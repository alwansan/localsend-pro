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
