import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'tts_adapter.dart';

/// تطبيق TtsAdapter باستخدام flutter_tts — محرك النطق المدمج بنظام
/// الهاتف نفسه. هذا هو المحرك "الافتراضي المضمون" لكل التطوير
/// والاختبار، بغض النظر عن أي محرك بديل نجرّبه مستقبلًا.
class FlutterTtsAdapter implements TtsAdapter {
  final FlutterTts _tts = FlutterTts();

  @override
  Future<void> init() async {
    await _tts.awaitSpeakCompletion(true);
    await _tts.setSpeechRate(0.45);
    await _tts.setPitch(1.0);
    await _tts.setVolume(1.0);
  }

  @override
  Future<bool> setLanguage(String localeCode) async {
    try {
      await _tts.setLanguage(localeCode);
      await _selectBestVoice(localeCode);
      return true;
    } catch (e) {
      debugPrint('⚠️ FlutterTtsAdapter: تعذّر ضبط اللغة "$localeCode": $e');
      return false;
    }
  }

  /// يدور على الأصوات المتاحة بالجهاز بلغة محدَّدة، ويفضّل أي صوت
  /// معلَّم بجودة محسّنة (enhanced/network/wavenet/neural) إن وُجد.
  Future<void> _selectBestVoice(String localeCode) async {
    try {
      final voices = await _tts.getVoices as List<dynamic>?;
      if (voices == null || voices.isEmpty) return;

      final matching = voices.where((v) {
        final locale = (v['locale'] ?? '').toString().toLowerCase();
        return locale.startsWith(localeCode);
      }).toList();
      if (matching.isEmpty) {
        debugPrint('⚠️ FlutterTtsAdapter: ما في صوت بلغة "$localeCode"');
        return;
      }

      dynamic best;
      for (final v in matching) {
        final name = (v['name'] ?? '').toString().toLowerCase();
        if (name.contains('enhanced') ||
            name.contains('network') ||
            name.contains('wavenet') ||
            name.contains('neural')) {
          best = v;
          break;
        }
      }
      best ??= matching.first;

      await _tts.setVoice({
        'name': best['name'].toString(),
        'locale': best['locale'].toString(),
      });
    } catch (e) {
      debugPrint('⚠️ FlutterTtsAdapter: تعذّر اختيار أفضل صوت: $e');
    }
  }

  @override
  Future<void> speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }

  @override
  Future<void> dispose() async {
    await _tts.stop();
  }
}