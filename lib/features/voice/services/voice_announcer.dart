import 'package:flutter/foundation.dart';

import '../../../core/constants.dart';
import '../../detection/models/detected_object.dart';
import '../data/labels_ar.dart';
import 'flutter_tts_adapter.dart';
import 'tts_adapter.dart';

/// لغات النطق المدعومة.
enum SpeechLanguage { arabic, english }

/// يقرر "شو" و"متى" ينطق التطبيق باسم الأشياء المكتشفة — منطق قرار
/// خالص، بدون أي تفاصيل عن أي مكتبة TTS محدَّدة. التنفيذ الفعلي للنطق
/// مفوَّض بالكامل لـ TtsAdapter (اعتماد وليس تنفيذ مباشر) — لو بدنا
/// نجرّب محرك صوت ثاني مستقبلًا (بعد اختبار منعزل)، نمرر تطبيق TtsAdapter
/// مختلف هون فقط، بدون أي تعديل على منطق القرار نفسه.
class VoiceAnnouncer {
  final TtsAdapter _engine;
  final Map<String, DateTime> _lastAnnouncedAt = {};
  final Duration _cooldown = Duration(seconds: AppConstants.voiceCooldownSeconds);

  bool enabled = AppConstants.voiceEnabledByDefault;
  bool _isSpeaking = false;
  SpeechLanguage _language = SpeechLanguage.arabic;

  SpeechLanguage get language => _language;

  /// المحرك الافتراضي هو FlutterTtsAdapter (المضمون والمُختبَر). لتجربة
  /// محرك بديل: مرر تطبيق TtsAdapter آخر هنا، بدون تعديل أي شي تاني
  /// بهذا الملف.
  VoiceAnnouncer({TtsAdapter? engine}) : _engine = engine ?? FlutterTtsAdapter();

  Future<void> init() async {
    await _engine.init();
    await setLanguage(_language);
  }

  /// يبدّل لغة النطق فورًا. لو المحرك الحالي ما يدعم اللغة المطلوبة
  /// بالجهاز، تضل اللغة القديمة فعّالة (المحرك يرجع false).
  Future<void> setLanguage(SpeechLanguage lang) async {
    final localeCode = lang == SpeechLanguage.arabic ? 'ar' : 'en';
    final ok = await _engine.setLanguage(localeCode);
    if (ok) {
      _language = lang;
    } else {
      debugPrint('⚠️ اللغة "$localeCode" غير مدعومة، الإبقاء على اللغة الحالية');
    }
  }

  /// يُستدعى مع كل دفعة نتائج كشف جديدة.
  Future<void> announceIfNeeded(List<DetectedObject> detections) async {
    if (!enabled || detections.isEmpty || _isSpeaking) return;

    final now = DateTime.now();

    // نمرّ على كل الأجسام المكتشفة (وليس أولها فقط) وننطق كل جسم انتهت
    // فترة انتظاره، الواحد تلو الآخر. الترتيب السابق كان يوقف الحلقة
    // (break) بعد أول جسم يستاهل النطق — وبما إن نتائج الكشف مرتَّبة
    // دائمًا حسب الثقة تنازليًا، كان هذا يعني إن أعلى جسم ثقة (مثل
    // الحاسوب المحمول) يحتكر النطق دائمًا، وأجسام تانية ثابتة بنفس
    // المكان (كوب، فأرة) ما توصلها الحلقة أبدًا.
    for (final obj in detections) {
      final key = obj.trackingKey;
      final lastTime = _lastAnnouncedAt[key];

      final shouldAnnounce =
          lastTime == null || now.difference(lastTime) > _cooldown;

      if (shouldAnnounce) {
        _lastAnnouncedAt[key] = now;
        await _speak(_buildSentence(obj.label));
      }
    }
  }

  String _buildSentence(String englishLabel) {
    if (_language == SpeechLanguage.arabic) {
      return 'يوجد أمامك ${toArabicLabel(englishLabel)}';
    }
    return 'I see a $englishLabel in front of you';
  }

  Future<void> _speak(String text) async {
    _isSpeaking = true;
    try {
      await _engine.speak(text);
    } catch (e) {
      debugPrint('❌ خطأ بالنطق: $e');
    } finally {
      _isSpeaking = false;
    }
  }

  Future<void> dispose() async {
    await _engine.dispose();
  }
}