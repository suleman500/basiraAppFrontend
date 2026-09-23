import 'ai_backend_client.dart';

/// ⚠️ يستبدل هذا الملف الفكرة القديمة بـai_intent_classifier.dart —
/// بدل ما الباك-اند يصنّف النية ويرجّع JSON منظّم (intent/object) نحوّله
/// يدويًا لـVoiceCommand، هون الباك-اند وظيفته أبسط بكتير: **يعيد
/// صياغة النص فقط** لأقرب صيغة قانونية معروفة (زي "وين الكرسي"، "شو
/// قدامي"، "وقف التوجيه")، وبعدين نمرّر النص المُعاد صياغته لنفس
/// parseVoiceCommand المحلي من جديد — زي أي نص عادي وصل من STT.
///
/// الفايدة: مصدر واحد بس لقاموس الأوامر المدعومة (voice_command_parser.
/// dart المحلي). الباك-اند ما يحتاج "يعرف" بنية VoiceCommand ولا
/// أسماء الحقول (intent/object...) — بس يحتاج يعرف الصيغ القانونية
/// كأمثلة بالـprompt. أي أمر جديد نضيفه بالـparser مستقبلًا، الباك-اند
/// بيقدر يستخدمه فور ما نحدّث أمثلة الـprompt عنده، بدون أي تغيير
/// بعقد الـJSON أو بكود Dart هون.
///
/// ⚠️ هذا الملف **ما بيلغي الفحص المحلي أبدًا** — يُستدعى فقط كخطوة
/// إضافية بعد ما parseVoiceCommand المحلي يفشل (UnknownCommand) وكان
/// في نت. لو مافي نت أو الباك-اند مو جاهز، النظام يرجع تلقائيًا
/// لسلوكه المحلي القديم بالضبط (راجع detection_screen.dart).
class AiCommandRewriter {
  final AiBackendClient client;

  const AiCommandRewriter(this.client);

  /// يحاول إعادة صياغة [rawText] (زي "نادي الكرسي" أو "الكرسي" لحالها
  /// أو "اوين الكرسي" بخطأ STT بسيط) لأقرب صيغة قانونية معروفة (زي
  /// "وين الكرسي"). يرجّع null لو فشل الاتصال، أو الرد فاضي، أو
  /// الباك-اند نفسه ما قدر يحدد قصد واضح — بهاي الحالة المستدعي
  /// بيكمل بالنص الأصلي زي ما كان (يعني نفس UnknownCommand القديم).
  ///
  /// العقد المتوقّع من الباك-اند (POST /v1/voice/rewrite-command):
  /// الطلب: {"text": "<النص الخام من STT>"}
  /// الرد: {"rewritten": "<جملة عربية بصيغة قانونية>" أو null/فاضي لو
  ///        الباك-اند نفسه غير واثق}
  Future<String?> rewrite(String rawText) async {
    final response = await client.post('/v1/voice/rewrite-command', {
      'text': rawText,
    });

    if (response == null) return null;

    final rewritten = response['rewritten'] as String?;
    if (rewritten == null || rewritten.trim().isEmpty) return null;

    return rewritten;
  }
}