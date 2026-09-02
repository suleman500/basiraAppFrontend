import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../core/constants.dart';
import '../models/detected_object.dart';
import 'detector_service.dart' show YoloxDecodeJob, decodeYoloxDetections;
import 'frame_converter.dart';

/// نسخة بديلة (اختيارية بالكامل) لخدمة الكشف — تستخدم كود Kotlin أصلي
/// (Native) لتشغيل الموديل على خيط أندرويد حقيقي منفصل تمامًا عن خيط
/// الواجهة، بدل الاعتماد على tflite_flutter/Dart. الهدف: تفادي أي حظر
/// للواجهة (وبالتالي تقطيع الكاميرا) أثناء الاستدلال.
///
/// ⚠️ ملف منفصل بالكامل عن detector_service.dart الأصلي — القديم يبقى
/// شغّال وسليم بدون أي تعديل عليه. التبديل بينهم يصير بس عبر
/// AppConstants.useNativeDetector بملف detection_screen.dart.
///
/// نفس واجهة الاستخدام بالضبط (isReady / load / detect / dispose)
/// حتى يكون بديل مباشر بدون تغيير منطق الشاشة.
class NativeDetectorService {
  static const MethodChannel _channel =
  MethodChannel('basira/native_detector');

  List<String> _labels = [];
  List<int>? _outputShape;
  bool _modelLoaded = false;

  bool get isReady => _modelLoaded && _labels.isNotEmpty;

  Future<void> load() async {
    if (isReady) return;

    // نقرأ ملف الموديل والتسميات بـ Dart (زي العادة)، ونرسل بايتات
    // الموديل مرة وحدة بس لكود Kotlin، حتى ما يحتاج يعرف تفاصيل نظام
    // assets الخاص بفلاتر.
    final modelData = await rootBundle.load(
      AppConstants.detectionModelPath,
    );
    final modelBytes = modelData.buffer.asUint8List(
      modelData.offsetInBytes,
      modelData.lengthInBytes,
    );

    final labelsRaw = await rootBundle.loadString(
      AppConstants.labelsPath,
    );
    _labels = labelsRaw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final response = await _channel.invokeMapMethod<String, dynamic>(
      'loadModel',
      {'modelBytes': modelBytes},
    );

    if (response == null) {
      throw Exception('فشل تحميل الموديل بالكود الأصلي (Native)');
    }

    _outputShape = (response['outputShape'] as List).cast<int>();
    _modelLoaded = true;

    debugPrint(
      'Native Detector: تم التحميل بنجاح، شكل المخرج: $_outputShape',
    );
  }

  Future<List<DetectedObject>> detect(
      ConvertedFrame frame, {
        required int fullWidth,
        required int fullHeight,
      }) async {
    if (!isReady) return [];

    // نفس منطق YOLOX (قيم بكسل خام 0..255، بدون قسمة على 255) —
    // راجع تعليق detector_service.dart الأصلي لتفاصيل هذا الفخ.
    final flatInput = Float32List(frame.rgbBytes.length);
    for (int i = 0; i < flatInput.length; i++) {
      flatInput[i] = frame.rgbBytes[i].toDouble();
    }

    final inputBytes = flatInput.buffer.asUint8List();

    final outputBytes = await _channel.invokeMethod<Uint8List>(
      'runInference',
      {'input': inputBytes},
    );

    if (outputBytes == null) return [];

    // ⚠️ إصلاح مهم: الـ Uint8List الواصل من القناة أحيانًا يبدأ من
    // إزاحة (offset) غير قابلة للقسمة على 4 جوا الذاكرة الأصلية (تفصيل
    // داخلي بآلية النقل بين Dart والكود الأصلي) — و Float32List.view
    // تتطلب إزاحة قابلة للقسمة على 4 بالضبط (كل رقم = 4 بايت). ننسخ
    // البيانات لبفر جديد نظيف يبدأ من الصفر (دايمًا قابل للقسمة على 4)
    // قبل القراءة، لتفادي RangeError.
    final alignedBytes = Uint8List.fromList(outputBytes);
    final flatOutput = Float32List.view(
      alignedBytes.buffer,
      0,
      alignedBytes.lengthInBytes ~/ 4,
    );

    final job = YoloxDecodeJob(
      values: flatOutput,
      dimA: _outputShape![1],
      dimB: _outputShape![2],
      labels: _labels,
      inputSize: frame.size,
      originalWidth: fullWidth,
      originalHeight: fullHeight,
      confidenceThreshold: AppConstants.confidenceThreshold,
      iouThreshold: AppConstants.iouThreshold,
      manualGridDecodeRequired: true,
      yoloxStrides: AppConstants.yoloxStrides,
    );

    return decodeYoloxDetections(job);
  }

  void dispose() {
    // ما في موارد Dart-side لازم نحررها هون — الموديل نفسه محفوظ
    // ومُدار بالكامل بالجانب الأصلي (Kotlin).
  }
}