import '../../voice/data/labels_ar.dart';
import 'ai_backend_client.dart';
import 'voice_command_parser.dart';

/// طبقة إنقاذ (Fallback) للفهم — تُستدعى فقط لما parseVoiceCommand
/// المحلي (voice_command_parser.dart) يرجّع UnknownCommand، وكان في
/// اتصال بالباك-اند. هالملف ما بيستبدل الـparser المحلي أبدًا، بس
/// بيكمّله بالحالات اللي فشل فيها — الـparser المحلي يضل دايمًا أول
/// محطة، فوري ومجاني وبدون نت، لأنه هو نفسه اللي بيقرر "هل نفتح
/// الكاميرا أصلًا؟" — قرار لازم يصير محليًا بغض النظر عن حالة النت.
///
/// ⚠️ فرق جوهري عن ai_response_speaker.dart: هالاستدعاء يصير *قبل*
/// أي قرار بفتح الكاميرا (ما عنا صور ولا object_summary بعد بهاي
/// اللحظة). الـAI هون بس بيشوف النص المنطوق الخام، وبيرجّع تصنيف
/// نية (intent) ضمن نفس الفئات المحلية بالضبط — مو رد جاهز للنطق.
class AiIntentClassifier {
  final AiBackendClient client;

  const AiIntentClassifier(this.client);

  /// يحاول تصنيف [rawText] عبر الباك-اند. يرجّع null لو فشل الاتصال
  /// أو الرد كان غير صالح أو غير واثوق فيه — بهاي الحالة المستدعي
  /// (الشاشة) بيرجع لسلوكه الحالي (UnknownCommand + "ما فهمت الأمر").
  ///
  /// العقد المتوقّع من الباك-اند (POST /v1/voice/classify-intent):
  /// الطلب: {"text": "<النص الخام كما وصل من STT>"}
  /// الرد: {"intent": "find_object" | "whats_around" |
  ///        "stop_navigation" | "unknown", "object": "<اسم الجسم
  ///        بالعربي أو الإنجليزي، فقط لو intent = find_object>"}
  Future<VoiceCommand?> classify(String rawText) async {
    final response = await client.post('/v1/voice/classify-intent', {
      'text': rawText,
    });

    if (response == null) return null;

    final intent = response['intent'] as String?;
    if (intent == null) return null;

    switch (intent) {
      case 'stop_navigation':
        return const StopNavigationCommand();

      case 'whats_around':
        return const WhatsAroundCommand();

      case 'find_object':
        final objectPhrase = response['object'] as String?;
        if (objectPhrase == null || objectPhrase.trim().isEmpty) {
          return null;
        }

        // ⚠️ نتحقق من الاسم اللي رجّعه الـAI مقابل قاموسنا المحلي
        // (labels_ar.dart) قبل ما نثق فيه — الـAI ممكن يقترح اسم
        // جسم مو موجود أصلًا بموديل الكشف عنا (يعني ذاكرة الأجسام
        // ما رح تلاقيه أبدًا مهما كان الاسم صحيح لغويًا). نفس منطق
        // التحقق اللي بالـparser المحلي (englishLabelForArabic) هو
        // المرجع الوحيد الموثوق لأسماء الأجسام المدعومة فعليًا.
        final englishLabel = englishLabelForArabic(
          normalizeArabicText(objectPhrase),
        );

        if (englishLabel == null) return null;

        return FindObjectCommand(
          arabicLabel: toArabicLabel(englishLabel),
          englishLabel: englishLabel,
        );

      case 'unknown':
      default:
        return null;
    }
  }
}