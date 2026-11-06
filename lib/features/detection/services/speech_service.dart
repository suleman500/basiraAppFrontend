import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// طبقة الاستماع (Speech-to-Text) — مسؤوليتها الوحيدة: "حوّل كلام
/// لنص". لا تعرف أي شيء عن معنى النص أو الأوامر.
///
/// موديل Moonshine (عربي) عبر sherpa_onnx، الصوت بيتلتقط بـ `record`.
///
/// ⚠️ التغييرات بهالنسخة (نفس الواجهة العامة بالضبط، بدون كسر أي استدعاء):
///
/// 1) التفريغ (decode) صار بـIsolate خلفي منفصل. استدعاءات sherpa_onnx
///    (FFI) متزامنة: لو اشتغلت على الخيط الرئيسي بتجمّد الشاشة والكاميرا
///    طول مدة التفريغ. هلق الخيط الرئيسي بس بيرسل الصوت ويستنى النتيجة.
///
/// 2) ما عاد في decode دوري كل 600ms أثناء الحكي. النسخة القديمة كانت
///    تعيد التعرّف على كل الصوت من الصفر كل 600ms على الخيط الرئيسي —
///    وهذا السبب الأكبر لتقطيع الكاميرا وقت الضغط على المايك. النتائج
///    الجزئية اختيارية هلق (enablePartialResults، الافتراضي false)،
///    والأوامر الصوتية ما بتحتاجها أصلًا.
///
/// 3) بعد رفع الإصبع بنكمّل التقاط الصوت [_tailRecordingGrace] قبل ما
///    نوقف المايك — بدونها كان آخر جزء من الكلمة الأخيرة بينقطع
///    (الزج، السج، الح...).
///
/// 4) بنضيف [_trailingSilenceSeconds] صمت لآخر الصوت قبل التفريغ.
///    Moonshine بيحدد سقف لعدد التوكنات حسب طول الصوت، وللعربي (غير
///    لاتيني) السقف الافتراضي ممكن يقصّ آخر الكلام. الصمت بيزيد الطول
///    فبيرفع السقف. (تخمين مبني على توثيق Moonshine، يحتاج تجربة.)
class SpeechService {
  final void Function(String text, bool isFinal)? onText;

  /// نتائج جزئية أثناء الحكي. ⚠️ مكلفة (تفريغ كل [_partialInterval]
  /// حتى لو بالخلفية). اتركها false إلا لو الواجهة فعلًا بتعرض النص
  /// لحظة بلحظة.
  final bool enablePartialResults;

  final AudioRecorder _recorder = AudioRecorder();

  Isolate? _worker;
  SendPort? _workerPort;
  final ReceivePort _replyPort = ReceivePort();
  final Map<int, Completer<String?>> _pending = {};
  int _nextRequestId = 0;

  StreamSubscription<Uint8List>? _audioStreamSub;
  Timer? _partialTimer;

  bool _isAvailable = false;
  bool _isListening = false;
  bool _isStopping = false;
  bool _partialInFlight = false;

  /// رقم الجلسة الحالية — بيتغيّر مع كل start/cancel، حتى لو stop كان
  /// منتظر (grace) وانلغت الجلسة بالنص ما يكمل على جلسة ميتة.
  int _session = 0;

  /// كل عينات PCM16 (بايتات خام) الملتقطة بالجلسة الحالية، بالترتيب.
  final List<Uint8List> _pcmChunks = [];

  String _lastPartialText = '';
  String _currentText = '';

  SpeechService({this.onText, this.enablePartialResults = false});

  bool get isAvailable => _isAvailable;
  bool get isListening => _isListening;

  static const String _assetDir = 'assets/models/sherpa-ar-stt';
  static const String _encoderAsset = '$_assetDir/encoder_model.ort';
  static const String _decoderAsset = '$_assetDir/decoder_model_merged.ort';
  static const String _tokensAsset = '$_assetDir/tokens.txt';

  static const int _sampleRate = 16000;

  /// أقل صوت (بالبايت) قبل ما نحاول أي decode — 0.3 ثانية.
  static const int _minBytesForDecode = 9600;

  static const Duration _partialInterval = Duration(milliseconds: 900);

  /// نكمّل التسجيل هالمدة بعد رفع الإصبع (لتجنب قص آخر كلمة).
  /// لو بتحس بتأخير، نزّلها لـ 300ms. لو لسا بينقطع آخر الكلام، ارفعها.
  static const Duration _tailRecordingGrace = Duration(milliseconds: 500);

  /// صمت بنضيفه لآخر الصوت قبل التفريغ.
  static const double _trailingSilenceSeconds = 0.8;

  static const Duration _decodeTimeout = Duration(seconds: 15);

  /// تهيئة: نسخ ملفات الموديل من assets (أول مرة بس)، تشغيل الـIsolate
  /// الخلفي وتحميل الموديل فيه. لا يرمي استثناء — يرجع false لو فشل.
  Future<bool> init() async {
    try {
      final String encoderPath =
      await _copyAssetToLocal(_encoderAsset, 'encoder_model.ort');
      final String decoderPath =
      await _copyAssetToLocal(_decoderAsset, 'decoder_model_merged.ort');
      final String tokensPath =
      await _copyAssetToLocal(_tokensAsset, 'tokens.txt');

      _replyPort.listen((dynamic message) {
        if (message is List && message.length == 2) {
          final id = message[0] as int;
          final text = message[1] as String?;
          _pending.remove(id)?.complete(text);
        }
      });

      final readyPort = ReceivePort();
      _worker = await Isolate.spawn<Map<String, Object>>(
        _sttWorkerMain,
        {
          'mainPort': readyPort.sendPort,
          'encoderPath': encoderPath,
          'decoderPath': decoderPath,
          'tokensPath': tokensPath,
          'numThreads': 2,
        },
      );

      final dynamic first =
      await readyPort.first.timeout(const Duration(seconds: 90));
      readyPort.close();

      if (first is SendPort) {
        _workerPort = first;
        _isAvailable = true;
      } else {
        debugPrint('⚠️ SpeechService: فشل تهيئة الـIsolate: $first');
        _worker?.kill(priority: Isolate.immediate);
        _worker = null;
        _isAvailable = false;
      }
    } catch (e) {
      debugPrint('⚠️ SpeechService(sherpa_onnx): فشل التهيئة: $e');
      _isAvailable = false;
    }

    return _isAvailable;
  }

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

  /// يبدأ الاستماع — لحظة ضغط زر الميكروفون.
  Future<bool> startListening() async {
    if (!_isAvailable || _isListening || _isStopping || _workerPort == null) {
      return false;
    }

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      debugPrint('⚠️ SpeechService(sherpa_onnx): إذن المايكروفون مرفوض');
      return false;
    }

    _session++;
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

      if (enablePartialResults) {
        _partialTimer = Timer.periodic(_partialInterval, (_) {
          _runPartialDecode();
        });
      }

      _isListening = true;
      return true;
    } catch (e) {
      debugPrint('⚠️ SpeechService(sherpa_onnx): فشل بدء الاستماع: $e');
      _isListening = false;
      return false;
    }
  }

  /// يوقف الاستماع — لحظة رفع الإصبع. بيكمّل التقاط الصوت
  /// [_tailRecordingGrace] أول، بعدين بيفرّغ بالـIsolate الخلفي.
  Future<String?> stopListening() async {
    if (!_isListening) {
      return _currentText.isEmpty ? null : _currentText;
    }
    if (_isStopping) return null;

    _isStopping = true;
    final int session = _session;

    _partialTimer?.cancel();
    _partialTimer = null;

    // نكمّل نلتقط آخر جزء من الكلام قبل ما نقفل المايك.
    await Future<void>.delayed(_tailRecordingGrace);

    // لو انلغت الجلسة أو بدأت وحدة جديدة خلال الانتظار، لا نكمل.
    if (session != _session) {
      _isStopping = false;
      return null;
    }

    try {
      await _audioStreamSub?.cancel();
      await _recorder.stop();
    } catch (e) {
      debugPrint('⚠️ SpeechService(sherpa_onnx): خطأ أثناء الإيقاف: $e');
    }
    _audioStreamSub = null;
    _isListening = false;

    final samples = _buildSamples(trailingSilenceSeconds: _trailingSilenceSeconds);
    _pcmChunks.clear();

    String? finalText;
    if (samples != null) {
      final stopwatch = Stopwatch()..start();
      final raw = await _decodeInWorker(samples);
      stopwatch.stop();

      finalText = raw == null ? null : removeTashkeel(raw.trim());
      final audioSeconds = samples.length / _sampleRate;
      debugPrint(
        '🎙️ STT: ${stopwatch.elapsedMilliseconds}ms لتفريغ '
            '${audioSeconds.toStringAsFixed(1)}s صوت ← "${finalText ?? ''}"',
      );
    }

    _currentText = finalText ?? '';
    _isStopping = false;

    if (session != _session) return null;

    if (finalText != null && finalText.isNotEmpty) {
      onText?.call(finalText, true);
    }

    return _currentText.isEmpty ? null : _currentText;
  }

  /// يلغي الاستماع فورًا بدون اعتبار أي نص التُقط.
  Future<void> cancelListening() async {
    _session++;
    _partialTimer?.cancel();
    _partialTimer = null;

    try {
      await _audioStreamSub?.cancel();
      await _recorder.stop();
    } catch (_) {}
    _audioStreamSub = null;

    _isListening = false;
    _isStopping = false;
    _pcmChunks.clear();
    _lastPartialText = '';
    _currentText = '';
  }

  /// نتيجة جزئية (اختيارية): تفريغ لقطة من الصوت لحد هلق، بالخلفية،
  /// ونتجاهل الطلب لو اللي قبله لسا ما خلّص.
  Future<void> _runPartialDecode() async {
    if (_partialInFlight || !_isListening) return;

    final samples = _buildSamples(trailingSilenceSeconds: 0);
    if (samples == null) return;

    _partialInFlight = true;
    final int session = _session;
    try {
      final raw = await _decodeInWorker(samples);
      if (session != _session || !_isListening) return;

      final text = raw == null ? '' : removeTashkeel(raw.trim());
      if (text.isEmpty || text == _lastPartialText) return;

      _lastPartialText = text;
      _currentText = text;
      onText?.call(text, false);
    } finally {
      _partialInFlight = false;
    }
  }

  /// يدمج الـchunks، يحوّلها لـFloat32، ويضيف صمت بالآخر. يرجّع null لو
  /// الصوت قصير جدًا.
  Float32List? _buildSamples({required double trailingSilenceSeconds}) {
    final totalLength = _pcmChunks.fold<int>(0, (sum, c) => sum + c.length);
    if (totalLength < _minBytesForDecode) return null;

    final merged = Uint8List(totalLength);
    var offset = 0;
    for (final chunk in _pcmChunks) {
      merged.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }

    final sampleCount = merged.length ~/ 2;
    final padCount = (_sampleRate * trailingSilenceSeconds).round();

    // Float32List بيبدأ أصفار، فالصمت (padCount) جاهز بدون ملء.
    final floats = Float32List(sampleCount + padCount);
    final byteData = ByteData.sublistView(merged);
    for (var i = 0; i < sampleCount; i++) {
      floats[i] = byteData.getInt16(i * 2, Endian.little) / 32768.0;
    }
    return floats;
  }

  /// يرسل الصوت للـIsolate الخلفي ويستنى النص. null لو فشل أو انتهت
  /// المهلة.
  Future<String?> _decodeInWorker(Float32List samples) async {
    final port = _workerPort;
    if (port == null) return null;

    final id = _nextRequestId++;
    final completer = Completer<String?>();
    _pending[id] = completer;

    port.send(<Object>[
      'decode',
      id,
      _replyPort.sendPort,
      TransferableTypedData.fromList(<TypedData>[samples]),
      _sampleRate,
    ]);

    try {
      return await completer.future.timeout(_decodeTimeout);
    } on TimeoutException {
      _pending.remove(id);
      debugPrint('⚠️ SpeechService: انتهت مهلة التفريغ (${_decodeTimeout.inSeconds}s)');
      return null;
    }
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

    _workerPort?.send(<Object>['dispose']);
    _worker?.kill(priority: Isolate.beforeNextEvent);
    _worker = null;
    _workerPort = null;

    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.complete(null);
    }
    _pending.clear();
    _replyPort.close();

    _isAvailable = false;
    _isListening = false;
    _isStopping = false;
  }
}

/// نقطة دخول الـIsolate الخلفي: بيحمّل الموديل مرة وحدة، وبعدين بيستقبل
/// طلبات decode ويرد بالنص. محرك sherpa بيعيش هون بس (مؤشرات native
/// ما بتنتقل بين الـIsolates).
void _sttWorkerMain(Map<String, Object> init) {
  final SendPort mainPort = init['mainPort'] as SendPort;
  final commandPort = ReceivePort();
  sherpa.OfflineRecognizer? recognizer;

  try {
    sherpa.initBindings();

    recognizer = sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          moonshine: sherpa.OfflineMoonshineModelConfig(
            encoder: init['encoderPath'] as String,
            mergedDecoder: init['decoderPath'] as String,
          ),
          tokens: init['tokensPath'] as String,
          numThreads: init['numThreads'] as int,
          debug: false,
          provider: 'cpu',
        ),
      ),
    );

    mainPort.send(commandPort.sendPort); // جاهز
  } catch (e) {
    mainPort.send('init_error: $e');
    return;
  }

  commandPort.listen((dynamic message) {
    if (message is! List || message.isEmpty) return;
    final command = message[0] as String;

    if (command == 'dispose') {
      recognizer?.free();
      recognizer = null;
      commandPort.close();
      return;
    }

    if (command == 'decode') {
      final id = message[1] as int;
      final replyPort = message[2] as SendPort;
      final samples =
      (message[3] as TransferableTypedData).materialize().asFloat32List();
      final sampleRate = message[4] as int;

      final r = recognizer;
      if (r == null) {
        replyPort.send(<Object?>[id, null]);
        return;
      }

      String? text;
      final stream = r.createStream();
      try {
        stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
        r.decode(stream);
        text = r.getResult(stream).text;
      } catch (_) {
        text = null;
      } finally {
        stream.free();
      }

      replyPort.send(<Object?>[id, text]);
    }
  });
}

/// إزالة الحركات العربية (تشكيل) من النص — بدون توحيد أشكال الحروف.
String removeTashkeel(String input) {
  if (input.isEmpty) return input;

  final tashkeelPattern = RegExp(r'[\u064B-\u0652\u0653-\u0655]');

  var result = input.replaceAll(tashkeelPattern, '');
  result = result.replaceAll(RegExp(r'\s+'), ' ').trim();

  return result;
}