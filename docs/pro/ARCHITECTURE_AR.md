# المراجع التقنية — Android Pro
## مسارات المشروع
- Flutter UI: app/lib/pages/tabs/settings_tab.dart وsend_tab.dart
- Persisted settings: app/lib/provider/persistence_provider.dart (SharedPreferences)، Refena: settings_provider.dart
- Rust client: packages/core/src/http/client/mod.rs
- Rust server: packages/core/src/http/server/mod.rs
- File streaming: packages/core/src/model/transfer.rs
- Send controller/hashing: app/lib/provider/network/send_provider.dart
- Android channel: app/android/app/src/main/kotlin/org/localsend/localsend_app/MainActivity.kt
- Android manifest: app/android/app/src/main/AndroidManifest.xml
- CI: .github/workflows/build_android_apk.yml (existing upstream release workflow requires signing secrets).

## تمييز ثلاثة مستويات
1) النقل: HTTP/HTTPS (يتضمن HTTP/1.1 بالفعل).
2) الرابط: Wi-Fi عبر راوتر LAN أو local-only hotspot/Direct عند الإمكان.
3) التفاوض: capabilities + consent + اختيار route؛ لا تختر 5GHz من اسم الزر بل من قدرات STA/AP والرابط الفعلي.

## نظام اختيار المسار
- تجنب القفز من LAN 5GHz جيد ومتوفر إلى Hotspot أبطأ دون قياس أو رغبة المستخدم.
- إذا خيار hotspot مفعّل ولم يوجد LAN مناسب واستوفى الطرفان القدرات/الموافقات، حاول direct.
- إذا طرف لا يدعم 5GHz على الرابط المطلوب، 2.4GHz.
- إذا الجهاز الآخر LocalSend قديم: fallback إلى LocalSend V2 بلا رسائل مخصصة تكسر البروتوكول.
- اتصالين عبر نفس الراوتر لا يعني أن الاثنين على 5GHz؛ افحص طرفين + نطاق AP وموقع socket/route.
- لجهاز Android عادي لا تُفترض صلاحية التحكم الصامت بنقطة اتصال tethered أو انتقاء BAND_5GHZ: startLocalOnlyHotspot عادي وقد يختار النظام band، وWifiNetworkSpecifier قد يظهر طلب موافقة.

## Recovery state machine (مخطط)
idle → negotiating → transferring → (degraded) → probing → recovering → transferring/failed
- health check على window متحركة لا على عينة واحدة؛ عند الهبوط فحص bytes/sec، استمرار تقدم bytes، مدة توقف، RTT، reader/writer queue.
- عند فشل الشبكة: client يسأل عن offset المحفوظ على server؛ لا يعيد إرسال إلا من offset معرّف وموثّق، مع chunk IDs/etag أو hash؛ لا تُعلن success حتى verify+commit.
- عند أقدم سيرفر لا يدعم offset: لا ندّعي resume دون دعم؛ استخدم retry آمن يخبر المستخدم بالحقيقة.
- جودة الرابط تكون متغيرات: عينة Mbps + band + reconnectCount + battery/thermal + I/O backlog.

## ملاحظات مراجعة الأداء 2026-11-21
- النقاش القديم #3329 يذكر ضبط HTTP/2/TCP_NODELAY؛ الشيفرة الحالية فيها بالفعل HTTP/1.1 فقط وTCP_NODELAY. checksum على المرسل false حالياً، فلا تعتمد نتائج نقاش 2026-08 كما هي.
- miniserve لديه HTTP range للتحميل وparallelism لكن HTTP Range وحده لا يحقق resumable upload آمن؛ هذا يحتاج دعم الطرفين وتخزين session offsets.
- لا نأخذ تفاصيل proprietary internal لShareKaro من افتراضات التسويق.

## الإطلاق
- P0/P1 لا يعني final: build diagnostic artifacts منفصلة؛ final فقط بعد اكتمال مراحل P2–P7 والاختبارات.

## إضافة تقنية 2026-11-21 — Android receiver association
- `ProWifiJoin.kt`: بعد إذن NEARBY_WIFI_DEVICES أو ACCESS_FINE_LOCATION حسب إصدار Android، يبني WifiNetworkSpecifier للـSSID وWPA2 passphrase ويتصل عبر ConnectivityManager.requestNetwork مع نافذة النظام. لا يستخدم bindProcessToNetwork؛ NetworkHandle المرسل للـDart لا يعني أن Rust صار يوجّه TCP عبر هذا المسار.
- `pro_wifi_join.dart`: Future join, isConnected, leave. يُستخدم فقط بعد تفاوض/موافقة موثقة؛ لا تخزن credential ولا تُرسل في رسائل اكتشاف عادية. لا تروّج اكتمال هذه الخطوة على أنها automatic transfer.
- `ProLocalOnlyHotspot.kt`: generation counter يلغي callbacks غير الحالية ويغلق reservation قديمة بعد الإلغاء. Lifecycle cleanup في MainActivity.onDestroy.
- متطلب تكامل لاحق: مرّر NetworkHandle إلى طبقة نقل Android/Rust موثوقة، واربط sockets الفردية بدل تغيير default network لكل العملية، ثم اعمل TLS pinning وفحص reachability وthroughput قبل التبديل.
- GitHub Android diagnostics غير مثبت نجاحه؛ لا تخمّن نتائج CI.

## تفصيل تطبيق P1/P3/P4 — Continue 2026-11-21
1. Native Android `ProWifiJoin.probeIpv4` يستعمل Network.socketFactory لإنشاء socket مؤقت مرتبط حصراً بالشبكة الموافق عليها، مع timeout=2500ms، دون DNS ولا Internet IP ولا UI blocking؛ النتيجة reachable/elapsedMillis فقط. عميل LocalSend Rust لم يتحول إلى الشبكة الجديدة ولم نضمن شهادة TLS على هذا probe.
2. ربط Rust لاحقاً: Android NDK API `android_setsocknetwork()` أو `Network.bindSocket(fd)` ممكن على socket منفرد قبل connect؛ تكامل reqwest يحتاج connector يُنشئ sockets مبكراً ويتحفظ على ALPN + TLS client auth/pinning وعدم proxy. إياك تستخدم bindProcessToNetwork كحل سريع لأنه قد يقطع discovery والاتصالات الجارية. راجع https://developer.android.com/ndk/reference/group/networking.
3. `ProTransferTelemetry` يتلقى progress عند قراءة محتوى HTTP body من Rust؛ read bytes ليست receiver persisted/ACKed bytes. لا retry/reconnect تلقائي إلا بعد دعم offset الموثوق. Timer واحد مشترك خلال عمليات الإرسال، والمراقبة تنتهي عند completed/failed/cancel.
4. `ProResumeLedger` فعلاً يحدد staged vs confirmed offset، يتحقق SHA256 لكل chunk، لا يَقبل duplicate إلا إذا تطابقت metadata/hash، ولا يعلن verified قبل اكتمال الحجم وبصمة محتوى مستقبل كاملة. **المتكامل مع القرص لاحقاً يجب أن يعمل fsync+checkpoint قبل confirmDurableWrite ويزيل أي bytes غير مؤكدة عند إعادة الفتح.** لا expose API خارجي أو تحوّل إلى engine حي حتى يتوفر persistent resume negotiation.
5. لا تبادل كلمة مرور hotspot عبر multicast أو discovered metadata، ولا اعتماد على TCP probe دون TLS pinned fingerprint. احتفظ باختبار LAN/hotspot وfallback لـLocalSend القديم.
6. Workflow Pro يقوم بتحليل live send/progress، وAndroid debug artifact يحتوي SHA256SUMS وBUILD_INFO إذا نجح. نجاح البناء لم يتم إثباته، لذلك لا APK نهائي.

## ملاحظات مخزن الاستئناف P4 — 2026-11-21
- `ProResumableFileStore.open(directory, sessionId, fileId, expectedSize, expectedSha256Hex)`: أسماء الملفات مشتقة SHA-256 من session+file، *يجب* استعمال app-private directory؛ الاعتماد على هوية جلسة موثقة قبل استدعائها على شبكة حقيقية.
- `append`: التحقق من hash 4MiB max وترتيب offset والهوية، الكتابة إلى .part مع flush، تجميع checkpoint متتالٍ وإغلاق temp ثم rename، وبعدها فقط confirmDurableWrite؛ أي خطأ يبقي ledger offset دون تقدم.
- `open` بعد انقطاع البرنامج: parse نسخة checkpoint المتزامنة، تحقق كل chunk من bytes على القرص وبصمته وأعد إنشاء ledger؛ truncate tail غير موثق؛ إذا metadata/file mismatch تعطل بدلاً من فقد/تخطي bytes.
- `verifyComplete`: stream SHA256 عبر File.openRead دون تحميل ملف كامل، ثم التحقق من الحجم والبصمة؛ لا يعمل publish نهائي؛ يحتاج atomic rename وحماية وجهة SAF.
- حدود حالية: لا cross-process file lock، إعادة فتح مخزن متعدد الكتّاب غير معرّفة؛ Dart filesystem flush + rename لا يضمن strict power-loss durability دون fsync لدليل metadata على Android؛ لا تستخدمه على UI isolate للملفات الكبيرة.
- اختبارات Pro نجحت 34 على Actions Run 44944767568، ولم يُثبت نجاح Android ARM64 debug build بعد.

## Rust Pro capability API — 2026-11-21
- الجديد `GET /api/localsend/pro/v1/capabilities`: route مستقل في `packages/core/src/http/server/mod.rs`, المخرجات JSON schema=1. لا يتاح إذا v2 disabled أو طلب من دون client TLS certificate. لم يعدّل الlegacy `/api/localsend/v2/`، ولا يغيّر سلوك ملفات المستخدم.
- `http/pro.rs` يعلن pinnedTlsRequired=true وresumableUpload/hotspotCoordination/networkBoundUpload=false,maxChunkBytes=0 لأن الشبكة/استئناف البيانات **لم يكتمل**. لا تضمّن password/token/session data بأي إعلان عام.
- `LsHttpClientV2.pro_capabilities` يرفض غير HTTPS أو client غير pinned، ثم يتصل عبر rustls reqwest المعتاد الحافظ لـTLS fingerprint؛ 404→None (legacy fallback)، الإعلان غير المدعوم→None. `LsHttpClient.pro_capabilities` يمرر V2 فقط، V3→None.
- لم تُربط دوال Rust الجديدة بعد بـDart FRB ولا بمسار الإرسال، لذلك لا تدعي فعلية التفاوض بين الهاتفين.
- Rustfmt CI أُصلح حتى يفحص ملفات Pro المعدلة فقط بدلاً من تغيير legacy/generated files. Rust unit tests تشتغل في Run 44946218918 حين تحديث الوثائق؛ Run سابق 44944767568 ناجح على commit أقدم.

## Bridge/UI connectivity — 2026-11-22
- توليد واجهات Flutter–Rust يتم عبر `flutter_rust_bridge_codegen 2.12.0` و`.github/workflows/pro-frb-bindings.yml`، وليس بكتابة `lib/rust/frb_generated.dart` أو `rust/src/frb_generated.rs` يدوياً. عُولج نقص rustfmt في CI؛ أُنتج commit 8e0f82f، Run 44949823398 ناجح.
- `RsHttpClient.proCapabilities` يرجع `RsProCapabilities?` عبر pinned reqwest Rust TLS، يرفض HTTP أو client ليس له peer fingerprint؛ يرد None عند 404 legacy. الـDTO ما زال يعطي flags false للـlive resume/hotspot/network bound.
- `app/lib/pro/pro_peer_capabilities.dart` يختار قناة HTTPS غير فاشلة فقط عند وجود 64-char SHA fingerprint صالح؛ `pro_peer_capabilities_panel.dart` يعرض **Manual Check** في Device Details Android، لا يغير مسار النقل/الشبكة، يمنع عرض استجابة طلب لجهاز قديم بعد تغيير widget.
- اختبارات Rust `v2_tls_pinning.rs` زيدت بفحص متماثل حقيقي TLS وقيد mTLS حتى مع WebMode enabled، ومرّت: 8 integration + 82 lib. Flutter unit: 39 passed في Run 44950400113. لا تعادل هذا باكتمال النقل بين هاتفين.

## Native file lease — 2026-11-22
- `RsProFileLease` في `packages/localsend_isolates/rust/src/api/pro_file_lease.rs` يحجز ملف `.lease` منفصلاً (لا يُحذف قط بالإنتاج)، عبر open(O_NOFOLLOW,0600) ثم `flock(LOCK_EX|LOCK_NB)`. بعكس قفل Dart fcntl على Unix، قفل flock مرتبط بـopen-file-description؛ مقابض مستقلة بين isolates أو processes تتنافس. لا يوجد انتظار بلا نهاية؛ failure→no writer. release/Drop/process crash يغلق fd ويحرر القفل؛ القفل على app-private canonical storageId الذي يحسب SHA256(sessionId+NUL+fileId).
- `ProResumableFileStore.open`: يسجّل canonical path محلياً، ثم على Android يستدعي `acquireProFileLease(path: '$base.lease')` قبل أي قراءة أو truncation للـpart/checkpoint؛ التخصيص السابق للـledger لا يعدّل القرص. عند open error يحرر native lease ويحذف in-isolate reservation. `close` يرفض أثناء append/hash، ويحرر native lease ثم in-isolate registry. Desktop tests لا تحتاج تحميل RustLib لأن الشرط Platform.isAndroid.
- `ProResumableFileStore.append` يحظر إعادة استعمال الـhandle بعد خطأ file/checkpoint I/O لأن rename قد يكون نجح قبل ظهور الخطأ؛ `open` التالي فقط يراجع checkpoint/bytes. إذا `.part` orphan غير فارغ وcheckpoint غائب، يحفظه ويتوقف. `verifyComplete` يحجز busy flag أثناء hashing ويغلق handle عند فساد النتيجة.
- Rust native lease codegen v2.12.0 في workflow pro-frb-bindings.yml، Run 44951796090 نجح ونشر 8f4d466 + Cargo.lock. Run 44952326531 لربط Android الأخير ما يزال بحاجة فحص.
- هذا قفل تخزين محلي فقط: لم يتم دمجه بعميل/خادم LocalSend v2 واستئناف نقل الشبكة أو ضمان power loss fsync/directory publishing.
