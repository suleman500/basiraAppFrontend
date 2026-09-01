import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../../core/constants.dart';
import 'frame_converter.dart';

/// نتيجة خريطة العمق بعد تشغيل موديل العمق.
class DepthMap {
  final List<double> values;
  final int width;
  final int height;

  const DepthMap({
    required this.values,
    required this.width,
    required this.height,
  });

  double valueAt(int x, int y) {
    final safeX = x.clamp(0, width - 1);
    final safeY = y.clamp(0, height - 1);
    final index = safeY * width + safeX;
    if (index < 0 || index >= values.length) return 0.0;
    return values[index];
  }
}

/// خدمة تشغيل موديل العمق (MiDaS Small).
///
///  لمعرفة تفاصيل شكل الموديل، تحسينات الأداء، والتنبيهات المهمة،
/// راجع ملف DEVELOPMENT_NOTES.md.
class DepthService {
  Interpreter? _interpreter;
  IsolateInterpreter? _isolateInterpreter;

  bool get isReady => _isolateInterpreter != null;

  Future<void> load() async {
    if (isReady) return;

    final options = InterpreterOptions()..threads = 4;
    try {
      options.addDelegate(XNNPackDelegate());
    } catch (e) {
      debugPrint('Depth: XNNPack failed, using CPU: $e');
    }

    _interpreter = await Interpreter.fromAsset(
      AppConstants.depthModelPath,
      options: options,
    );

    _isolateInterpreter = await IsolateInterpreter.create(
      address: _interpreter!.address,
    );

    debugPrint('Depth input shape: ${_interpreter!.getInputTensor(0).shape}');
    debugPrint('Depth output shape: ${_interpreter!.getOutputTensor(0).shape}');
  }

  /// تشغيل موديل العمق على إطار واحد.
  Future<DepthMap?> predict(ConvertedFrame frame) async {
    if (!isReady) return null;

    final flatInput = _bytesToInputTensor(frame.rgbBytes, frame.size);
    final input = flatInput.reshape([1, 3, frame.size, frame.size]);

    final outputTensor = _interpreter!.getOutputTensor(0);
    final outputShape = outputTensor.shape;
    final totalOutputElements = outputShape.reduce((a, b) => a * b);

    final output = Float32List(totalOutputElements).reshape(outputShape);
    await _isolateInterpreter!.run(input, output);

    final values = _flatten(output);
    final dimensions = _findSpatialDimensions(outputShape);
    if (dimensions == null) {
      debugPrint('Unsupported depth output shape: $outputShape');
      return null;
    }

    final expectedLength = dimensions.width * dimensions.height;
    if (values.length < expectedLength) {
      debugPrint('Depth output has too few values. Expected: $expectedLength, actual: ${values.length}');
      return null;
    }

    return DepthMap(
      values: values.take(expectedLength).toList(),
      width: dimensions.width,
      height: dimensions.height,
    );
  }

  /// استخراج قيمة العمق من منطقة 3×3 حول مركز المربع.
  /// تستخدم الوسيط لتقليل الضوضاء.
  double? distanceAt({
    required DepthMap map,
    required Rect box,
    required int fullWidth,
    required int fullHeight,
  }) {
    if (fullWidth <= 0 || fullHeight <= 0) return null;

    final centerX = box.center.dx;
    final centerY = box.center.dy;

    final mapX = (centerX / fullWidth * map.width).round();
    final mapY = (centerY / fullHeight * map.height).round();

    const radius = 1;
    final samples = <double>[];

    for (int dy = -radius; dy <= radius; dy++) {
      for (int dx = -radius; dx <= radius; dx++) {
        final value = map.valueAt(mapX + dx, mapY + dy);
        if (value.isFinite && value > 0) samples.add(value);
      }
    }

    if (samples.isEmpty) return null;

    samples.sort();
    final middle = samples.length ~/ 2;
    if (samples.length.isOdd) return samples[middle];
    return (samples[middle - 1] + samples[middle]) / 2.0;
  }

  /// تحويل البكسل إلى Float32List مسطّح بصيغة NCHW.
  ///
  /// الفرض الحالي: NCHW + قسمة على 255. يجب تأكيد ذلك فعلياً بعد
  /// إضافة الموديل (راجع DEVELOPMENT_NOTES.md للتفاصيل).
  Float32List _bytesToInputTensor(Uint8List rgbBytes, int size) {
    final input = Float32List(3 * size * size);

    for (int channel = 0; channel < 3; channel++) {
      for (int y = 0; y < size; y++) {
        for (int x = 0; x < size; x++) {
          final srcIndex = (y * size + x) * 3 + channel;
          final dstIndex = channel * size * size + y * size + x;
          input[dstIndex] = rgbBytes[srcIndex] / 255.0;
        }
      }
    }

    return input;
  }

  /// استخراج الأبعاد المكانية من شكل المخرج (يدعم عدة تنسيقات).
  _SpatialDimensions? _findSpatialDimensions(List<int> shape) {
    if (shape.length == 4) {
      if (shape[1] == 1) return _SpatialDimensions(width: shape[3], height: shape[2]);
      if (shape[3] == 1) return _SpatialDimensions(width: shape[2], height: shape[1]);
      return _SpatialDimensions(width: shape[3], height: shape[2]);
    }
    if (shape.length == 3 && shape[0] == 1) {
      return _SpatialDimensions(width: shape[2], height: shape[1]);
    }
    if (shape.length == 2) {
      return _SpatialDimensions(width: shape[1], height: shape[0]);
    }
    return null;
  }

  /// تسطيح المخرجات (نسخ بسيط).
  List<double> _flatten(dynamic value) {
    final result = <double>[];
    void visit(dynamic item) {
      if (item is List) {
        for (final child in item) visit(child);
      } else if (item is num) {
        result.add(item.toDouble());
      }
    }
    visit(value);
    return result;
  }

  void dispose() {
    _isolateInterpreter?.close();
    _interpreter?.close();
    _isolateInterpreter = null;
    _interpreter = null;
  }
}

class _SpatialDimensions {
  final int width;
  final int height;
  const _SpatialDimensions({required this.width, required this.height});
}