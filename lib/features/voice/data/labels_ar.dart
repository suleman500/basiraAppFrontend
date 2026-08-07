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
