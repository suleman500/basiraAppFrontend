/// ثوابت عامة للمشروع كامل.
class AppConstants {
  AppConstants._();

  // ---------------- ذاكرة الأجسام ----------------
  /// أقصى فرق مسموح بين بصمتين حتى نعتبرهما نفس الجسم.

  /// أقل ثقة مقبولة للكشف.
  static const double confidenceThreshold = 0.40;

  /// عتبة تداخل المربعات.
  static const double iouThreshold = 0.45;

  /// تحليل إطار واحد من كل إطارين.
  static const int frameSkip = 2;

  static const double memoryMatchThreshold = 0.16;

  // ---------------- الموديلات ----------------

  /// موديل كشف الأشياء والمربعات.
  static const String detectionModelPath = 'assets/models/model.tflite';

  /// اسم قديم للمحافظة على التوافق مع أي كود يستخدم modelPath.
  static const String modelPath = detectionModelPath;

  /// موديل خريطة العمق.
  static const String depthModelPath = 'assets/models/yolo26n-depth.tflite';

  /// أسماء الفئات.
  static const String labelsPath = 'assets/labels/labels.txt';

  /// حجم صورة الإدخال للموديلين.
  static const int modelInputSize = 320;

  // ---------------- الأداء ----------------

  // ---------------- تحسين التتبع والأداء ----------------

  /// تشغيل موديل العمق كل عدد معين من الإطارات.
  static const int depthFrameInterval = 10;

  /// إبقاء آخر نتيجة ظاهرة إذا فشل الكشف مؤقتًا.
  static const int detectionHoldFrames = 8;

  /// نسبة نعومة حركة المربع.
  static const double detectionSmoothing = 0.65;

  // ---------------- الصوت ----------------

  /// المدة بين تكرار نطق نفس الجسم.
  static const int voiceCooldownSeconds = 4;

  /// تشغيل الصوت افتراضيًا.
  static const bool voiceEnabledByDefault = true;

  // ==================== Backend Server ====================
  static const String serverBaseUrl = 'http://192.168.43.165:5000';
  static const String uploadEndpoint = '/upload';
  static const String trainEndpoint = '/train';
  static const String downloadModelEndpoint = '/download_model';
}
