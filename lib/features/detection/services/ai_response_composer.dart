import 'ai_backend_client.dart';
import 'object_summary.dart';

/// نتيجة صياغة الرد وتركيب الصوت عبر الباك اند.
///
/// [reply] هو النص المصاغ من الذكاء الاصطناعي.
/// [audioBase64] هو ملف الصوت الخارجي بصيغة MP3 مشفرًا بـ Base64.
class AiComposedSpeech {
  final String? reply;
  final String? audioBase64;

  const AiComposedSpeech({
    this.reply,
    this.audioBase64,
  });
}

/// يطلب من الباك اند:
///
/// 1. صياغة رد عربي أفضل.
/// 2. تحويل الرد إلى صوت خارجي.
///
/// إذا كان الباك اند غير متوفر أو لا يوجد إنترنت أو تأخر الرد، ترجع
/// الدالة null، وعندها يستخدم التطبيق الرد والصوت المحليين.
class AiResponseComposer {
  final AiBackendClient client;

  const AiResponseComposer(this.client);

  /// يرسل طلب صياغة وصوت خارجي.
  ///
  /// مسار الباك اند المطلوب:
  ///
  /// POST /v1/voice/compose-and-speak
  ///
  /// الطلب:
  ///
  /// {
  ///   "text": "النص الأصلي",
  ///   "objects": []
  /// }
  ///
  /// الرد المتوقع:
  ///
  /// {
  ///   "reply": "الكرسي أمامك على يمينك",
  ///   "audioBase64": "...."
  /// }
  ///
  /// مهلة الصوت أطول من بقية الطلبات؛ لأن الباك اند قد يحتاج إلى:
  ///
  /// - الاتصال بمزود الذكاء الاصطناعي
  /// - صياغة النص
  /// - طلب الصوت الخارجي
  /// - تحويل الملف وإرساله للتطبيق
  Future<AiComposedSpeech?> compose({
    required String rawText,
    required List<DetectedObjectSummary> objects,
  }) async {
    final response = await client.post(
      '/v1/voice/compose-and-speak',
      {
        'text': rawText,
        'objects': objects.map((object) => object.toJson()).toList(),
      },
      timeout: const Duration(seconds: 30),
    );

    // الباك اند غير متوفر أو الإنترنت غير موجود.
    if (response == null) {
      return null;
    }

    final reply = _readString(response['reply']);
    final audioBase64 = _readString(response['audioBase64']);

    final hasReply = reply != null && reply.trim().isNotEmpty;
    final hasAudio = audioBase64 != null && audioBase64.trim().isNotEmpty;

    // لا يوجد نص ولا ملف صوت.
    if (!hasReply && !hasAudio) {
      return null;
    }

    return AiComposedSpeech(
      reply: hasReply ? reply : null,
      audioBase64: hasAudio ? audioBase64 : null,
    );
  }

  String? _readString(dynamic value) {
    if (value is! String) {
      return null;
    }

    final result = value.trim();

    if (result.isEmpty || result == 'null') {
      return null;
    }

    return result;
  }
}