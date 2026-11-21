# LocalSend Pro Android — خطة التنفيذ
آخر تحديث: 2026-11-21 | فرع الكتابة الوحيد: feature/android-pro-fast-transfer

## الهدف
نسخة Android ذات إرسال واستقبال محلي سريع، تلقائي، آمن، قابل للاستئناف بعد انقطاع أو هبوط. لا إعلان عن APK نهائي قبل إكمال الاختبارات على هاتفين.

## حقيقة البنية الحية (خط الأساس)
- Flutter 3.41.9، Rust core عبر FFI، تطبيق LocalSend 1.18.2، LocalSend v2 HTTPS/HTTP في الشبكة المحلية.
- المحرك الموجود يستخدم بالفعل ALPN HTTP/1.1؛ يوجد set_nodelay على مقبس استقبال TCP؛ وgetCreateChecksums() افتراضه false، والتحقق عند الاستقبال true. لا تكرر إصلاحات قديمة.
- miniserve خادم HTTP سريع بRust وليس بروتوكول شبكة بديل؛ نستفيد من الأفكار (streaming، bounded buffering، range)، دون استبدال آلية LocalSend أو نسخ الشيفرة بلا مراجعة رخص/توافق.
- ShareKaro مرجع لسلوك UX، وليس دليلاً موثوقاً على بروتوكوله الداخلي.
- القيود: Android العادي يتيح LocalOnlyHotspot بشروط وصلاحيات؛ اختيار 5GHz كـ SoftAP ليس مضموناً لتطبيق غير نظامي. اتصال Wi-Fi جديد قد يحتاج موافقة المستخدم.

## السلوك المطلوب
1. acceleratedTransport: مفعّل افتراضياً. متوافق مع LocalSend التقليدي عند عدم دعم الطرف الثاني.
2. preferDirectHotspot: مفعّل افتراضياً. يُعرض خيار نقل مباشر، لكن لا يقطع شبكة عاملة إلا عندما يكون الربط المباشر متاحاً وبعد موافقات النظام.
3. prefer5GHz: مفعّل افتراضياً. يتفاوض الطرفان على الإمكانات؛ 5GHz فقط إذا كان AP يدعمه والعميل يدعمه والرابط الفعلي عليه. إن تعذر فـ 2.4GHz أو LAN الحالي.
كل الإعدادات مستقلة ومستمرة بعد إغلاق التطبيق.

## خطة المراحل ومقاييس القبول
- P0 (الآن): قراءة البنية ومراجعة التحقيقات، فرع خاص، ملفات الذاكرة، قواعد الاختيار واختبارات وحدات وGitHub Actions تشخيصية، واجهة تفضيلات مبدئية.
- P1: قياس معدل النقل الحقيقي على 2.4GHz و5GHz، مدة التهيئة، CPU/RAM، hashing، SAF read/write، backpressure، مشاكل router/thermal؛ تخزين نتائج الهاتفين.
- P2: capability exchange additive/opt-in عبر تفاوض صريح بعد التعرّف على الجهاز. معيار الأمان: لا إرسال أسرار نقطة الاتصال في discovery العام ولا تغيير البروتوكول لأجهزة قديمة.
- P3: Android LocalOnlyHotspot وطلب الانضمام على الجهاز الثاني عبر واجهات Android العامة وموافقة OS الضرورية؛ سجلات حالة وعودة آمنة إلى LAN. لا نفترض إمكان تشغيل tethered hotspot/ضبط 5GHz دون صلاحيات نظام.
- P4: نقل محسّن للملفات الضخمة بstreaming ومن دون buffering شامل. نقل مجزأ مستقل مع offset مؤكد وقابل للاستئناف فقط بعد توثيق خادم/عميل متوافقَين؛ verification (size + per-chunk/final hash)، وatomic rename، وشروط عدم التكرار.
- P5: Network health/recovery: نافذة سرعة متحركة، حدّ أدنى مستمر، تمييز stall عن slowdown، probe أولاً، إغلاق اتصال معطوب وإعادة التفاوض فقط عندما يكون الاستئناف معتمداً؛ backoff؛ عدم إعادة بدء ملف كامل أو فقد البيانات.
- P6: UI على الإرسال والإعدادات مع 3 مفاتيح تفضيل محفوظة، status صريح (LAN 2.4/5، direct 2.4/5، fallback)، اختيار يدوي، وموافقات المستخدم دون طلب صلاحيات زائدة.
- P7: GitHub Actions تحليل + Android ARM64 debug APK تشخيصي، تجارب 2 جهاز كبير/صغير/اختلاف قدرات، 100% hash matches، إكمال الاستئناف، اختبارات أمان وتوافق وإصدار APK نهائي عند قبول المستخدم.

## أولويات الأداء
لا تقيس نجاح النقل بمعدل لحظي فقط: أحسب MB/s sustained وp50/p95، total transfer time، peak RSS، overheating، drops، retransmits، file read/write time. لا توقف النقل تلقائياً لمجرد أن السرعة نزلت؛ السبب قد يكون التخزين أو الجهاز أو التداخل وليس ذاكرة الراوتر.

## سياسات الأمان والتوافق
- default HTTPS + TLS fingerprint pinning، وحافظ على طلب قبول النقل الطبيعي.
- لا تشغّل HTTP بلا TLS افتراضياً، ولا تنشر كلمة مرور Hotspot في logs.
- لا تغيير فروع main/upstream. تحديث RESTORE_AR.md وSTATE.json عقب كل مرحلة/commit.
- لا تروج 5GHz بوصفه بروتوكول نقل: هو نطاق لاسلكي، وسرعة الفعلية تتغير حسب الهواتف والراوتر وWi-Fi generation.
- لا تغلق اتصالاً فاشلاً/تنشئ جلسة جديدة بلا آلية offset موثوقة. لا فقدان أو استبدال ملف مكتمل.
- لا تدّع تشغيل البناء أو اختبار الأجهزة ما لم يتم التحقق من نتائج GitHub Actions/هواتف فعلية.

## روابط مرجعية
- https://github.com/localsend/protocol
- https://github.com/svenstaro/miniserve
- https://github.com/localsend/localsend/discussions/3329
- https://developer.android.com/reference/android/net/wifi/WifiManager
- https://developer.android.com/reference/android/net/wifi/WifiNetworkSpecifier

## تحديث التنفيذ الأول — 2026-11-21
- [x] إنشاء الفرع وملفات الذاكرة والاستعادة والتصميم.
- [x] مفاتيح التفضيل الثلاثة الافتراضية والحفظ وظهورها في واجهتي Android.
- [x] سياسة اختيار route قابلة للاختبار، لا تؤثر على حركة النقل الحي بعد.
- [x] كشف إمكانات Wi-Fi المحلية فعلياً عبر Kotlin، مجهولة hotspot band إذا لم يُثبت النظام.
- [x] MethodChannel لبدء/إيقاف LocalOnlyHotspot مع طلب الأذونات عند الاستخدام، ليس مفعلاً ضمن تدفق الإرسال.
- [x] مراقب throughput لا يتلف النقل، اختبارات وحدة مكتوبة.
- [x] إعداد CI تشخيصي ARM64 (لم يُتحقق من تشغيل ناجح).
- [ ] تفاوض المرسل والمستقبل وربط الشبكة ونقل البيانات عبرها.
- [ ] آلية chunks/offset/resume + integrity للحالتين.
- [ ] ربط مراقب الصحة بمسار التعافي الآمن.
- [ ] Android CI confirmed green ثم جهازين وAPK النهائي.

## تحديث Continue — 2026-11-21 (P1/P3)
- [x] إضافة Receiver join bridge على Android 10+ بواسطة WifiNetworkSpecifier وموافقة النظام، واستعلام الحالة وleave دون تغيير default routing للتطبيق؛ كود فقط ولم يُختبر على جهاز.
- [x] حماية LocalOnlyHotspot من رد البدء المتأخر بعد الإلغاء (generation guard + release).
- [x] إضافة تصريحَي ACCESS_NETWORK_STATE وCHANGE_NETWORK_STATE الضروريين لطلب Network.
- [x] اختبارات Dart لواجهة join/status/leave مكتوبة وغير منفّذة بعد.
- [ ] Authentication/capabilities exchange بين الهاتفين، نقل credentials بمسار مؤمّن ومحدّد الجلسة، وتجنب نشرها في multicast أو logs.
- [ ] ربط sockets الخاصة بالنقل عبر Android Network handle، مع فحص موثوق قبل التحول، بدون bindProcessToNetwork.
- [ ] إظهار حالة الاتصال الفعلي بالمستخدم، cleanup عندما تفشل أو تُلغى العملية.
- [ ] CI Android + اختبارات هاتفين + قياسات فعلية + safe resume. لا APK نهائي.

## تحديث Continue — دفعة تنفيذ 2026-11-21
- [x] Android consented Network TCP probe بSocketFactory خاص بالشبكة ومن دون تغيير default network؛ رقم زمن الاتصال فقط ولا يعتبر TLS identity proof.
- [x] Telemetry على تدفق Upload events + tick دوري لرصد silence؛ لا يتدخل بالملفات ولا يقطع الاتصالات.
- [x] عرض health read-stream في Advanced progress (sender only؛ ليس ACK المستقبل).
- [x] ProResumeLedger للـchunk hashing وoffset المرحلي وACK بعد دوام التخزين ورفض التكرار الفاسد؛ اختبارات مكتوبة.
- [x] CI Pro يفحص التكامل في send/progress ويضيف checksum وأثر commit لـDebug APK إذا نجح البناء.
- [ ] ربط TCP المقبول بـReqwest/Rust مع fingerprint verification.
- [ ] تبادل peer capabilities الموثق والموافقة قبل نقل كلمات مرور Hotspot.
- [ ] كتابة فعليّة آمنة لملف جزئي وcheckpoint durable وعملية استئناف تلقائية مع endpoint لـoffset.
- [ ] قياس receiver ACK وsocket/network telemetry وbenchmark هاتفين؛ لا تفسر Sender read-progress على أنه completed transfer.
- [ ] إثبات نتائج CI/Android build؛ test files مكتوبة فقط وغير منفذة.

## تحديث 2026-11-21 — P4 store وCI مثبت
- [x] ProResumableFileStore مستقل: .part وcheckpoint manifest، flush، rename، replay والتحقق SHA لكل chunk، تجاهل trailing speculative bytes، رفض corruption/mismatched identity، لا إعادة إرسال bytes مؤكدة دون موافقة المستقبل.
- [x] اختبار مكونات Pro في CI `44944767568`: Dart analyzer ناجح و34 اختباراً ناجحاً.
- [~] ARM64 debug diagnostic build ضمن نفس Run — قيد التشغيل عند حفظ الحالة، لا APK نهائي.
- [ ] مسار بروتوكول فعلي بين المستقبل والمرسل (authenticated receiver offset, file token, chunk hashes, idempotent ack, TLS fingerprint).
- [ ] ضمانات strict power-loss fsync + concurrent file lock + safe final rename.
- [ ] تلقائي 5GHz/Hotspot مع Android Network-specific Rust binding + consent, ثم اختبار فعلي على هاتفين.
- [ ] جعل CI لا يلغي تشغيل البناء بسبب commits خاصة بالوثائق؛ استعمل [skip ci] مؤقتاً.

## تحديث متابعة — بروتوكول Rust وبناء Android 2026-11-21
- [x] Android ARM64 diagnostic build ناجح من GitHub Actions 44944767568 (commit 00006b0) + 34 Dart unit tests؛ artifact 14723396847 (Debug غير نهائي).
- [x] Pro Rust read-only capability endpoint (mTLS client certificate required) وعميل V2 pinned HTTPS-only؛ ترجيع None عند 404 للأجهزة القديمة؛ بروتوكول v2 الأصلي لم يتغير.
- [x] Rust unit tests للـcapabilities والـHTTPS pin gating وURLs IPv4/IPv6؛ Workflow Rust test. تعديل نطاق formatter حتى لا يُدخل تنسيق كامل legacy في المرحلة.
- [~] Run 44946218918 للشيفرة الجديدة ongoing؛ تأكد من Rust tests وAndroid build، وراجع النتائج قبل وصف أي Feature بأنه شغال.
- [ ] FRB وتجارب capability discovery بين هاتفين مع TLS pinned identity وفشل آمن، ثم consent/network socket-specific binding.
- [ ] Chunk resume protocol persistent ACK، واختبار إعادة الإرسال بعد توقف التطبيق والشبكة؛ آلية النقل الحالية لا تستخدم هذا المسار حتى الآن.

- [x] CI الأحدث 44946218918 Rustfmt scoped + Rust HTTP core **82/82 passed**، وكذلك Flutter Pro unit job نجح.
- [~] ARM64 job 136974325851 من نفس التشغيل لم يكن قد انتهى عند توثيق النتيجة؛ تأكد منه قبل اختبار APK على الهاتف.

## تقدم 2026-11-22 — Flutter-Rust Bridge + manual peer check
- [x] إصلاح rustfmt في FRB generator، نجاح Run 44949823398، نشر generated bindings commit 8e0f82f.
- [x] إضافة Android Device Details manual Pro compatibility check مع pinned HTTPS، واختيار قناة صالحة، عرض advertised flags فقط. الطرف legacy يرجع إلى النقل المعتاد؛ لا يغيّر hotspot أو النقل.
- [x] Run 44950400113: 39 Flutter unit tests passed و82 Rust unit tests + 8 Rust TLS integration tests passed؛ لا فشل أو crash مُثبت بهذه الاختبارات.
- [~] APK ARM64 الأحدث Run 44950400113 job 136987215583 queued؛ اختبر نتيجته، لا تستعمل artifact الأقدم 14724103202 للتحقق من الشاشة الجديدة.
- [ ] تنظيف 3 معلومات lint للاستيرادات؛ ثم إكمال full transport opt-in، socket binding، checkpoint concurrency & directory fsync، واجهة receiver confirmed offsets.

## P4 — أمان التخزين متعدد الكُتّاب (2026-11-22)
- [x] منع كاتبين داخل نفس Dart isolate؛ حفظ non-empty orphan .part بدلاً من مسحه؛ إيقاف الـhandle بعد فشل checkpoint I/O؛ guard final SHA against append/early close.
- [x] Flutter 44/44 unit tests passing على Run 44951142687؛ Rust 82+8 TLS passing.
- [x] Rust native `flock` lease per session/file + generated FRB (Run 44951796090 SUCCESS، commit 8f4d466) + Android-only acquire/release integration (commit 2821e30).
- [x] إصلاح CI لإيقاف إلغاءات ARM64 السابقة: cancel-in-progress=false وAndroid needs both test jobs.
- [~] Run 44952326531 pending للـ44 Dart + native Rust lease tests + ARM64 APK. لا تدّعي النجاح بلا conclusion.
- [ ] Test two Android isolates with concurrent open, abnormal process termination and restart; include native fsync checkpoint directory & safe publish before release readiness.
- [ ] Network session token/chunk endpoints and durable receiver ACK; per-socket Android Network binding and permission-driven hotspot transition.

- [x] نتائج `44952326531`: Rust native file lease 2/2، Rust core 82/82، TLS integration 8/8، Flutter 44/44، Dart analyzer zero issues.
- [~] Android ARM64 job 136993506186 running; لا تختبر native lease APK من artifact الأقدم 14725669490 لأن source e89cbc4 ليس 2821e30.

## P4.2 — Durable resume offset/auth local foundations (2026-11-22)
- [x] Native lease-directory fsync after pending checkpoint rename, no ACK before fsync; native Rust tests 4/4 passed (total Rust 94) in run 44953715009.
- [x] FRB v2.12.0 generated `syncCheckpointDirectory` via run 44953715002 SUCCESS (commit fb25ea6), integrated into Android store commit da0b601f.
- [x] Local status gate `ProReceiverSessionGate`: verified mTLS fingerprint+session/file/hash+private token mandatory; unauthorized status null; no secrets in status. Six tests written and fast CI pending.
- [x] Confirm prior native-lock Android debug APK artifact 14726702057 (Run 44952326531, e.g. no directory fsync).
- [~] Fast tests run 44954233385 + latest ARM64 queued 44954233387. Check conclusions, fix failures, then checkpoint.
- [ ] Authenticated network status/chunk endpoints, verified durable network receipts, process-death Android tests, atomic final publish, approval-based Wi-Fi direct route / native socket binding.
