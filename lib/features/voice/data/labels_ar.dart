

import '../../../core/utils/arabic_text_utils.dart' as utils;

/// ترجمة أسماء فئات YOLO (80 فئة قياسية بموديل COCO) للعربي.
/// لإضافة فئة جديدة لاحقًا: أضف سطر واحد بهذا القاموس فقط.
const Map<String, String> labelsAr = {
  'person': 'شخص',
  'bicycle': 'دراجة هوائية',
  'car': 'سيارة',
  'motorcycle': 'دراجة نارية',
  'airplane': 'طائرة',
  'bus': 'حافلة',
  'train': 'قطار',
  'truck': 'شاحنة',
  'boat': 'قارب',
  'traffic light': 'إشارة مرور',
  'fire hydrant': 'صنبور إطفاء',
  'stop sign': 'إشارة توقف',
  'bench': 'مقعد',
  'bird': 'طائر',
  'cat': 'قطة',
  'dog': 'كلب',
  'horse': 'حصان',
  'sheep': 'خروف',
  'cow': 'بقرة',
  'backpack': 'حقيبة ظهر',
  'umbrella': 'مظلة',
  'handbag': 'حقيبة يد',
  'suitcase': 'حقيبة سفر',
  'bottle': 'زجاجة',
  'cup': 'كوب',
  'fork': 'شوكة',
  'knife': 'سكين',
  'spoon': 'ملعقة',
  'bowl': 'وعاء',
  'banana': 'موزة',
  'apple': 'تفاحة',
  'chair': 'كرسي',
  'couch': 'أريكة',
  'bed': 'سرير',
  'dining table': 'طاولة طعام',
  'tv': 'تلفاز',
  'laptop': 'حاسوب محمول',
  'mouse': 'فأرة الحاسوب',
  'remote': 'جهاز تحكم',
  'keyboard': 'لوحة مفاتيح',
  'cell phone': 'هاتف محمول',
  'book': 'كتاب',
  'clock': 'ساعة',
  'door': 'باب',
};

/// يرجّع الاسم العربي لو موجود بالقاموس، وإلا يرجّع الاسم الإنجليزي
/// كما هو (أفضل من رمي خطأ أو إخفاء الجسم بالكامل).
String toArabicLabel(String englishLabel) {
  return labelsAr[englishLabel] ?? englishLabel;
}

/// توحيد بسيط لأشكال الحروف العربية المختلفة (همزات، تاء مربوطة، ألف
/// مقصورة) ومسافات زائدة. يستخدمه هذا الملف (englishLabelForArabic)
/// وأيضًا voice_command_parser.dart لمطابقة نصوص STT، اللي غالبًا
/// ترجع بدون تشكيل وباختلافات إملائية بسيطة حسب دقة التعرّف.
String normalizeArabicText(String input) => utils.normalizeArabic(input);

/// يبحث عن الاسم الإنجليزي المطابق لكلمة أو جملة عربية (مثلًا نص خام
/// من STT). يقارن بعد التطبيع أولًا (تطابق كامل)، ثم يجرّب مطابقة
/// جزئية (احتواء) كخيار ثانٍ — يفيد لو النص كان جملة كاملة تحتوي اسم
/// الجسم ("الكرسي" بدل "كرسي"، بسبب أل التعريف). يرجّع null لو ما لقى
/// أي تطابق — الاستدعاء المسؤول (parseVoiceCommand) يتعامل مع هذي
/// الحالة كأمر غير مفهوم، مو خطأ.
String? englishLabelForArabic(String arabicText) {
  final normalized = normalizeArabicText(arabicText);
  if (normalized.isEmpty) return null;

  // 1) تطابق تام
  for (final entry in labelsAr.entries) {
    if (normalizeArabicText(entry.value) == normalized) {
      return entry.key;
    }
  }

  // 2) ✅ جديد: تطابق كلمة-كلمة (يحل "الحاسوب" ↔ "حاسوب محمول")
  final inputWords = normalized
      .split(' ')
      .where((w) => w.length > 1 && w != '.')  // تجاهل الحروف المفردة والفواصل
      .toList();

  for (final entry in labelsAr.entries) {
    final labelWords = normalizeArabicText(entry.value).split(' ');

    // إذا أي كلمة من الإدخال تطابق أي كلمة من الاسم
    if (labelWords.any((lw) => inputWords.contains(lw))) {
      return entry.key;
    }
  }

  return null;
}



