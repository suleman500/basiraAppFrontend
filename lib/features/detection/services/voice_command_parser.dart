import '../../voice/data/labels_ar.dart';

/// أنواع الأوامر الصوتية المدعومة بالمرحلة الأولى (MVP) — قائمة ثابتة
/// محدودة النطاق، وليست فهمًا للغة الطبيعية بشكل عام. نفس فلسفة "ابدأ
/// بسيط" اللي نجحت معنا بباقي مراحل المشروع (الذاكرة، التوجيه...).
///
/// هذا الملف خالص منطق تصنيف نص → أمر، بدون أي أثر جانبي (لا يستدعي
/// الذاكرة، ولا الصوت، ولا أي خدمة). التنفيذ الفعلي مسؤولية الشاشة
/// (detection_screen.dart)، بالضبط زي أي تفاعل مستخدم تاني (لمس،
/// زر) — نفس مبدأ فصل VoiceAnnouncer (قرار) عن TtsAdapter (تنفيذ).
sealed class VoiceCommand {
  const VoiceCommand();
}

/// "وين الكرسي؟" / "فين الكوب؟" — البحث عن جسم محدد بذاكرة الأجسام.
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

/// ما قدرنا نصنّف الجملة ضمن قائمتنا الثابتة، أو ما لقينا اسم جسم
/// معروف بالنص. يحمل النص الخام حتى يقدر المستدعي يسجّله أو يعرضه.
class UnknownCommand extends VoiceCommand {
  final String rawText;
  const UnknownCommand(this.rawText);
}

/// عبارات مفتاحية ثابتة لكل نوع أمر (MVP: قائمة يدوية، مو معالجة لغة
/// طبيعية). كل عبارة تُطابَق كـ"احتواء" (contains) بالنص بعد التطبيع
/// — أخف على المستخدم من حفظ صيغة واحدة حرفية بالضبط.
const List<String> _findObjectTriggers = ['وين', 'فين', 'اين'];

const List<String> _whatsAroundTriggers = [
  'شو قدامي',
  'ايش قدامي',
  'شو حولي',
  'ايش حولي',
  'ماذا امامي',
];

const List<String> _stopNavigationTriggers = [
  'الغاء التوجيه',
  'وقف التوجيه',
  'وقف',
  'الغاء',
];

/// يحوّل نص STT خام (بالعربي) إلى أمر مفهوم. الترتيب مقصود: نتحقق من
/// "إلغاء التوجيه" و"شو قدامي" أولًا (عبارات كاملة، احتمال تصادم
/// منخفض)، وأخيرًا "وين + اسم جسم" (الأوسع نطاقًا، محتاج استخراج اسم
/// جسم فعليًا من labels_ar حتى ما يتفاعل غلط مع أي جملة تحتوي "وين"
/// بالصدفة بدون اسم جسم معروف بعدها).
VoiceCommand parseVoiceCommand(String rawText) {
  final normalized = normalizeArabicText(rawText);

  for (final trigger in _stopNavigationTriggers) {
    if (normalized.contains(normalizeArabicText(trigger))) {

      return const StopNavigationCommand();
    }
  }

  for (final trigger in _whatsAroundTriggers) {
    if (normalized.contains(normalizeArabicText(trigger))) {
      return const WhatsAroundCommand();
    }
  }

  final hasFindTrigger = _findObjectTriggers.any(
        (trigger) => normalized.contains(normalizeArabicText(trigger)),
  );

  if (hasFindTrigger) {
    final englishLabel = _extractKnownObjectLabel(normalized);
    if (englishLabel != null) {
      return FindObjectCommand(
        arabicLabel: toArabicLabel(englishLabel),
        englishLabel: englishLabel,
      );
    }
  }

  // حتى بدون كلمة "وين" صراحة — لو الجملة كلها اسم جسم معروف بس
  // (المستخدم قال "الكرسي" مباشرة)، نتعامل معها كطلب بحث ضمنيًا.
  final englishLabel = _extractKnownObjectLabel(normalized);
  if (englishLabel != null) {
    return FindObjectCommand(
      arabicLabel: toArabicLabel(englishLabel),
      englishLabel: englishLabel,
    );
  }

  return UnknownCommand(rawText);
}

/// يفحص كل كلمة بالجملة لحالها أولًا (أدق)، ثم الجملة كاملة كخيار
/// أخير (يفيد لو اسم الجسم بالعربي أكثر من كلمة، مثل "طاولة طعام").
String? _extractKnownObjectLabel(String normalizedText) {
  for (final word in normalizedText.split(' ')) {
    final match = englishLabelForArabic(word);
    if (match != null) return match;
  }
  return englishLabelForArabic(normalizedText);
}
