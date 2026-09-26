import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// إعدادات الاتصال بالباك اند.
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

/// عميل HTTP للتواصل مع باك اند بصيرة.
///
/// إذا فشل الاتصال أو لم يرد الباك اند خلال المهلة، ترجع الدالة null.
/// التطبيق يستخدم هذا السلوك للرجوع تلقائيًا إلى التنفيذ المحلي.
class AiBackendClient {
  final AiBackendConfig config;

  const AiBackendClient(this.config);

  /// يرسل طلب POST إلى الباك اند.
  ///
  /// يمكن تمرير مهلة مختلفة للطلبات البطيئة مثل:
  /// - تركيب الصوت الخارجي
  /// - صياغة رد طويل
  ///
  /// إذا لم يتم تمرير [timeout] تستخدم المهلة الافتراضية من الإعدادات.
  Future<Map<String, dynamic>?> post(
      String path,
      Map<String, dynamic> body, {
        Duration? timeout,
      }) async {
    final uri = _buildUri(path);
    final requestTimeout = timeout ?? config.timeout;

    try {
      debugPrint(
        '🌐 AiBackendClient: إرسال طلب إلى $uri '
            '(مهلة ${requestTimeout.inSeconds} ثواني)',
      );

      final response = await http
          .post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${config.apiKey}',
        },
        body: jsonEncode(body),
      )
          .timeout(requestTimeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          '⚠️ AiBackendClient: رد غير ناجح من $path '
              '(${response.statusCode})',
        );
        return null;
      }

      if (response.bodyBytes.isEmpty) {
        debugPrint(
          '⚠️ AiBackendClient: الباك اند أعاد ردًا فارغًا من $path',
        );
        return null;
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));

      if (decoded is! Map<String, dynamic>) {
        debugPrint(
          '⚠️ AiBackendClient: شكل الرد غير متوقع من $path',
        );
        return null;
      }

      debugPrint(
        '✅ AiBackendClient: وصل رد ناجح من $path',
      );

      return decoded;
    } on TimeoutException {
      debugPrint(
        '⏱️ AiBackendClient: انتهت مهلة الاتصال بـ$path '
            'بعد ${requestTimeout.inSeconds} ثواني',
      );
      return null;
    } on FormatException catch (e) {
      debugPrint(
        '⚠️ AiBackendClient: رد JSON غير صالح من $path: $e',
      );
      return null;
    } catch (e) {
      debugPrint(
        '⚠️ AiBackendClient: فشل الاتصال بـ$path: $e',
      );
      return null;
    }
  }

  /// يبني الرابط النهائي بدون مشاكل في الشرطات المائلة.
  Uri _buildUri(String path) {
    final trimmedBase = config.baseUrl.endsWith('/')
        ? config.baseUrl.substring(0, config.baseUrl.length - 1)
        : config.baseUrl;

    final normalizedPath = path.startsWith('/') ? path : '/$path';

    return Uri.parse('$trimmedBase$normalizedPath');
  }
}