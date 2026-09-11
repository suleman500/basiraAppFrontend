import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// طبقة الاستماع (Speech-to-Text) — مسؤوليتها الوحيدة: "حوّل كلام
/// لنص". لا تعرف أي شيء عن معنى النص أو الأوامر — هذا منطق
/// VoiceCommandParser بملف منفصل تمامًا.
///
/// ⚠️ الانتقال من Vosk إلى sherpa_onnx (next-gen Kaldi + ONNX runtime):
/// بعد سلسلة أخطاء متتالية مع vosk_flutter/vosk_flutter_2 (تعارض http،
/// namespace ناقص، minSdk 30، compileSdk 33 قديم)، sherpa_onnx نشطة
/// الصيانة ومحلية بالكامل بدون إنترنت وبدون أي خدمة Google.
///
/// ⚠️ فرق جوهري عن Vosk يستحق التوثيق: Vosk كان يدير المايكروفون
/// داخليًا (initSpeechService + start/stop مباشرة). sherpa_onnx يوفّر
/// فقط محرك التعرّف (OfflineRecognizer) — نحن نلتقط الصوت الخام بأنفسنا
/// عبر حزمة `record` (PCM16، 16kHz، قناة وحدة) ونمرره له يدويًا.
///
/// ⚠️ فرق جوهري تاني: موديل Moonshine اللي نستخدمه هو Offline
/// (non-streaming) — ما عنده partial results جاهزة من المحرك متل
/// Vosk. للحفاظ على نفس تجربة onText(text, isFinal=false) أثناء
/// الحكي، نسوي "decode دوري" (كل ~600ms) على الصوت المتراكم لحد
/// هلق. هذا مو استكمال حقيقي (كل مرة نعيد التعرّف من الصفر على كل
/// الصوت المسجَّل)، بس كافي لجمل قصيرة (أوامر صوتية).
///
/// ⚠️ sherpa_onnx (زي أغلب محركات ONNX) لازم ياخذ مسار ملف حقيقي على
/// القرص — مو مسار asset افتراضي جوا الـ APK. لهيك init() ينسخ ملفات
/// الموديل الثلاثة من assets إلى مجلد داخلي حقيقي (Application Support
/// Directory) أول مرة بس، وبعدين يشتغل من هناك بكل مرة.
class SpeechService {
  final void Function(String text, bool isFinal)? onText;

  final AudioRecorder _recorder = AudioRecorder();
  sherpa.OfflineRecognizer? _recognizer;

  StreamSubscription<Uint8List>? _audioStreamSub;
  Timer? _partialTimer;

  bool _isAvailable = false;
  bool _isListening = false;

  /// كل عينات PCM16 (بايتات خام) الملتقطة بالجلسة الحالية، بالترتيب.
  final List<Uint8List> _pcmChunks = [];

  /// آخر نص جزئي بعثناه، عشان ما نكرر onText لو النص ما تغيّر.
  String _lastPartialText = '';

  /// النص الكامل الأخير (جزئي أو نهائي) — يرجع من stopListening.
  String _currentText = '';

  SpeechService({this.onText});

  bool get isAvailable => _isAvailable;
  bool get isListening => _isListening;

  // مسارات ملفات الموديل جوا assets (زي ما مسجّلة بـ pubspec.yaml)
  static const String _assetDir = 'assets/models/sherpa-ar-stt';
  static const String _encoderAsset = '$_assetDir/encoder_model.ort';
  static const String _decoderAsset = '$_assetDir/decoder_model_merged.ort';
  static const String _tokensAsset = '$_assetDir/tokens.txt';

  static const int _sampleRate = 16000;

  /// أقل مدة صوت (بالبايت) قبل ما نحاول أي decode دوري — لتفادي
  /// تعريف محرك التعرّف على صوت فاضي/قصير جدًا كل 600ms بلا داعي.
  /// ~0.3 ثانية = 0.3 * 16000 * 2 بايت.
  static const int _minBytesForPartialDecode = 9600;

  static const Duration _partialInterval = Duration(milliseconds: 600);

  /// تهيئة المحرك: نسخ ملفات الموديل من assets لمسار حقيقي (أول مرة
  /// بس)، إنشاء OfflineRecognizer. لا يرمي استثناء لو فشل — يرجع
  /// false فقط (نفس أسلوب باقي خدمات المشروع الاختيارية).
  ///
  /// ⚠️ هذا الاستدعاء بياخذ وقت وقت أول تشغيل (نسخ الملفات + تحميل
  /// الموديل للذاكرة) — كم ثانية، مو فوري. طبيعي، مش تعليق أو خطأ.
  Future<bool> init() async {
    try {
      sherpa.initBindings();

      final String encoderPath =
      await _copyAssetToLocal(_encoderAsset, 'encoder_model.ort');
      final String decoderPath =
      await _copyAssetToLocal(_decoderAsset, 'decoder_model_merged.ort');
      final String tokensPath =
      await _copyAssetToLocal(_tokensAsset, 'tokens.txt');

      final modelConfig = sherpa.OfflineModelConfig(
        moonshine: sherpa.OfflineMoonshineModelConfig(
          encoder: encoderPath,
          mergedDecoder: decoderPath,
        ),
        tokens: tokensPath,
        numThreads: 2,
        debug: false,
        provider: 'cpu',
      );

      _recognizer = sherpa.OfflineRecognizer(
        sherpa.OfflineRecognizerConfig(model: modelConfig),
      );

      _isAvailable = true;
    } catch (e) {
      debugPrint('⚠️ SpeechService(sherpa_onnx): فشل التهيئة: $e');
      _isAvailable = false;
    }

    return _isAvailable;
  }

  /// ينسخ ملف من assets لمجلد داخلي حقيقي بالجهاز (لو مو منسوخ أصلاً)
  /// ويرجّع المسار الكامل على القرص.
  Future<String> _copyAssetToLocal(String assetPath, String fileName) async {
    final appDir = await getApplicationSupportDirectory();
    final modelDir = Directory('${appDir.path}/sherpa-ar-stt');
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }

    final outFile = File('${modelDir.path}/$fileName');
    if (await outFile.exists()) {
      return outFile.path;
    }

    final data = await rootBundle.load(assetPath);
    final bytes =
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    await outFile.writeAsBytes(bytes, flush: true);
    return outFile.path;
  }

  /// يبدأ الاستماع — يُستدعى لحظة ضغط زر الميكروفون. يفتح تسجيل PCM16
  /// خام من المايك عبر `record`، ويشغّل تايمر لعمل decode دوري
  /// (partial) أثناء ما المستخدم لسا ضاغط.
  Future<bool> startListening() async {
    if (!_isAvailable || _isListening || _recognizer == null) {
      return false;
    }

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      debugPrint('⚠️ SpeechService(sherpa_onnx): إذن المايكروفون مرفوض');
      return false;
    }

    _pcmChunks.clear();
    _lastPartialText = '';
    _currentText = '';

    try {
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: _sampleRate,
          numChannels: 1,
        ),
      );

      _audioStreamSub = stream.listen((chunk) => _pcmChunks.add(chunk));

      _partialTimer = Timer.periodic(_partialInterval, (_) {
        _runPartialDecode();
      });

      _isListening = true;
      return true;
    } catch (e) {
      debugPrint('⚠️ SpeechService(sherpa_onnx): فشل بدء الاستماع: $e');
      _isListening = false;
      return false;
    }
  }

  /// يوقف الاستماع — يُستدعى لحظة رفع الإصبع. يوقف التسجيل، يعمل
  /// decode نهائي على كل الصوت المتراكم، ويرجّع النص (أو null لو ما
  /// تعرّف على شي).
  Future<String?> stopListening() async {
    if (!_isListening) {
      return _currentText.isEmpty ? null : _currentText;
    }

    _partialTimer?.cancel();
    _partialTimer = null;

    try {
      await _audioStreamSub?.cancel();
      await _recorder.stop();
    } catch (e) {
      debugPrint('⚠️ SpeechService(sherpa_onnx): خطأ أثناء الإيقاف: $e');
    }
    _audioStreamSub = null;
    _isListening = false;

    final finalText = _decodeBufferedAudio();
    _currentText = finalText ?? '';

    if (finalText != null && finalText.isNotEmpty) {
      onText?.call(finalText, true);
    }

    _pcmChunks.clear();

    return _currentText.isEmpty ? null : _currentText;
  }

  /// يلغي الاستماع فورًا بدون اعتبار أي نص التُقط — يُستخدم لو
  /// المستخدم سحب إصبعه برّة الزر قبل الرفع (تراجع عن الأمر).
  Future<void> cancelListening() async {
    _partialTimer?.cancel();
    _partialTimer = null;

    try {
      await _audioStreamSub?.cancel();
      await _recorder.stop();
    } catch (_) {}
    _audioStreamSub = null;

    _isListening = false;
    _pcmChunks.clear();
    _lastPartialText = '';
    _currentText = '';
  }

  /// decode دوري على الصوت المتراكم لحد هلق — بمثابة "partial result".
  void _runPartialDecode() {
    final totalBytes = _pcmChunks.fold<int>(0, (sum, c) => sum + c.length);
    if (totalBytes < _minBytesForPartialDecode) return;

    final text = _decodeBufferedAudio();
    if (text == null || text.isEmpty || text == _lastPartialText) return;

    _lastPartialText = text;
    _currentText = text;
    onText?.call(text, false);
  }

  /// يدمج كل الـ chunks المتراكمة، يحوّلها لـ Float32، ويشغّل
  /// OfflineRecognizer عليها مرة وحدة. يرجّع null لو ما فيه صوت كافي.
  String? _decodeBufferedAudio() {
    if (_pcmChunks.isEmpty || _recognizer == null) return null;


    final totalLength = _pcmChunks.fold<int>(0, (sum, c) => sum + c.length);
    if (totalLength == 0) return null;

    final merged = Uint8List(totalLength);
    var offset = 0;
    for (final chunk in _pcmChunks) {
      merged.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }

    final samples = _pcm16ToFloat32(merged);

    final stream = _recognizer!.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: _sampleRate);
      _recognizer!.decode(stream);
      final result = _recognizer!.getResult(stream);
      return result.text.trim();
    } catch (e) {
      debugPrint('⚠️ SpeechService(sherpa_onnx): خطأ أثناء decode: $e');
      return null;
    } finally {
      stream.free();
    }
  }

  Float32List _pcm16ToFloat32(Uint8List pcm16) {
    final sampleCount = pcm16.length ~/ 2;
    final floats = Float32List(sampleCount);
    final byteData = ByteData.sublistView(pcm16);
    for (var i = 0; i < sampleCount; i++) {
      final sample = byteData.getInt16(i * 2, Endian.little);
      floats[i] = sample / 32768.0;
    }
    return floats;
  }

  Future<void> dispose() async {
    _partialTimer?.cancel();
    _partialTimer = null;

    try {
      await _audioStreamSub?.cancel();
    } catch (_) {}

    try {
      await _recorder.dispose();
    } catch (_) {}

    _recognizer?.free();
    _recognizer = null;
    _isAvailable = false;
    _isListening = false;
  }
}


String removeTashkeel(String input) {
  if (input.isEmpty) return input;

  // نطاق الحركات العربية في Unicode
  // \u064B-\u0652: تنوين فتح، تنوين ضم، تنوين كسر، فتحة، ضمة، كسرة، شدة، سكون
  // \u0653-\u0655: مد، همزة فوق، همزة تحت
  final tashkeelPattern = RegExp(r'[\u064B-\u0652\u0653-\u0655]');

  var result = input.replaceAll(tashkeelPattern, '');

  // توحيد المسافات المتعددة
  result = result.replaceAll(RegExp(r'\s+'), ' ').trim();

  return result;
}