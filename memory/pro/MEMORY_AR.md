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

## Continue — جلسة 2026-11-21، دفعة الشبكة/الصحة/الاستئناف
- كومِت `ee37899fc129dc66f6c4f9d695cdbbd9811d1a46`: `ProWifiJoin.probeIpv4` باستخدام Network.socketFactory من الشبكة التي وافق عليها Android، من thread منفصل، IPv4 محلي فقط، مع قياس latency ونتيجة reachable؛ channel/Dart وDart tests؛ **هذا TCP probe فقط، لا يتحقق من TLS ولا يوجّه Rust HTTP**.
- كومِت `dc5b38744df68532f63db48e73dde99865129642`: مراقب `ProTransferTelemetry` حي مرتبط بHttpUploadFileStarted/Progress/Finished/Failed وبحالات إلغاء الجلسة، وTimer كل ثانية حتى يلتقط توقف وصول أحداث التقدم؛ عرضه في تفاصيل صفحة إرسال الملفات. لا يتحكم بالنقل إطلاقاً، وبياناته هي bytes المقروءة من المرسل وليس bytes المؤكدة على المستقبل.
- كومِت `b5ac64c32a99accc568505d746e5b872db2be7e3`: `ProResumeLedger` (Dart pure): hash SHA256 لكل جزء، حدود 4MiB، session+file identity، stage ثم receipt بعد confirmDurableWrite، idempotent duplicates، منع jump/gaps، final hash verification؛ اختبارات فشل الشبكة والتكرار والأجزاء الخاطئة والملف الفارغ. **لا يستخدمه transport الحي بعد، ولا توجد كتابة أو checkpoint على القرص أو endpoint استئناف.**
- كومِت `a17f09faac518c0ea9d11c5bf2295a64141ec33e`: CI يحلل send_provider وprogress_page مع pro/tests؛ يحفظ DEBUG APK مع SHA256SUMS وBUILD_INFO عند نجاح البناء. لا يوجد دليل على CI أخضر من الأداة المتاحة.
- الأولوية القادمة: capability exchange مؤمّن عبر pinned TLS، Android Network socket binding لعميل Rust، ثم persistent chunk checkpoint/offset API، ثم اختبارات الجهازين؛ احتفظ fallback LocalSend v2.

## Continue 2026-11-21 — P4 disk checkpoint + verified CI
- كود جديد منشور في commit `00006b079fbea776007555d85d86d8c59285f86a`: ملف `app/lib/pro/resumable_file_store.dart` و`app/test/unit/pro/resumable_file_store_test.dart` (اختبارات إعادة الفتح، كتابة .part والـcheckpoint، رفض التلف، استبعاد bytes غير المؤكدة، التكرار، mismatch hash/identity، والملف الفارغ).
- تخزين Offline/داخل app-private directory فقط، ليس endpoint أو sender/receiver transfer في LocalSend الحالي؛ بعد file.flush يكتب manifest مؤقتة ويعمل same-directory rename ثم ledger confirms. عند الاسترجاع يتحقق من كل chunk؛ حماية انقطاع الطاقة المفاجئ الكاملة تحتاج native fsync للدليل وأقفال تسلسلية وintegration لاحقاً.
- **CI مثبت لأول مرة**: Run https://github.com/alwansan/localsend-pro/actions/runs/44944767568 ؛ Job Pro policy tests ID 136969617732 ناجح، Dart analyze ناجح و**34 اختبار Flutter ناجحة**. Android ARM64 job ID 136969942311 قيد التشغيل وقت التحديث، لا APK مؤكد.
- ملاحظة مهمة: كافة الـpush السابقة المتقاربة ألغت Actions قبل الإكمال بسبب `concurrency.cancel-in-progress=true`. لا تكتب تغييرات كود جديدة أثناء بناء Run 44944767568 كي لا تلغيه. تحديث هذه الوثائق فقط يتم بـcommit message `[skip ci]`.

## Continue 2026-11-21 — Rust Pro negotiation + CI fix
- [x] <https://github.com/alwansan/localsend-pro/commit/c9159d8b3c7cc5cb1fa1b2f94cb7d2779e1ea875> أُضيف HTTP ProCapabilitiesDto v1 و`GET /api/localsend/pro/v1/capabilities` في Rust، مقيّد بوجود TLS client certificate وLocalSend v2 runtime؛ عميل V2 يستعمل الـHTTPS pinned reqwest client فقط، ويعامل 404 كطرف قديم. **لا تنقل passwords أو tokens أو أسماء أجهزة**. كل أعلام الميزات غير المكتملة false.
- [x] <https://github.com/alwansan/localsend-pro/commit/1258d5d26fcc23d257a65b4fa114a71586d55722> أضيف wrapper على LsHttpClient وRust tests لمنع HTTP/unpinned probes ومعيار الإعلان عن القدرات.
- [x] <https://github.com/alwansan/localsend-pro/commit/8cee4d8802e02525362bfaf5d3b1b816b4b332a1> فحص Rustfmt الأول فشل من اختلاف تنسيق ملفات legacy غير معدلة؛ حُدِّد نطاقه لملفات Pro المتأثرة وصُلّح سطرا import + URLs. Workflow يختبر `cargo +1.97.1 test -p localsend --features http --lib`.
- ✅ GitHub Actions Run 44944767568 `SUCCESS` على Source commit 00006b0: Dart analyzer و34 test Flutter، وبناء Android ARM64 Debug وArtifact 14723396847 باسم `LocalSend-Pro-Android-arm64-DIAGNOSTIC`، ZIP size 93,785,397 bytes، ينتهي 2026-12-05. هذا APK تشخيصي سابق لإضافة Rust negotiation، **ليس النهائي**.
- 🔄 Run 44946218918 لكود Rust الجديد: fmt نجح وRust test كان يشتغل عند الحفظ؛ راقب وتحقق. لا تضف commits عادية تلغيه؛ تحديث الوثائق [skip ci].
- المتبقي: Flutter/FRB integration للتفاوض، hotspot pairing آمن، Rust per-socket Network binding، chunk uploader+checkpoint/ACK end-to-end وAndroid two-phone tests.

## حالة CI المؤكدة — تكملة 2026-11-21
- Run 44946218918: `pro-rust` job 136974049811 **نجح**: Rustfmt المخصص + `cargo test -p localsend --features http --lib` = **82 tests passed, 0 failed**. من ضمنها `http::pro::tests` و`http::server::pro::tests` و`http::client::v2::pro_tests`.
- `pro-unit` job 136974049953 **نجح** (Flutter analyzer/tests). ARM64 job 136974325851 ظل قيد التشغيل عند تسجيل هذه المعلومة.
- احفظ آخر مصدر كود 8cee4d8 وdocs HEAD الفعلي؛ لا تخلط build الأقدم الناجح 44944767568 بمصدر Rust الجديد. لا تعلن APK النهائي.
