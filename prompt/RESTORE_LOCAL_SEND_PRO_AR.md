# رسالة استرجاع الجلسة — LocalSend Pro (انسخ كامل هذه الرسالة للمحادثة الجديدة)

الهوية: مطور مشروع **LocalSend Pro Android**. المستودع: https://github.com/alwansan/localsend-pro. فرع الكتابة الوحيد **feature/android-pro-fast-transfer**، لا تعدّل main ولا upstream.

أول مهمة: افتح HEAD وGitHub Actions والملفات الحية من الفرع:
- https://github.com/alwansan/localsend-pro/blob/feature/android-pro-fast-transfer/memory/pro/STATE.json
- https://github.com/alwansan/localsend-pro/blob/feature/android-pro-fast-transfer/memory/pro/MEMORY_AR.md
- https://github.com/alwansan/localsend-pro/blob/feature/android-pro-fast-transfer/docs/pro/PLAN_AR.md
- https://github.com/alwansan/localsend-pro/blob/feature/android-pro-fast-transfer/docs/pro/ARCHITECTURE_AR.md
ثم واصل العمل الفعلي واحفظ التقدم في هذه الملفات في كل جلسة؛ قد تكون نسخة الرسالة المنسوخة أقدم من حالة GitHub.

الهدف: 3 تفضيلات تُفعَّل افتراضياً وتُحفظ: (1) النقل السريع (Rust streaming، مستوحى من miniserve)، (2) تفضيل Hotspot/direct إذا متاح، (3) 5GHz auto إذا AP+طرفان متوافقون وإلا fallback 2.4GHz أو LAN. الاتصال تلقائي قدر الإمكان، مع إظهار موافقات Android الضرورية. لازم تحقيق أداء حقيقي + safe resume + adaptive recovery عند تدهور السرعة دون ضياع bytes أو إعادة الملف من الصفر. تحفظ TLS/التوافق مع LocalSend الأصلي.

خط الأساس 2026-11-21: أنشئ الفرع من main@26cc8f997aa3f7ad789c12500a8b7206cfbb3ddc. التطبيق Flutter 3.41.9 + Rust؛ HTTP/1.1 وTCP_NODELAY موجودان بالفعل؛ createChecksums افتراضه false؛ miniserve ليس بروتوكول نقل بل خادم HTTP. لا تكرر تغييرات محسومة. التصميم في docs/pro/PLAN_AR.md.

الأولويات: اقرأ بنية الشيفرة والاختبارات، implement capability detection/probe والطريقة السليمة لتفاوض القدرات ثم النقل المجزأ والـ offset والتعافي دون فساد؛ قوائم إرسال وإعدادات ومراقبة الأداء ثم GitHub Actions ARM64. لا تسلّم APK كنهائي إلى أن تكتمل المتطلبات ويجتاز اختبار جهازين. واصل العمل عندما أقول Continue.

آخر حالة هذه الرسالة عند تأسيسها: P0، الفرع منشأ، وثائق الخطة والذاكرة جارٍ إنشاؤها، لم يتم بناء APK نهائي أو اختبار هاتفين. المرجع الأحدث دائماً STATE.json، وليس هذه الفقرة. حدّثها بعد كل إنجاز.
