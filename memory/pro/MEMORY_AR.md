# الذاكرة المستمرة — LocalSend Pro
آخر تحديث 2026-11-21

## توجيه المستخدم
نسخة Android فقط كأولوية؛ فورك alwansan/localsend-pro، فرع مستقل feature/android-pro-fast-transfer، استعمل GitHub Actions لبناء APK بعد تطويره، لا تسمِّ أي APK نهائياً قبل إكمال المتطلبات والتحقق من جهازين. عندما يكتب المستخدم Continue: اقرأ الحالة الحية أولاً ثم نفذ المرحلة التالية بدون تكرار الأسئلة والإصلاحات السابقة.

## المتطلبات الثلاثة
1) محرك نقل سريع مستوحى من miniserve، زر مفعل افتراضياً ويحفظ حالته.
2) اتصال Hotspot/direct إذا متاح، زر مفعل افتراضياً ويحفظ حالته؛ كبديل عن الراوتر دون افتراض القدرة على إجبار اتصال صامت.
3) اختيار 5GHz تلقائيًا إذا الطرفان ونقطة الربط متوافقون؛ 2.4GHz fallback؛ يجب أن يعمل LAN عبر راوتر 5GHz حتى لو طُفئ hotspot. زر مفعل افتراضياً ويحفظ حالته.
يجب أن تتفاوض الهواتف وتتبادل القدرات وتختار route آمن؛ اقبل الملفات وفق سياسة LocalSend المعتمدة.

## المشكلة الملاحظة
بطء النقل هاتف→هاتف في LocalSend الأصلي. miniserve لاحظ المستخدم أنه يتباطأ مع الملفات الضخمة ثم يعود أسرع بعد إيقاف وتشغيل. لا نستنتج أن السبب دائماً buffer الراوتر. ضع آلية health وresume حقيقية لا إعادة نقل كاملة.

## حقائق مثبتة
Flutter 3.41.9 / Rust core / LocalSend 1.18.2. عميل Rust الحالي HTTP/1.1، server TCP_NODELAY، sender checksums off وreceiver checksums on افتراضياً. miniserve خادم ملفات HTTP، ليس معيار نقل سريع مستقل. Android يسمح LocalOnlyHotspot بحسب الجهاز/الصلاحيات؛ 5GHz قد لا يقبل فرضه في تطبيق عادي. TLS/cert pinning ينبغي الحفاظ عليه.

## بروتوكول الاستئناف في كل جلسة
1. تحقق من HEAD والفرع وحالة Actions، ولا تكتب إلا feature/android-pro-fast-transfer.
2. اقرأ prompt/RESTORE_LOCAL_SEND_PRO_AR.md، memory/pro/STATE.json، docs/pro/PLAN_AR.md.
3. تابع المرحلة التالية، افحص الاختبارات والتوافق، اكتب تغييرات حقيقية؛ لا تزعم اختباراً لم يحدث.
4. حدّث STATE + MEMORY + RESTORE برسالة صريحة: ما نُفذ، ما فشل، ما التالي، آخر commit وروابط البناء.
5. احفظ السلامة أولاً: الحزم القديمة والتوافق، لا تسرّب بيانات Hotspot ولا تنقل ملفات ناقصة.

## روابط
https://github.com/localsend/localsend
https://github.com/svenstaro/miniserve
https://play.google.com/store/apps/details?id=com.sharekaro.app

## سجل تنفيذ المرحلة التأسيسية — 2026-11-21
في feature/android-pro-fast-transfer: تمت إضافة التخزين المستقل لإعدادات النقل/الهوتسبوت/5GHz + لوحتين بالواجهة، planner مستقل مع اختبارات 2.4/5/LAN/legacy، مراقب هبوط سرعة مع اختبارات، كشف Android WiFi في Kotlin وDart، واستدعاءات بدء/إيقاف LocalOnlyHotspot مع طلب صلاحيات. Workflow Android ARM64 تشخيصي على push. غير منفذ بعد: التفاوض بين الطرفين، اتصال جهاز المستقبل بالهوتسبوت، اختيار النطاق الفعلي، استئناف upload مع offset، إصلاح تلقائي لشبكة متدهورة، اختبار جهازين، إثبات نجاح بناء APK. لا تدعي اكتمال أي منها.

## متابعة Continue — جلسة 2026-11-21 (P1/P3 جزئي)
- على فرع feature/android-pro-fast-transfer فقط: أضيفت وصلة **ProWifiJoin.kt** للمستقبل Android 10+ باستعمال WifiNetworkSpecifier وConnectivityManager.requestNetwork مع موافقة Android، وإرجاع NetworkHandle كمعرف لمسار شبكي مقترح، حالة الاتصال، IPv4 المحلي، وإلغاء صريح بدون bindProcessToNetwork.
- أضيف Dart bridge **pro_wifi_join.dart** واختبار **pro_wifi_join_test.dart** (مكتوب وغير منفّذ على CI بعد). Manifest يصرح بـ CHANGE_NETWORK_STATE وACCESS_NETWORK_STATE.
- أُصلح سباق إلغاء startLocalOnlyHotspot: generation token يمنع callbacks القديمة من إحياء نقطة اتصال بعد الإلغاء، ويُنهي pending result عند الإلغاء.
- مهم: **لا ربط لمحرك Rust بالشبكة بعد؛ لا تبادل مؤمّن لكلمة مرور hotspot؛ لا اتصال مباشر تلقائي end-to-end؛ لا resume**. لا تستعمل شبكة الجديدة للنقل حتى يتحقق socket binding وauthentication.
- GitHub Actions: توجد Workflow pro-android-diagnostics.yml، ولكن نتائج push CI غير متحقَّق منها؛ أداة commit runs تعرض PR فقط. لا تدّع نجاح APK/اختبارات.
- كومِتات الكود: bcac11292ee4a69301763b8bb78104710f12b902 ،02560c8dfdaad0dab821f4452c59e3c9190f33bf. ابدأ في الجلسة التالية بفحص HEAD الجديد وSTATE ثم أكمل التفاوض الآمن وربط مسار Rust.
