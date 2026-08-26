/// ثوابت عامة للمشروع كامل.
///
/// محدَّث وفق "الخطة الجديدة المتفق عليها" (25 أغسطس 2026):
/// - نموذج الكشف: YOLOX-Tiny (Apache 2.0) بدل YOLO11n.
/// - نموذج العمق: MiDaS Small (MIT) بدل yolo26n-depth، ويعمل الآن
///   عند الطلب فقط (On-Demand) وليس تلقائيًا كل عدة إطارات.
class AppConstants {
  AppConstants._();

  // ---------------- ذاكرة الأجسام ----------------

  /// أقل ثقة مقبولة للكشف.
  static const double confidenceThreshold = 0.40;

  /// عتبة تداخل المربعات لِـ NMS (Non-Max Suppression).
  ///
  /// مهم مع YOLOX-Tiny تحديدًا: خلافًا لموديلات YOLO الأحدث (YOLO26/
  /// YOLO11 بصيغتها المصدَّرة)، YOLOX لا يطبّق NMS داخل الموديل نفسه،
  /// لذلك detector_service.dart يطبّق NMS يدويًا بهذي العتبة على كل
  /// مخرجات الموديل قبل عرضها.
  static const double iouThreshold = 0.45;

  /// تحليل إطار واحد من كل إطارين.
  static const int frameSkip = 2;

  static const double memoryMatchThreshold = 0.16;

  // ---------------- الموديلات: الكشف (YOLOX-Tiny) ----------------

  /// موديل كشف الأشياء والمربعات.
  ///
  /// ضع ملف YOLOX-Tiny المصدَّر بصيغة .tflite هنا بنفس الاسم، أو غيّر
  /// المسار إذا استخدمت اسمًا مختلفًا. لا حاجة لتعديل أي كود آخر غير
  /// هذا السطر عند إضافة الملف.
  static const String detectionModelPath = 'assets/models/model.tflite';

  /// اسم قديم للمحافظة على التوافق مع أي كود يستخدم modelPath.
  static const String modelPath = detectionModelPath;

  /// حجم صورة الإدخال لموديل الكشف (YOLOX-Tiny يُصدَّر عادة بحجم
  /// 416×416). عدّل هذا الرقم إذا صدّرت الموديل بحجم مختلف — باقي
  /// الكود (detector_service, frame_converter) يقرأ من هنا فقط.
  static const int detectionInputSize = 416;

  /// عتبات الشبكة (strides) المستخدمة بمعمارية YOLOX anchor-free.
  /// تُستخدم فقط لو صدَّرت الموديل بدون "decode" داخلي (راجع تعليق
  /// decoderIncludedInModel أسفل detector_service.dart).
  static const List<int> yoloxStrides = [8, 16, 32];

  // ---------------- الموديلات: العمق (MiDaS Small) ----------------

  /// موديل خريطة العمق. يعمل الآن فقط عند طلب صريح من المستخدم، وليس
  /// تلقائيًا كل عدة إطارات (راجع depth_service.dart و detection_screen.dart).
  static const String depthModelPath = 'assets/models/midas_small.tflite';

  /// حجم صورة الإدخال لموديل العمق (MiDaS Small يُصدَّر عادة بحجم
  /// 256×256). عدّل هذا الرقم فقط عند تغيير الموديل المصدَّر.
  static const int depthInputSize = 256;

  /// أسماء الفئات.
  static const String labelsPath = 'assets/labels/labels.txt';

  /// حجم صورة الإدخال العام — أُبقي عليه للتوافق مع أي كود قديم يستخدمه
  /// (frame_converter مثلًا)، لكن الأفضل الاعتماد على
  /// detectionInputSize/depthInputSize كل بموضعه.
  static const int modelInputSize = detectionInputSize;

  // ---------------- تحسين التتبع والأداء ----------------

  /// تشغيل موديل العمق كل عدة إطارات (لسا مستخدَم من detection_screen.dart
  /// الحالي؛ سيُحذف لاحقًا عند تحويل موديل العمق لآلية "عند الطلب" حسب
  /// الخطة الجديدة — راجع المرحلة 2 بملف baseera_new_plan).
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
  // يبقى صالحًا لتجميع بيانات التدريب (Roboflow) — التدريب الفعلي فقط
  // ينتقل من مكتبة ultralytics إلى سكربتات YOLOX (راجع الخطة، المرحلة 4).
  static const String serverBaseUrl = 'http://192.168.43.165:5000';
  static const String uploadEndpoint = '/upload';
  static const String trainEndpoint = '/train';
  static const String downloadModelEndpoint = '/download_model';
}