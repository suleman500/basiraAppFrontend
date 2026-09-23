import 'ai_backend_client.dart';
import 'object_summary.dart';

/// نتيجة صياغة + تركيب صوتي من الباك-اند. ⚠️ [audioBase64] ممكن
/// يكون null حتى لو [reply] موجود — راجع تعليق composeAndSpeak.js
/// بالباك-اند: الصياغة ممكن تنجح والتركيب الصوتي يفشل لحاله. المستدعي
/// (الشاشة) لازم يتحقق من الاثنين بشكل منفصل: لو فيه صوت، شغّله؛
/// لو ما فيه بس فيه نص، انطقه بمحرك محلي بدل ما يستسلم كليًا.
class AiComposedSpeech {
  final String? reply;
  final String? audioBase64;

  const AiComposedSpeech({this.reply, this.audioBase64});
}

/// يصوغ ردًا طبيعيًا **ويحوّله صوت** عبر الباك-اند بنداء وحد — يستقبل
/// النص المنطوق (للسياق) + قائمة DetectedObjectSummary (بيانات خام
/// رقمية بس، بدون أي صورة أو فيديو — راجع object_summary.dart).
///
/// ⚠️ فرق جوهري عن ai_command_rewriter.dart: هالاستدعاء يصير *بعد*
/// ما قرار "شو الأمر المطلوب" خلص أصلًا (محليًا أو عبر إعادة الصياغة)،
/// وبعد ما عنا بيانات فعلية (من كاميرا أو من الذاكرة) نصوغ منها رد.
/// الهدف هون صياغة الجملة النهائية + نطقها — مو فهم القصد.
class AiResponseComposer {
  final AiBackendClient client;

  const AiResponseComposer(this.client);

  /// يحاول صياغة رد طبيعي + تركيبه صوتيًا عبر الباك-اند. يرجّع null
  /// لو فشل الاتصال كليًا أو الباك-اند ما قدر يصوغ رد واثوق — بهاي
  /// الحالة المستدعي (الشاشة) بيرجع لصياغته الثابتة المحلية + محرك
  /// النطق المحلي. هذا يضمن التطبيق يشتغل 100% حتى لو الباك-اند غير
  /// جاهز أو النت مقطوع.
  ///
  /// العقد المتوقّع من الباك-اند (POST /v1/voice/compose-and-speak):
  /// الطلب: {"text": "<النص المنطوق الخام>",
  ///         "objects": [<DetectedObjectSummary.toJson() لكل جسم>]}
  /// الرد: {"reply": "<جملة عربية>" أو null,
  ///        "audioBase64": "<صوت MP3 بصيغة base64>" أو null}
  Future<AiComposedSpeech?> compose({
    required String rawText,
    required List<DetectedObjectSummary> objects,
  }) async {
    final response = await client.post('/v1/voice/compose-and-speak', {
      'text': rawText,
      'objects': objects.map((o) => o.toJson()).toList(),
    });

    if (response == null) return null;

    final reply = response['reply'] as String?;
    final audioBase64 = response['audioBase64'] as String?;

    final hasReply = reply != null && reply.trim().isNotEmpty;
    final hasAudio = audioBase64 != null && audioBase64.isNotEmpty;

    if (!hasReply && !hasAudio) return null;

    return AiComposedSpeech(
      reply: hasReply ? reply : null,
      audioBase64: hasAudio ? audioBase64 : null,
    );
  }
}