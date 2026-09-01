/// ثوابت عامة للمشروع.
///
/// للتفاصيل الكاملة والتاريخ، راجع APP_CONSTANTS_NOTES.md.
class AppConstants {
  AppConstants._();

  // (Navigation Mode)

  /// نسبة ارتفاع صندوق الهدف إلى ارتفاع الشاشة للوصول.
  static const double navigationArrivalBoxHeightRatio = 0.45;

  /// نسبة مساحة العائق للشاشة لاعتباره عائقاً أمامياً.
  static const double navigationObstacleBoxAreaRatio = 0.22;

  /// أقصى انحراف أفقي للعائق عن مركز الصورة.
  static const double navigationObstacleCenterTolerance = 0.25;

  /// لم يعد مستخدماً – الإعلان أصبح فورياً.
  static const int navigationTargetLostFrames = 6;

  /// فترة التهدئة بين تكرار "فقدت الهدف".
  static const int navigationLostAnnounceCooldownSeconds = 3;

  /// فترة التهدئة بين تكرار "استمر".
  static const int navigationProgressAnnounceCooldownSeconds = 2;

  /// فترة التهدئة بين تحذيرات العوائق.
  static const int navigationObstacleCooldownSeconds = 2;

  /// اتجاه الجيروسكوب (true = القيمة الموجبة تعني يسار).
  static const bool gyroYawPositiveMeansTurnedLeft = true;

  /// أقل زاوية دوران لتجاهل ضجيج الجيروسكوب.
  static const double gyroMinYawToGuessDirection = 0.15;

  // (Object Memory)

  /// أقل ثقة مقبولة للكشف.
  static const double confidenceThreshold = 0.40;

  /// عتبة NMS لـ YOLOX (يُطبق يدوياً).
  static const double iouThreshold = 0.45;

  /// عدد الإطارات المُتخطاة بين كل إطار معالج.
  static const int frameSkip = 2;

  /// عتبة تطابق البصمة اللونية.
  static const double memoryMatchThreshold = 0.22;

  /// تعطيل ذاكرة الأجسام (تحسين الأداء).
  static const bool objectMemoryEnabled = false;

  // (Detection Models: YOLOX-Tiny)

  /// مسار موديل الكشف.
  static const String detectionModelPath = 'assets/models/model.tflite';

  /// اسم قديم للتوافق.
  static const String modelPath = detectionModelPath;

  /// حجم إدخال موديل الكشف.
  static const int detectionInputSize = 416;

  /// خطوات الشبكة لـ YOLOX.
  static const List<int> yoloxStrides = [8, 16, 32];

  /// اتجاه خريطة العمق (true = أعلى قيمة = أقرب).
  static const bool depthHigherValueMeansCloser = true;

  // (Depth Models: MiDaS Small)

  /// مسار موديل العمق.
  static const String depthModelPath = 'assets/models/midas_small.tflite';

  /// حجم إدخال موديل العمق.
  static const int depthInputSize = 256;

  /// مسار التصنيفات.
  static const String labelsPath = 'assets/labels/labels.txt';

  /// حجم الإدخال العام (للتوافق مع الكود القديم).
  static const int modelInputSize = detectionInputSize;

  // (Tracking & Performance)

  /// عدد الإطارات للاحتفاظ بالكشف بعد فقدانه.
  static const int detectionHoldFrames = 0;

  /// نسبة نعومة حركة المربع.
  static const double detectionSmoothing = 0.75;

  /// سرعة تقارب المربع (حركة سلسة).
  static const double boxAnimationSpeed = 18.0;

  /// عدد الإطارات المتتالية قبل النطق الصوتي.
  static const int minDetectionStreakForAnnounce = 2;

  /// عرض معاينة الكاميرا (للتطوير فقط).
  static const bool showCameraPreviewForDebug = true;

  // (Voice)

  /// فترة التهدئة بين تكرار نطق نفس الجسم.
  static const int voiceCooldownSeconds = 4;

  /// تفعيل الصوت افتراضياً.
  static const bool voiceEnabledByDefault = true;

  // (Backend Server)

  static const String serverBaseUrl = 'http://192.168.43.165:5000';
  static const String uploadEndpoint = '/upload';
  static const String trainEndpoint = '/train';
  static const String downloadModelEndpoint = '/download_model';
}