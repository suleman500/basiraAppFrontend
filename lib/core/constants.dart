/// ثوابت عامة للمشروع كامل — أي رقم أو مسار يُحتمل نغيّره لاحقًا
/// يُكتب هون بس، وباقي الكود يستورده بدل ما يكرره بكل مكان.
class AppConstants {
  AppConstants._();

  // ---------------- الموديل ----------------

  /// مسار ملف الموديل داخل assets (بعد التصدير لصيغة tflite)
  static const String modelPath = 'assets/models/yolo26n-depth.tflite';

  /// مسار ملف أسماء الفئات (كل سطر = اسم فئة بترتيب مطابق لمخلم رجات الموديل)
  static const String labelsPath = 'assets/labels/labels.txt';

  /// حجم الإدخال المتوقع للموديل (عرض × ارتفاع بالبكسل). القيمة الشائعة
  /// لموديلات YOLO المصدَّرة هي 320 أو 640 — تأكد من مطابقتها لموديلك.
  static const int modelInputSize = 320;

  /// أقل نسبة ثقة نقبل بها كنتيجة كشف صحيحة (0.0 - 1.0)
  static const double confidenceThreshold = 0.5;

  /// عتبة تداخل المربعات المستخدمة بخوارزمية NMS لإزالة المربعات المكرّرة
  static const double iouThreshold = 0.45;

  // ---------------- الأداء ----------------

  /// إرسال إطار واحد من كل عدة إطارات للتحليل، لتخفيف الحمل على المعالج
  static const int frameSkip = 2;

  // ---------------- الصوت ----------------

  /// أقل مدة (بالثواني) قبل ما نسمح بإعادة نطق نفس الجسم من جديد،
  /// حتى لو اختفى وظهر بسرعة (يمنع التكرار المزعج)
  static const int voiceCooldownSeconds = 4;

  /// هل الصوت مفعّل افتراضيًا عند فتح التطبيق
  static const bool voiceEnabledByDefault = true;
}
