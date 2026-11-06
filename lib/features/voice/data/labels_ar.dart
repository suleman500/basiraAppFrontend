import '../../../core/utils/arabic_text_utils.dart' as utils;

/// ترجمة أسماء فئات YOLO للعربي (الأسماء "الرسمية" — هي اللي بيرجّعها
/// toArabicLabel وبتنطق للمستخدم).
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

/// ⚠️ مرادفات ولهجات وجموع — للفهم فقط (ما بتنطق للمستخدم أبدًا، النطق
/// دايمًا بالاسم الرسمي من labelsAr). أي كلمة بتسمعها من المستخدم وما
/// انفهمت، ضيفها هون تحت اسم الجسم الإنجليزي المناسب.
const Map<String, List<String>> _labelAliases = {
  'person': ['انسان', 'اشخاص', 'ناس', 'حدا'],
  'bicycle': ['بسكليت', 'سيكل', 'دراجات'],
  'car': ['سيارات', 'عربية', 'مركبة'],
  'motorcycle': ['موتور', 'موتورسيكل'],
  'bus': ['باص', 'حافلات'],
  'truck': ['تريلا', 'شاحنات'],
  'bench': ['دكة', 'بنش'],
  'cat': ['قط', 'بسة', 'قطط'],
  'dog': ['كلاب'],
  'backpack': ['شنطة ظهر', 'ظهرية'],
  'umbrella': ['شمسية', 'مظلات'],
  'bottle': ['قنينة', 'قارورة', 'زجاجات'],
  'cup': ['كاسة', 'كباية', 'كأس', 'فنجان', 'اكواب'],
  'spoon': ['معلقة'],
  'bowl': ['صحن', 'طبق', 'سلطانية', 'زبدية'],
  'banana': ['موز'],
  'apple': ['تفاح'],
  'chair': ['كراسي'],
  'couch': ['كنبة', 'كنب', 'كنباية', 'صوفا', 'سوفا'],
  'bed': ['تخت', 'اسرة', 'فراش'],
  'dining table': ['ترابيزة', 'طربيزة', 'سفرة', 'طاولات'],
  'tv': ['تلفزيون', 'تلفزون', 'تلفيزيون', 'تي في'],
  'laptop': ['لابتوب', 'لاب توب', 'كمبيوتر', 'كمبيوتر محمول'],
  'mouse': ['ماوس'],
  'remote': ['ريموت', 'ريموت كنترول', 'كنترول'],
  'keyboard': ['كيبورد'],
  'cell phone': ['موبايل', 'جوال', 'تلفون', 'خلوي', 'خليوي'],
  'book': ['كتب'],
  'door': ['ابواب'],
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

/// تقسيم النص إلى كلمات بعد التطبيع (مع إزالة علامات الترقيم حتى
/// "الكرسي؟" تصير "الكرسي").
List<String> _normalizedWords(String input) {
  final withoutPunctuation = input.replaceAll(
    RegExp(r'[.,،؟?!:;"“”«»()\-]'),
    ' ',
  );

  return normalizeArabicText(withoutPunctuation)
      .split(RegExp(r'\s+'))
      .map((word) => word.trim())
      .where((word) => word.isNotEmpty)
      .toList();
}

/// يشيل "ال" وكل السوابق الملتصقة فيها من بداية الكلمة.
///
/// أمثلة: الكرسي → كرسي | للكرسي → كرسي | بالباب → باب |
///        عالباب → باب | والكرسي → كرسي
///
/// ⚠️ بنشيل بس لو بقي 3 أحرف على الأقل، حتى ما تنهدم كلمات قصيرة.
String _cleanWord(String word) {
  const prefixes = ['وبال', 'ولل', 'وال', 'بال', 'كال', 'فال', 'عال', 'لل', 'ال'];

  for (final prefix in prefixes) {
    if (word.startsWith(prefix) && word.length - prefix.length >= 3) {
      return word.substring(prefix.length);
    }
  }
  return word;
}

/// المسافة التحريرية (Levenshtein) بين كلمتين.
int _editDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  var previous = List<int>.generate(b.length + 1, (i) => i);

  for (var i = 0; i < a.length; i++) {
    final current = List<int>.filled(b.length + 1, 0);
    current[0] = i + 1;

    for (var j = 0; j < b.length; j++) {
      final deletion = previous[j + 1] + 1;
      final insertion = current[j] + 1;
      final substitution = previous[j] + (a[i] == b[j] ? 0 : 1);

      var best = deletion;
      if (insertion < best) best = insertion;
      if (substitution < best) best = substitution;
      current[j + 1] = best;
    }
    previous = current;
  }
  return previous[b.length];
}

/// اسم (رسمي أو مرادف) جاهز للمقارنة: كلماته منظّفة مسبقًا.
class _LabelEntry {
  final String english;
  final List<String> words;
  final bool isOfficial;

  const _LabelEntry(this.english, this.words, this.isOfficial);
}

List<_LabelEntry> _buildEntries() {
  final entries = <_LabelEntry>[];

  // الأسماء الرسمية أول (لها أولوية عند التعادل).
  labelsAr.forEach((english, arabic) {
    entries.add(
      _LabelEntry(english, _normalizedWords(arabic).map(_cleanWord).toList(), true),
    );
  });

  _labelAliases.forEach((english, aliases) {
    for (final alias in aliases) {
      entries.add(
        _LabelEntry(english, _normalizedWords(alias).map(_cleanWord).toList(), false),
      );
    }
  });

  return entries;
}

// Dart بيبني المتغيّر العام أول مرة بنستخدمه (lazy)، مرة وحدة بس.
final List<_LabelEntry> _entries = _buildEntries();

/// هل [input] فيها العبارة [phrase] كلماتها ورا بعض بنفس الترتيب؟
bool _containsPhrase(List<String> input, List<String> phrase) {
  if (phrase.isEmpty || phrase.length > input.length) return false;

  for (var start = 0; start + phrase.length <= input.length; start++) {
    var matches = true;
    for (var i = 0; i < phrase.length; i++) {
      if (input[start + i] != phrase[i]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}

/// يبحث عن الاسم الإنجليزي المطابق لنص عربي.
///
/// بيمرّ على 3 مراحل (الأدق أول):
/// 1) الاسم (الرسمي أو المرادف) موجود بالجملة كعبارة كاملة — الأطول أولًا
///    ("دراجة نارية" قبل "دراجة"). بيدعم: وين الكرسي، للكرسي، الكراسي،
///    الكنباية، لاب توب...
/// 2) كلمة وحدة من الجملة = كلمة من اسم رسمي (زي "طاولة" ← طاولة طعام).
/// 3) تسامح بحرف واحد (أخطاء STT زي "الكرس" ← كرسي): بشروط صارمة —
///    الكلمة المنطوقة 3 أحرف+، كلمة الاسم 4 أحرف+، نفس الحرف الأول.
String? englishLabelForArabic(String arabicText) {
  final inputWords = _normalizedWords(arabicText).map(_cleanWord).toList();

  if (inputWords.isEmpty) return null;

  // 1) عبارة كاملة
  _LabelEntry? best;
  for (final entry in _entries) {
    if (!_containsPhrase(inputWords, entry.words)) continue;
    if (best == null || entry.words.length > best.words.length) {
      best = entry;
    }
  }
  if (best != null) return best.english;

  // 2) كلمة وحدة من اسم رسمي
  for (final inputWord in inputWords) {
    for (final entry in _entries) {
      if (entry.isOfficial && entry.words.contains(inputWord)) {
        return entry.english;
      }
    }
  }

  // 3) تسامح بحرف واحد
  String? fuzzyMatch;
  var bestDistance = 2;

  for (final inputWord in inputWords) {
    if (inputWord.length < 3) continue;

    for (final entry in _entries) {
      for (final labelWord in entry.words) {
        if (labelWord.length < 4) continue;
        if (inputWord[0] != labelWord[0]) continue;
        if ((inputWord.length - labelWord.length).abs() > 1) continue;

        final distance = _editDistance(inputWord, labelWord);
        if (distance < bestDistance) {
          bestDistance = distance;
          fuzzyMatch = entry.english;
        }
      }
    }
  }

  return fuzzyMatch;
}