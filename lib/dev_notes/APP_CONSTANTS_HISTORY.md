# ملاحظات تطوير الثوابت العامة (AppConstants)

## السجل التاريخي

- **25 أغسطس 2026:** سجّل هذا التحديث الانتقال من YOLO11n إلى YOLOX-Tiny، ومن yolo26n-depth إلى MiDaS Small، وتحويل استدلال MiDaS إلى نمط عند الطلب.
- بقيت أسماء YOLO11n وyolo26n-depth في هذه الملاحظات كتاريخ للاستبدال فقط؛ ملفات التشغيل الحالية تشير إلى `assets/models/model.tflite` و`assets/models/midas_small.tflite`.
- كانت ذاكرة الأجسام معطّلة في مرحلة سابقة، ثم فُعّلت. وكانت `detectionHoldFrames` تساوي صفرًا في ملاحظات أقدم؛ القيمة الحالية اثنتان.

## الحالة الحالية في `constants.dart`

### التوجيه

- `navigationArrivalBoxHeightRatio = 0.45`: الوصول يُستنتج من ارتفاع صندوق الهدف نسبةً إلى ارتفاع الإطار.
- `navigationObstacleBoxAreaRatio = 0.22` و`navigationObstacleCenterTolerance = 0.25`: عتبتا مساحة الصندوق ومركزه لاكتشاف عائق في المسار.
- `navigationLostAnnounceCooldownSeconds = 3`: التنبيه الأول عند فقد الهدف فوري، ثم يحدّ هذا الفاصل تكراره. `navigationTargetLostFrames = 6` ما زال معرّفًا لكنه غير مستخدم في `NavigationController`.
- `navigationProgressAnnounceCooldownSeconds = 2` و`navigationObstacleCooldownSeconds = 2`.
- `gyroYawPositiveMeansTurnedLeft = true` و`gyroMinYawToGuessDirection = 0.15`. اتجاه الإشارة يحتاج اختبارًا فعليًا على الجهاز.

### الكشف والذاكرة

- `detectionModelPath = 'assets/models/model.tflite'`، وحجم التحويل `detectionInputSize = 416`، و`yoloxStrides = [8, 16, 32]`.
- `useNativeDetector = true`: الشاشة تختار `NativeDetectorService` على Android. `DetectorService` بديل Dart/TFLite عند تغيير العلم.
- `confidenceThreshold = 0.40` و`iouThreshold = 0.45`. فك YOLOX وNMS معرفان في `detector_service.dart` ويستعملهما المساران.
- `frameSkip = 2`: تتم معالجة إطار من كل إطارين. القيمة الحالية لا تثبت أنها مثالية لكل جهاز.
- `objectMemoryEnabled = true`، و`memoryMatchThreshold = 0.22`، و`objectLostAfterSeconds = 5`، و`objectArchivedAfterSeconds = 300`. التخزين في JSON محلي وتتم الكتابات اللاحقة عبر حفظ مؤجل.

### العمق والتتبع والعرض

- `depthModelPath = 'assets/models/midas_small.tflite'` و`depthInputSize = 256`. يُحمّل `DepthService` أثناء تهيئة الشاشة، لكن تشغيل الاستدلال يكون عند طلب قياس أو تحليل مساحة.
- `depthHigherValueMeansCloser = true` هو افتراض اتجاه خريطة العمق، ويحتاج تحققًا على النموذج والجهاز.
- `detectionHoldFrames = 2` يحتفظ بآخر صناديق لمدة إطارين معالجين عند اختفاء كشف مؤقت.
- `detectionSmoothing = 0.75` معرّف لكنه غير مستخدم حاليًا؛ تنعيم الهوية والمسافة في `smoothDetections` وتحريك الصناديق في `BoxAnimationController` مساران منفصلان.
- `boxAnimationSpeed = 18.0` يُستخدم في `BoxAnimationController`، و`minDetectionStreakForAnnounce = 2` يُستخدم فقط إذا فُعّل الإعلان الآلي.
- `showCameraPreviewForDebug = true`: تعرض الشاشة `CameraPreview` عندما تكون القيمة true. الأزرار اليدوية، بخلاف ذلك، محصورة في `kDebugMode` وتتطلب إظهار لوحة المطوّر.
- `handTrackingEnabled = false`: خدمة تتبع اليد والاختيار بالقبضة غير نشطين حاليًا.

### الصوت والخوادم

- `voiceCommandsEnabled = true` و`voiceEnabledByDefault = true`.
- `announceAllDetectionsAutomatically = false`: منطق `_detectionStreak` موجود، لكن الإعلان الآلي عن كل كشف متوقف افتراضيًا.
- `voiceCooldownSeconds = 4` يقيّد `VoiceAnnouncer.announceIfNeeded`، ولا يقيّد كل رسائل `speakNow`.
- `useSherpaTts = true`: `DetectionScreen` يحقن `SherpaTtsAdapter` حاليًا؛ `FlutterTtsAdapter` هو البديل.
- `voiceBurstScanDuration = 1500ms` للمسح الصوتي القصير. `aiBackendEnabled = true`، وتأتي عناوين الخوادم ومفتاحها من `AppSecrets` في `lib/core/secrets.dart` المستثنى من Git؛ لا تُكتب القيم الخاصة في هذا السجل.
- مسارات التدريب المعرّفة هي `/upload` و`/train` و`/download_model`، لكن شاشة التدريب الحالية تستخدم رفع الصور فقط.

## نقاط تحتاج تحققًا على جهاز

- اتجاه الجيروسكوب وقيم العمق النسبية ومعايرة الخطوات ليست نتائج يمكن إثباتها من الثوابت وحدها.
- أرقام أزمنة الاستدلال الواردة في سجلات/ملاحظات أخرى مرتبطة بالجهاز ووضع الطاقة، وليست ضمان أداء عامًا.
- مصدر النموذج وترخيص أوزانه موثقان في `THIRD_PARTY_LICENSES.md` و`NOTICE` وفق المعلومات المتاحة، لا في هذا الملف البرمجي.