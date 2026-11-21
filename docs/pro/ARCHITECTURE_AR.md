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
