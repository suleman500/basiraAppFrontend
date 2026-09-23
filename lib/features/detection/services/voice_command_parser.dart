import '../../voice/data/labels_ar.dart';

/// أنواع الأوامر الصوتية المدعومة — قائمة ثابتة محدودة النطاق، وليست
/// فهمًا للغة الطبيعية بشكل عام. نفس فلسفة "ابدأ بسيط" اللي نجحت
/// معنا بباقي مراحل المشروع.
///
/// هذا الملف خالص منطق تصنيف نص → أمر، بدون أي أثر جانبي (لا يستدعي
/// الذاكرة، ولا الصوت، ولا أي خدمة، ولا الكاميرا). التنفيذ الفعلي
/// مسؤولية الشاشة (detection_screen.dart).
sealed class VoiceCommand {
  const VoiceCommand();
}

/// "وين الكرسي؟" / "فين الكوب؟" / "قديش بعيد الباب؟" — البحث عن جسم
/// محدد بذاكرة الأجسام (الجواب أصلًا فيه الاتجاه + المسافة، فسؤال
/// "قديش بعيد" بيتعامل معه بنفس المسار).
class FindObjectCommand extends VoiceCommand {
  final String arabicLabel;
  final String englishLabel;

  const FindObjectCommand({
    required this.arabicLabel,
    required this.englishLabel,
  });
}

/// "شو قدامي؟" / "شو حولي؟" — كل الأجسام النشطة حاليًا بالذاكرة.
class WhatsAroundCommand extends VoiceCommand {
  const WhatsAroundCommand();
}

/// "وقف التوجيه" / "الغاء" — إلغاء وضع التوجيه الحالي لو شغّال.
class StopNavigationCommand extends VoiceCommand {
  const StopNavigationCommand();
}

/// "بدي أروح للكرسي" / "خدني عند الباب" — بدء وضع التوجيه نحو جسم.
class NavigateToObjectCommand extends VoiceCommand {
  final String arabicLabel;
  final String englishLabel;

  const NavigateToObjectCommand({
    required this.arabicLabel,
    required this.englishLabel,
  });
}

/// "في عائق قدامي؟" / "بقدر أمشي؟" / "الطريق آمن؟" — تحليل المساحة
/// الفاضية بالممر، مختلف عن WhatsAroundCommand (بيرجع تقييم "قدرة
/// مشي" مو قائمة أجسام).
class FreeSpaceQueryCommand extends VoiceCommand {
  const FreeSpaceQueryCommand();
}

/// ما قدرنا نصنّف الجملة ضمن قائمتنا الثابتة، أو ما لقينا اسم جسم
/// معروف بالنص. يحمل النص الخام حتى يقدر المستدعي يسجّله أو يعرضه.
class UnknownCommand extends VoiceCommand {
  final String rawText;
  const UnknownCommand(this.rawText);
}

/// كل أمر = قائمة "مجموعات" (groups)، وكل مجموعة لازم كلمة وحدة
/// منها (على الأقل) تكون موجودة بالجملة حتى تعتبر مطابقة.
const List<List<String>> _stopNavigationGroups = [
  ['وقف', 'الغاء', 'بطل', 'خلص'],
];

const List<List<String>> _whatsAroundGroups = [
  ['شو', 'ايش', 'وش', 'ايه', 'ماذا'], // كلمة استفهام
  ['قدام', 'امام', 'حول', 'جنب', 'قرب'], // كلمة اتجاه/محيط
];

/// تشمل "قديش" لتغطية "قديش بعيد الكرسي؟" — نفس مسار FindObjectCommand
/// بالضبط لأن جوابه أصلًا فيه المسافة، فما في داعي لأمر منفصل.
const List<String> _findObjectTriggers = ['وين', 'فين', 'اين', 'قديش'];

/// أفعال/عبارات تدل على نية "روح لهناك" — أي وحدة منها + اسم جسم
/// معروف بعدها = NavigateToObjectCommand.
const List<String> _navigateTriggers = [
  'اروح',
  'رايح',
  'خدني',
  'وديني',
  'وجهني',
  'دلني',
  'وصلني',
];

/// كلمات تدل على استفسار "فيه مجال أمشي؟" — مختلفة عن WhatsAround
/// (مسح أجسام) لأنها بتسأل عن "قابلية المشي" تحديدًا.
const List<String> _freeSpaceTriggers = [
  'عائق',
  'امشي',
  'اسير',
  'مساحة',
];

/// أقصى فرق حروف مسموح بيه لاعتبار كلمتين "نفس الكلمة" (يمتص أخطاء
/// STT البسيطة بحرف وحدة). كلمة بطول 3 أحرف أو أقل ما بتستفيد من
/// التسامح (خطر تصادم أعلى من الفايدة).
const int _maxFuzzyDistance = 1;

/// يحوّل نص STT خام (بالعربي) إلى أمر مفهوم. الترتيب مقصود من الأضيق
/// نطاقًا للأوسع: إلغاء التوجيه (عبارات مميزة جدًا، تصادم شبه معدوم)،
/// ثم شو قدامي/حولي، ثم فيه عائق/بقدر أمشي، ثم التوجّه لجسم، وأخيرًا
/// وين + اسم جسم (الأوسع نطاقًا، محتاج استخراج اسم جسم فعليًا من
/// labels_ar حتى ما يتفاعل غلط مع أي جملة تحتوي "وين" بالصدفة).
VoiceCommand parseVoiceCommand(String rawText) {
  final normalized = normalizeArabicText(rawText);
  final words = normalized.split(' ').where((w) => w.isNotEmpty).toList();

  if (_matchesAllGroups(words, _stopNavigationGroups)) {
    return const StopNavigationCommand();
  }

  if (_matchesAllGroups(words, _whatsAroundGroups)) {
    return const WhatsAroundCommand();
  }

  final hasFreeSpaceTrigger = _freeSpaceTriggers.any(
        (trigger) => _wordsContainFuzzy(words, trigger),
  );

  if (hasFreeSpaceTrigger) {
    return const FreeSpaceQueryCommand();
  }

  final hasNavigateTrigger = _navigateTriggers.any(
        (trigger) => _wordsContainFuzzy(words, trigger),
  );

  if (hasNavigateTrigger) {
    final englishLabel = _extractKnownObjectLabel(words);
    if (englishLabel != null) {
      return NavigateToObjectCommand(
        arabicLabel: toArabicLabel(englishLabel),
        englishLabel: englishLabel,
      );
    }
  }

  final hasFindTrigger = _findObjectTriggers.any(
        (trigger) => _wordsContainFuzzy(words, trigger),
  );

  if (hasFindTrigger) {
    final englishLabel = _extractKnownObjectLabel(words);
    if (englishLabel != null) {
      return FindObjectCommand(
        arabicLabel: toArabicLabel(englishLabel),
        englishLabel: englishLabel,
      );
    }
  }

  // حتى بدون كلمة "وين" صراحة — لو الجملة كلها اسم جسم معروف بس
  // (المستخدم قال "الكرسي" مباشرة)، نتعامل معها كطلب بحث ضمنيًا.
  final englishLabel = _extractKnownObjectLabel(words);
  if (englishLabel != null) {
    return FindObjectCommand(
      arabicLabel: toArabicLabel(englishLabel),
      englishLabel: englishLabel,
    );
  }

  return UnknownCommand(rawText);
}

/// يتحقق إنه كل "مجموعة" بقائمة المجموعات عندها كلمة وحدة ع الأقل
/// موجودة (بمطابقة تسامحية) بكلمات الجملة.
bool _matchesAllGroups(List<String> words, List<List<String>> groups) {
  if (groups.isEmpty) return false;

  for (final group in groups) {
    final groupMatched = group.any(
          (keyword) => _wordsContainFuzzy(words, keyword),
    );
    if (!groupMatched) return false;
  }

  return true;
}

/// يفحص لو أي كلمة بالجملة قريبة كفاية (fuzzy) من كلمة مفتاحية معيّنة.
bool _wordsContainFuzzy(List<String> words, String keyword) {
  final normalizedKeyword = normalizeArabicText(keyword);

  for (final word in words) {
    if (word.contains(normalizedKeyword) ||
        normalizedKeyword.contains(word)) {
      return true;
    }

    if (normalizedKeyword.length > 3 &&
        _levenshteinDistance(word, normalizedKeyword) <= _maxFuzzyDistance) {
      return true;
    }
  }

  return false;
}

/// المسافة التحريرية (Levenshtein) بين كلمتين — تطبيق قياسي
/// (dynamic programming) بدون أي حزمة خارجية.
int _levenshteinDistance(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  var previousRow = List<int>.generate(b.length + 1, (i) => i);

  for (var i = 0; i < a.length; i++) {
    final currentRow = List<int>.filled(b.length + 1, 0);
    currentRow[0] = i + 1;

    for (var j = 0; j < b.length; j++) {
      final deletionCost = previousRow[j + 1] + 1;
      final insertionCost = currentRow[j] + 1;
      final substitutionCost = previousRow[j] + (a[i] == b[j] ? 0 : 1);

      currentRow[j + 1] = [
        deletionCost,
        insertionCost,
        substitutionCost,
      ].reduce((v, e) => v < e ? v : e);
    }

    previousRow = currentRow;
  }

  return previousRow[b.length];
}

/// يفحص كل كلمة بالجملة لحالها أولًا (أدق)، ثم الجملة كاملة كخيار
/// أخير (يفيد لو اسم الجسم بالعربي أكثر من كلمة، مثل "طاولة طعام").
String? _extractKnownObjectLabel(List<String> words) {
  for (final word in words) {
    final match = englishLabelForArabic(word);
    if (match != null) return match;
  }
  return englishLabelForArabic(words.join(' '));
}