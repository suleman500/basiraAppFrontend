import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// إعدادات الاتصال بالباك-اند الخاص فينا (السيرفر اللي رح تبنيه إنت،
/// وهو بدوره بيتواصل مع أي مزوّد AI تختاره من جهته — Claude، GPT، أو
/// غيره). هالملف ما بيعرف ولا لازم يعرف شو المزوّد؛ بس بيتكلم مع
/// الـAPI تبعنا نحن بعقد JSON ثابت، فتقدر تبدّل المودل من السيرفر
/// براحتك بدون ما تلمس التطبيق إطلاقًا.
///
/// ⚠️ ملاحظة أمان مهمة: [apiKey] هون بيصير جوا الـAPK/IPA النهائي،
/// وأي شخص يقدر يفكّه (reverse engineer) ويطلع المفتاح. لو المفتاح
/// نفسه بيتحكم بتكلفة حقيقية على حسابك (استدعاءات AI)، الأفضل
/// لاحقًا يكون هالمفتاح مو سر ثابت مشترك، بل توكن يتولّد لكل جهاز/
/// تثبيت (device-scoped)، والباك-اند هو اللي يتحقق ويحدد حدود
/// استخدام لكل توكن. هذا تحسين لاحق — مو ضروري للـMVP.
class AiBackendConfig {
  final String baseUrl;
  final String apiKey;
  final Duration timeout;

  const AiBackendConfig({
    required this.baseUrl,
    required this.apiKey,
    this.timeout = const Duration(seconds: 4),
  });
}

/// عميل HTTP خام بسيط للتواصل مع باك-اند بصيرة. لا يعرف شي عن
/// "تصنيف نية" ولا "صياغة رد" — هذول مسؤولية الملفات اللي تستخدمه
/// (ai_command_rewriter.dart، ai_response_composer.dart). هون بس:
/// أرسل JSON، استقبل JSON، وتعامل مع الفشل/انقطاع النت بهدوء وبدون
/// ما يوقف التطبيق.
///
/// ⚠️ ما بنتحقق من الاتصال بالإنترنت مسبقًا عبر حزمة زي
/// connectivity_plus عمدًا — هاي الحزمة بتقول بس "في واجهة شبكة
/// متاحة"، مو "في إنترنت فعليًا شغال" أو "السيرفر متجاوب حاليًا".
/// بدل هيك، منعتمد على timeout قصير (4 ثواني افتراضيًا) ونمسك كل
/// استثناء ممكن — نفس النتيجة العملية (ما وصلنا رد؟ ارجع null)، بس
/// بتغطي كل حالات الفشل مش بس "ما في شبكة" (سيرفر واقع، DNS فشل،
/// timeout بطيء، restart مفاجئ وقت التطوير...).
class AiBackendClient {
  final AiBackendConfig config;

  const AiBackendClient(this.config);

  /// يرسل POST بجسم [body] لمسار [path] (مثلاً 'v1/voice/rewrite-command'
  /// أو '/v1/voice/rewrite-command' — الاثنين شغالين، راجع
  /// [_buildUri]) ويرجّع الـJSON كـMap، أو null لو صار أي خطأ.
  Future<Map<String, dynamic>?> post(
      String path,
      Map<String, dynamic> body,
      ) async {
    try {
      final uri = _buildUri(path);

      final response = await http
          .post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${config.apiKey}',
        },
        body: jsonEncode(body),
      )
          .timeout(config.timeout);

      if (response.statusCode != 200) {
        debugPrint(
          '⚠️ AiBackendClient: رد غير ناجح من $path (${response.statusCode})',
        );
        return null;
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        debugPrint('⚠️ AiBackendClient: شكل رد غير متوقع من $path');
        return null;
      }

      return decoded;
    } catch (e) {
      debugPrint('⚠️ AiBackendClient: فشل الاتصال بـ$path: $e');
      return null;
    }
  }

  /// ⚠️ يبني الرابط النهائي بأمان بغض النظر عن وجود/غياب الشرطة
  /// المائلة (/) بنهاية [AiBackendConfig.baseUrl] أو ببداية [path] —
  /// أي تركيبة من الاثنين بتعطي نفس النتيجة الصحيحة. هذا بالضبط
  /// إصلاح مشكلة حقيقية صارت: baseUrl بدون شرطة نهائية + path بدون
  /// شرطة أول = رابط مكسور زي "http://host:3000v1/voice/..." بدل
  /// الصحيح "http://host:3000/v1/voice/...".
  Uri _buildUri(String path) {
    final trimmedBase = config.baseUrl.endsWith('/')
        ? config.baseUrl.substring(0, config.baseUrl.length - 1)
        : config.baseUrl;

    final normalizedPath = path.startsWith('/') ? path : '/$path';

    return Uri.parse('$trimmedBase$normalizedPath');
  }
}