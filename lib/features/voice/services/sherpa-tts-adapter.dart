import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart' show rootBundle, AssetManifest;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import '../../../core/constants.dart';
import 'tts_adapter.dart';

/// تطبيق TtsAdapter باستخدام sherpa_onnx.OfflineTts الرسمي — نفس الحزمة
/// المستخدَمة أصلًا للـSTT، صفر مكتبة native جديدة، صفر احتمال تعارض
/// libonnxruntime.so (اللي عانينا منه مع onnxruntime المنفصلة).
///
/// الموديل: vits-piper-ar_JO-kareem-medium (صوت أردني ذكر، متحدث واحد).
class SherpaTtsAdapter implements TtsAdapter {
  sherpa_onnx.OfflineTts? _tts;
  final AudioPlayer _player = AudioPlayer();

  /// السرعة اللي اخترتها بعد التجربة الفعلية على جهازك.
  final double speed;

  SherpaTtsAdapter({this.speed = 1.2});

  @override
  Future<void> init() async {
    sherpa_onnx.initBindings();

    final realDir = await _ensureAssetsCopied();

    final vits = sherpa_onnx.OfflineTtsVitsModelConfig(
      model: '$realDir/ar_JO-kareem-medium.onnx',
      tokens: '$realDir/tokens.txt',
      dataDir: '$realDir/espeak-ng-data',
    );

    final modelConfig = sherpa_onnx.OfflineTtsModelConfig(
      vits: vits,
      numThreads: 2,
      debug: false,
    );

    final config = sherpa_onnx.OfflineTtsConfig(
      model: modelConfig,
      maxNumSenetences: 1,
    );

    _tts = sherpa_onnx.OfflineTts(config);
  }

  /// ينسخ كل ملفات tts-ar (الموديل + tokens + مجلد espeak-ng-data كامل
  /// بكل تفرّعاته) من الـassets لمجلد حقيقي بالجهاز — لازم لأنه
  /// sherpa_onnx (زي أي مكتبة native) تحتاج مسارات ملفات حقيقية على
  /// القرص، مو مسارات asset افتراضية جوا الـAPK.
  ///
  /// نستخدم AssetManifest.json لمعرفة كل الملفات المرتبطة بهذا المجلد
  /// تلقائيًا (بدل ما نكتب مئات الأسماء يدويًا بالكود — نفس السبب اللي
  /// خلانا نستخدم سكربت توليد تلقائي بـpubspec.yaml).
  Future<String> _ensureAssetsCopied() async {
    final appDir = await getApplicationSupportDirectory();
    final targetDir = Directory('${appDir.path}/tts-ar');
    final marker = File('${targetDir.path}/.copied_ok');

    if (await marker.exists()) {
      return targetDir.path;
    }

    final assetManifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final ttsArAssetKeys = assetManifest
        .listAssets()
        .where((key) => key.startsWith(AppConstants.ttsArAssetPrefix))
        .toList();

    for (final assetKey in ttsArAssetKeys) {
      final relativePath =
      assetKey.substring(AppConstants.ttsArAssetPrefix.length);
      final destFile = File('${targetDir.path}/$relativePath');

      await destFile.parent.create(recursive: true);

      final data = await rootBundle.load(assetKey);
      final bytes =
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      await destFile.writeAsBytes(bytes, flush: true);
    }

    await marker.create(recursive: true);
    return targetDir.path;
  }

  @override
  Future<bool> setLanguage(String localeCode) async {
    // المحرك محلي وعربي فقط حاليًا (موديل واحد ثابت).
    return localeCode.toLowerCase().startsWith('ar');
  }

  @override
  Future<void> speak(String text) async {
    final tts = _tts;
    if (tts == null) {
      throw StateError('SherpaTtsAdapter: لازم تنادي init() أول');
    }

    final genConfig = sherpa_onnx.OfflineTtsGenerationConfig(
      sid: 0,
      speed: speed,
      silenceScale: 0.2,
    );

    final audio = tts.generateWithConfig(text: text, config: genConfig);

    final tempDir = await getTemporaryDirectory();
    final wavPath = '${tempDir.path}/tts_ar_output.wav';

    sherpa_onnx.writeWave(
      filename: wavPath,
      samples: audio.samples,
      sampleRate: audio.sampleRate,
    );

    await _player.stop();
    await _player.play(DeviceFileSource(wavPath));
  }

  @override
  Future<void> stop() async {
    await _player.stop();
  }

  @override
  Future<void> dispose() async {
    await _player.stop();
    await _player.dispose();
    _tts?.free();
    _tts = null;
  }
}