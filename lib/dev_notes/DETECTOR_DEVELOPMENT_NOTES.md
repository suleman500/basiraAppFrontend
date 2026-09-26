# ملاحظات تطوير فك نتائج YOLOX ومحركات الكشف

## المسار المستخدم حاليًا

- `AppConstants.useNativeDetector = true`، لذا تختار `DetectionScreen` `NativeDetectorService` افتراضيًا.
- على Android يسجل `MainActivity` قناة `basira/native_detector`، ويحمّل `NativeDetector.kt` النموذج في `Interpreter` داخل `HandlerThread` باسم `basira-inference`. يضبط 4 threads ويحاول تفعيل XNNPACK. هذا يفصل استدلال النموذج عن خيط الواجهة؛ فك المخرجات وNMS يبقيان في Dart.
- `DetectorService` ما زال بديلًا صالحًا عند جعل العلم false: يستخدم `tflite_flutter` مع 4 threads و`XNNPackDelegate` عند نجاح إضافته، ويستدعي `Interpreter.run` مباشرةً من Dart، لا عبر `compute`.
- تحويل الكاميرا YUV إلى RGB هو الجزء الذي يستخدم `compute`/Isolate في المسارين؛ ليس استدلال النموذج.

## أشكال الإدخال والإخراج

- يحدد `detectionInputSize = 416` حجم الإطار المربع المستخدم حاليًا. كلا المسارين يحول بايتات RGB إلى Float32 بقيم خام `0..255` دون قسمة على 255.
- `DetectorService.load()` يقرأ شكل الإدخال والإخراج من Interpreter ويطبعهما، و`NativeDetector` يعيد الشكلين من Kotlin. الشكل `[1, 416, 416, 3]` للإدخال و`[1, 85, 3549]` للإخراج هما آخر قيم مسجلة في هذه الملاحظات، لكن الشيفرة الحالية لا تفرض هذه الأشكال كثوابت؛ تعاد قراءتها عند تحميل ملف النموذج.
- `[1, 85, 3549]` يطابق 5 حقول للصندوق + 80 فئة، و3549 = 52² + 26² + 13². يلزم إعادة فحص سجلات التحميل إذا استُبدل `assets/models/model.tflite`؛ لا يُستنتج الشكل من اسم الملف وحده.

## فك النتائج وNMS

- `decodeYoloxDetections` يتعامل مع قيم الصندوق `[cx, cy, w, h, objectness, class scores...]`، يطبق sigmoid عند الحاجة، ويحسب الثقة النهائية من objectness مضروبًا بأعلى class score.
- `manualGridDecodeRequired` مضبوط إلى true في `DetectorService`، وممرر true مباشرة في `NativeDetectorService`. يفك `decodeRawGrid` مواضع الشبكة باستخدام `yoloxStrides = [8, 16, 32]`.
- عتبة NMS للفئة نفسها هي `AppConstants.iouThreshold` (0.45 حاليًا). بعد ذلك يوجد ترشيح cross-label بعتبة IoU ثابتة 0.75.
- يفحص decoder أبعاد المحاور ديناميكيًا (`dimA` و`dimB`)، لكنه يفترض بنية YOLOX anchor-free وعدد حقول يبدأ بـ5. لا توجد هنا اختبارات fixture للمخرجات في مجلد `test` الحالي.

## الأبعاد، التحويل، والاحتفاظ بالنتائج

- `frame_converter.dart` يحول YUV إلى RGB مع sampling stride، ثم تدوير/تحجيم الإطار في Isolate. إطارات الكشف تستخدم `modelInputSize`، وهو alias لـ`detectionInputSize` (416).
- `detectionHoldFrames = 2` يحتفظ بصناديق الشاشة لإطارين معالجين عند غياب كشف مؤقت؛ القيمة ليست صفرًا كما ورد في ملاحظة أقدم.
- `detectionSmoothing = 0.75` معرّف في `AppConstants` لكنه غير مستخدم في ملفات Dart الحالية. تطابق الهوية/تنعيم المسافة موجود في `smoothDetections`، وتحريك الصناديق عبر `BoxAnimationController` يعتمد `boxAnimationSpeed`.

## الأداء والقياسات

- يسجل `DetectionScreen` زمن تحويل الإطار وزمن الكشف/فك النتائج والزمن الكلي. `DetectorService` يسجل مراحل التحويل الداخلي والاستدلال وdecode/NMS.
- قيم مثل `~800ms` أو `1200-2000ms` الواردة في سجلات سابقة ليست ضمانًا عامًا؛ هي قياسات تاريخية مرتبطة بجهاز وبناء ووضع طاقة محددين، ويجب إعادة قياسها لكل جهاز ومحرك.

## التصدير والتراخيص

- لا توجد في المشروع الحالي ملفات `export_onnx.py` أو وصف قابل للتشغيل لسلسلة PyTorch→ONNX→TFLite؛ خطوات التصدير القديمة غير قابلة للتحقق من هذا المستودع وتحتاج مصدرًا خارجيًا قبل إعادة استخدامها.
- راجع `THIRD_PARTY_LICENSES.md` و`NOTICE` لمعلومات المصدر والترخيص المتاحة. شيفرة decoder نفسها لا تثبت مصدر ملف الأوزان أو شروطه؛ لا يُستنتج السماح التجاري من هذه الملاحظات وحدها.