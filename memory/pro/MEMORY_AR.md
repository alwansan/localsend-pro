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

## Continue 2026-11-22 — اكتمل FRB/manual peer probe (بدون تبديل النقل)
- [x] أصلح CI generator missing rustfmt في commit `5e33e3d41c21a30bf60e8b1ecd671284b2b323a0`؛ Run 44949823398 **SUCCESS** ونشر ملفات Flutter–Rust المولّدة آلياً في commit `8e0f82fd6de5e83c69ae263123f6d3dcef9d0b21`. `RsHttpClient.proCapabilities` و`RsProCapabilities` موجودان في Dart الآن.
- [x] commit `6e6e3f3442bd868e8b5357fc4026d3ccfe9fce93`: `ProPeerCapabilitiesPanel` على Device Details Android، manual Check عبر قناة HTTPS مثبتة شهادة TLS من الهوية المعروفة، لا Hotspot أو transfer switch. مع `selectProCapabilityChannel` و5 unit tests، و2 TLS integration tests على خادم Rust فعلي.
- [x] Run 44950400113: Rust core **82 passed** + TLS integration **8 passed** (90 إجمالاً)، Flutter **39 passed**، Dart analyzer ناجح مع ثلاث informational lints تخص ترتيب imports. **ARM64 diagnostic job 136987215583 كان queued عند تسجيل الحالة**؛ افحص نهايته قبل القول APK ناجح على هذا commit.
- [x] آخر ARM64 APK ناجح مثبت *أقدم* من الواجهة الجديدة: Run 44947029359، artifact ID `14724103202` (93,785,991 bytes ZIP) من commit `6d191f4`. ليس APK نهائي ولا يتضمن تبديلات النقل.
- [ ] ما زال غير منفذ: automatic hotspot credentials negotiation, socket binding to selected Android Network, persistent authenticated chunk transfer endpoints, actual safe end-to-end resume, phone-to-phone benchmarks.
- لا تدفع كوداً عادياً أثناء ARM64 build إن أمكن بسبب cancel-in-progress=true؛ تحديثات docs استخدم [skip ci].

## Continue — 2026-11-22 — الاستئناف الآمن وقفل Android الأصلي
- [x] مصدر `e89cbc467577321a96f329ab7499dc93bb7a260c`: حراسة كاتب واحد داخل Dart isolate، عدم حذف orphan .part غير مؤكد، جعل handle يفشل نهائياً بعد خطأ I/O checkpoint، ومنع close/append أثناء final SHA. **44/44 Flutter tests passed** في GitHub Actions Run 44951142687؛ Rust core 82 وTLS 8 ناجحة أيضاً في هذا التشغيل. APK الخاص به كان ما زال يبني وقت التسجيل.
- [x] المصدر `8c670a8a4305978363f0d5bbae8b0885548e9c1a`: `RsProFileLease` native flock(LOCK_EX|LOCK_NB) على Android/Linux، lockfile دائم لا يُحذف، التحرير عند close/Drop أو crash، 2 Rust tests لتنافس fd/thread.
- [x] المصدر `faf52aa81ff37963cf69ee533dfa177c85990e5a`: diagnostics `cancel-in-progress: false` وAndroid needs both Pro Flutter and Rust jobs.
- [x] Rust Bridge generator `44951445191` فشل فقط بسبب تغيير Cargo.lock، ثم `ec31be51a2e9fa3f01201877c76c06f6ed5b1215` سمح بنشر lockfile، Run `44951796090` **SUCCESS** ونشر generated `RsProFileLease/acquireProFileLease/release` في `8f4d4661c7f8e4051109e0b307b36e3f1808d5ce`.
- [x] مصدر `2821e30fa471ef3406c425933e0c5450211b599f`: Android `ProResumableFileStore.open` يحصل على native file-description lease قبل قراءة checkpoint، ويحرره عند close أو فشل open؛ إذا فشل الحصول عليه لا يتابع بكتابة غير مقفولة. ثلاث ملاحظات imports cleanup.
- [~] **Run 44952326531** جديد على source 2821e30، حالته pending وقت checkpoint؛ تأكد من native Rust tests و44 Flutter tests وبناء ARM64 قبل القول إنه جاهز. آخر Android artifact مثبت قبل كل هذه الإضافات = ID 14724103202 من Run 44947029359.
- [ ] غير مكتمل: power loss directory fsync، atomic final publish، remote session chunk API/offset ACK، socket binding، automatic hotspot/5GHz link switch، device-to-device Android tests. **لا APK نهائي ولا استئناف فعلي عبر الشبكة.**

### تدقيق CI الأحدث — 2026-11-22
- Run `44952326531`: Rust job `136993136484` **SUCCESS**: 2 native flock lease tests + 82 Rust lib + 8 real TLS = 92 passing, 0 failures. Flutter job `136993136854` **SUCCESS**: 44 tests passed وDart analyzer `No issues found!`. أحدث ARM64 job `136993506186` قيد البناء وقت توثيق النتائج.
- Run `44951142687` السابق **SUCCESS** وAndroid diagnostic artifact ID `14725669490` (ZIP 93,847,409 bytes) مبني من source `e89cbc4` ولا يضم Rust native lease.

## Continue 2026-11-22 — fsync + authenticated local resume offset
- [x] Android native lease build **SUCCESS** Run [44952326531](https://github.com/alwansan/localsend-pro/actions/runs/44952326531) on commit `2821e30`: 44 Flutter tests + 92 Rust tests, ARM64 diagnostic artifact `14726702057` ZIP 93,865,523 bytes. لا يتضمن fsync الجديد ولا auth gate.
- [x] `85e6e702`: Rust `RsProFileLease.sync_checkpoint_directory` يستعمل `fsync` على app-private parent directory بعد `pending -> checkpoint.json` rename مع قفل حي؛ يرفض released lease أو symlink. 4 native Rust tests + 82 core + 8 TLS = **94 Rust tests pass** Run 44953715009. Bridge generator Run 44953715002 **SUCCESS**, published `fb25ea6`, Dart exposes `syncCheckpointDirectory()`.
- [x] `da0b601f`: Android `ProResumableFileStore._publishCheckpoint` يستدعي native directory fsync قبل `confirmDurableWrite`، فشل fsync يوقف ACK ويُسمّم handle حتى إعادة open/replay. `canReportVerifiedOffset` يمنع تقرير offset أثناء busy/close.
- [x] `da0b601f`: `ProReceiverSessionGate` محلي فقط: يربط verified TLS peer certificate fingerprint مع session ID + file ID + expected complete SHA256 وper-file secret token hashed in memory؛ يرفض طلبات غير مفوضة ولا يعطي offset أو ACK. 6 Flutter tests جديدة **نتيجتها بعد غير مؤكدة**.
- [x] `75eff160`: independent `.github/workflows/pro-fast-tests.yml` يفصل الاختبارات السريعة عن انتظار APK؛ CI Run `44954233385` قيد الفحص، ومنفصل عن build القديم.
- [ ] لم يُنشأ endpoint شبكي لاستعلام offset، ولا نقل chunks، ولا fsync Android power-loss real phone test، ولا نشر ملف نهائي ذري، ولا إكمال hotspot/band selection. Flags تبقى false.

### تدقيق نجاح فحوص الاستئناف المحلي (2026-11-22)
- ✅ **Run 44954233385 SUCCESS** (source `75eff160` contains code `da0b601f`): Dart analyze `No issues found!`، **50/50 Flutter tests PASS** (تشمل 6 اختبارات auth gate)، و**94 Rust PASS** (4 native lease/fsync + 82 core + 8 TLS).
- Latest Android diagnostic Run `44954233387` كان pending؛ المصدر `75eff160` يضم Android directory fsync والتصريح المحلي بالإزاحة. لا تدّعِ APK بهذه الميزات قبل نجاح run أو artifact.
