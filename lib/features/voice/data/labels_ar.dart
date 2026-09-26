import '../../../core/utils/arabic_text_utils.dart' as utils;

/// ترجمة أسماء فئات YOLO للعربي.
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

/// يرجّع الاسم العربي إذا كان موجودًا بالقاموس،
/// وإلا يرجّع الاسم الإنجليزي كما هو.
String toArabicLabel(String englishLabel) {
  return labelsAr[englishLabel] ?? englishLabel;
}

/// توحيد النص العربي قبل المقارنة.
String normalizeArabicText(String input) {
  return utils.normalizeArabic(input);
}

/// تقسيم النص إلى كلمات بعد التطبيع.
List<String> _normalizedWords(String input) {
  return normalizeArabicText(input)
      .split(RegExp(r'\s+'))
      .map((word) => word.trim())
      .where(
        (word) =>
    word.isNotEmpty &&
        word != '.' &&
        word != '،' &&
        word != '؟' &&
        word != '!',
  )
      .toList();
}

/// إزالة "الـ" من بداية الكلمة.
///
/// أمثلة:
/// كرسي  -> كرسي
/// الكرسي -> كرسي
/// باب   -> باب
/// الباب -> باب
String _withoutDefiniteArticle(String word) {
  if (word.startsWith('ال') && word.length > 2) {
    return word.substring(2);
  }

  return word;
}

/// مقارنة كلمتين عربيتين مع أو بدون "الـ".
bool _sameArabicWord(String first, String second) {
  final firstNormalized = _withoutDefiniteArticle(
    normalizeArabicText(first),
  );

  final secondNormalized = _withoutDefiniteArticle(
    normalizeArabicText(second),
  );

  return firstNormalized == secondNormalized;
}

/// مقارنة اسمين عربيين كلمة بكلمة.
///
/// أمثلة:
/// كرسي == الكرسي
/// باب == الباب
/// طاولة طعام == الطاولة الطعام
bool _sameArabicLabel(String first, String second) {
  final firstWords = _normalizedWords(first);
  final secondWords = _normalizedWords(second);

  if (firstWords.length != secondWords.length) {
    return false;
  }

  for (var i = 0; i < firstWords.length; i++) {
    if (!_sameArabicWord(firstWords[i], secondWords[i])) {
      return false;
    }
  }

  return true;
}

/// يبحث عن الاسم الإنجليزي المطابق لنص عربي.
///
/// يدعم:
/// - كرسي
/// - الكرسي
/// - وين الكرسي
/// - باب
/// - الباب
/// - وين الباب
/// - طاولة الطعام
/// - الطاولة الطعام
/// - وين الطاولة
String? englishLabelForArabic(String arabicText) {
  final normalized = normalizeArabicText(arabicText).trim();

  if (normalized.isEmpty) {
    return null;
  }

  // 1) تطابق مباشر، مثل:
  // كرسي == كرسي
  for (final entry in labelsAr.entries) {
    if (normalizeArabicText(entry.value) == normalized) {
      return entry.key;
    }
  }

  final inputWords = _normalizedWords(normalized);

  if (inputWords.isEmpty) {
    return null;
  }

  // 2) تطابق اسم كامل مع أو بدون "الـ"، مثل:
  // الكرسي == كرسي
  // الطاولة الطعام == طاولة طعام
  for (final entry in labelsAr.entries) {
    if (_sameArabicLabel(normalized, entry.value)) {
      return entry.key;
    }
  }

  // 3) البحث عن اسم الجسم داخل الجملة، مثل:
  // وين الكرسي
  // فين الباب
  // بدي أروح للطاولة
  for (final inputWord in inputWords) {
    for (final entry in labelsAr.entries) {
      final labelWords = _normalizedWords(entry.value);

      final found = labelWords.any(
            (labelWord) => _sameArabicWord(inputWord, labelWord),
      );

      if (found) {
        return entry.key;
      }
    }
  }

  return null;
}