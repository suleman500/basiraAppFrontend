# ملاحظات تطوير الثوابت العامة (AppConstants)

## التاريخ
- تحديث 25 أغسطس 2026

## التغييرات الرئيسية
- نموذج الكشف: YOLOX-Tiny (Apache 2.0) بدلاً من YOLO11n.
- نموذج العمق: MiDaS Small (MIT) بدلاً من yolo26n-depth.
- موديل العمق يعمل عند الطلب فقط (On-Demand).

## (Navigation Mode) – وضع التوجيه
- يعتمد على حجم صندوق الهدف كدليل تقارب، بدون حاجة لـ MiDaS.
- `navigationArrivalBoxHeightRatio = 0.45`: عندما يصل ارتفاع الصندوق إلى 45% من ارتفاع الشاشة، ينطق "وصلت".
- `navigationTargetLostFrames = 6`: لم يعد مستخدماً. الإعلان أصبح فورياً عند فقدان الهدف.
- `gyroYawPositiveMeansTurnedLeft = true`: يحتاج تأكيد فعلي على الجهاز. إذا كانت التوجيهات معكوسة، اقلب القيمة.

## (Object Memory) – ذاكرة الأجسام
- `confidenceThreshold = 0.40`: أقل ثقة للكشف.
- `iouThreshold = 0.45`: عتبة NMS. YOLOX لا يطبق NMS داخلياً، لذا يُطبق يدوياً في `detector_service.dart`.
- `frameSkip = 2`: تم تجربة 1 لكنها تسبب حملًا زائداً. 2 هي القيمة المثالية.
- `memoryMatchThreshold = 0.22`: رُفعت من 0.16 لتقليل الحساسية لتغيرات الإضاءة.
- `objectMemoryEnabled = false`: معطلة لتحسين الأداء. يمكن تفعيلها مستقبلاً.

## (Detection Models: YOLOX-Tiny)
- `detectionModelPath = 'assets/models/model.tflite'`: ضع ملف النموذج هنا.
- `detectionInputSize = 416`: حجم الإدخال القياسي لـ YOLOX-Tiny.
- `yoloxStrides = [8, 16, 32]`: مستويات فك تشفير الشبكة.

## (Depth Models: MiDaS Small)
- `depthModelPath = 'assets/models/midas_small.tflite'`: ضع ملف النموذج هنا.
- `depthInputSize = 256`: حجم الإدخال لـ MiDaS Small.

## (Tracking & Performance)
- `detectionHoldFrames = 0`: المربع يختفي فوراً عند فقدان الكشف.
- `detectionSmoothing = 0.75`: رُفعت من 0.65 لتقليل التأخر.
- `boxAnimationSpeed = 18.0`: سرعة تقارب المربع نحو الهدف.
- `minDetectionStreakForAnnounce = 2`: يمنع النطق للكشوفات اللحظية الوهمية.
- `showCameraPreviewForDebug = true`: فعّل للاختبار، وعطّل للإصدار النهائي.

## (Voice)
- `voiceCooldownSeconds = 4`: فترة بين تكرار نطق الجسم نفسه.
- `voiceEnabledByDefault = true`: تفعيل الصوت افتراضياً.

## (Backend Server)
- `serverBaseUrl = 'http://192.168.43.165:5000'`: عنوان الخادم لتجميع بيانات التدريب.
- يستخدم مع Roboflow لجمع بيانات التدريب وتدريب النماذج المخصصة.

## ملاحظة حول أداء البطارية ⚠️
- وضع توفير الطاقة أو انخفاض الشحن يؤدي إلى خفض تردد المعالج، مما يزيد زمن الاستدلال بشكل كبير.
- تأكد من أن الجهاز في وضع الأداء العالي أثناء الاختبار.
- مع البطارية الضعيفة، قد يرتفع زمن الاستدلال إلى 1200-2000ms أو أكثر.