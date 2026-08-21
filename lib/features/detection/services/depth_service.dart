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

    if (index < 0 || index >= values.length) {
      return 0.0;
    }

    return values[index];
  }
}

/// خدمة تشغيل موديل yolo26n-depth.tflite.
class DepthService {
  Interpreter? _interpreter;
  IsolateInterpreter? _isolateInterpreter;

  bool get isReady => _isolateInterpreter != null;

  Future<void> load() async {
    if (isReady) return;

    _interpreter = await Interpreter.fromAsset(
      AppConstants.depthModelPath,
    );

    _isolateInterpreter = await IsolateInterpreter.create(
      address: _interpreter!.address,
    );

    debugPrint(
      'Depth input shape: '
          '${_interpreter!.getInputTensor(0).shape}',
    );

    debugPrint(
      'Depth output shape: '
          '${_interpreter!.getOutputTensor(0).shape}',
    );
  }

  /// يشغّل موديل العمق مرة واحدة على الإطار.
  Future<DepthMap?> predict(
      ConvertedFrame frame,
      ) async {
    if (!isReady) return null;

    final input = _bytesToInputTensor(
      frame.rgbBytes,
      frame.size,
    );

    final outputTensor = _interpreter!.getOutputTensor(0);
    final outputShape = outputTensor.shape;
    final output = _createTensor(outputShape);

    await _isolateInterpreter!.run(input, output);

    final values = _flatten(output);

    final dimensions = _findSpatialDimensions(
      outputShape,
    );

    if (dimensions == null) {
      debugPrint(
        'Unsupported depth output shape: $outputShape',
      );
      return null;
    }

    final expectedLength =
        dimensions.width * dimensions.height;

    if (values.length < expectedLength) {
      debugPrint(
        'Depth output has too few values. '
            'Expected: $expectedLength, '
            'actual: ${values.length}',
      );
      return null;
    }

    return DepthMap(
      values: values.take(expectedLength).toList(),
      width: dimensions.width,
      height: dimensions.height,
    );
  }

  /// يأخذ العمق من منطقة صغيرة حول مركز مربع الجسم.
  ///
  /// fullWidth و fullHeight هما أبعاد صورة الكاميرا الأصلية.
  /// box أيضًا على مقياس الصورة الأصلية.
  double? distanceAt({
    required DepthMap map,
    required Rect box,
    required int fullWidth,
    required int fullHeight,
  }) {
    if (fullWidth <= 0 || fullHeight <= 0) {
      return null;
    }

    final centerX = box.center.dx;
    final centerY = box.center.dy;

    final mapX = (
        centerX / fullWidth * map.width
    ).round();

    final mapY = (
        centerY / fullHeight * map.height
    ).round();

    // نأخذ 3x3 حول المركز لتقليل اهتزاز القراءة.
    final radius = 1;
    final samples = <double>[];

    for (int dy = -radius; dy <= radius; dy++) {
      for (int dx = -radius; dx <= radius; dx++) {
        final value = map.valueAt(
          mapX + dx,
          mapY + dy,
        );

        if (value.isFinite && value > 0) {
          samples.add(value);
        }
      }
    }

    if (samples.isEmpty) {
      return null;
    }

    samples.sort();

    // الوسيط أكثر ثباتًا من أول قيمة أو المتوسط.
    final middle = samples.length ~/ 2;

    if (samples.length.isOdd) {
      return samples[middle];
    }

    return (
        samples[middle - 1] +
            samples[middle]
    ) /
        2.0;
  }

  List<List<List<List<double>>>> _bytesToInputTensor(
      Uint8List rgbBytes,
      int size,
      ) {
    return [
      List.generate(
        3,
            (channel) => List.generate(
          size,
              (y) => List.generate(
            size,
                (x) {
              final index = (y * size + x) * 3 + channel;
              return rgbBytes[index] / 255.0;
            },
          ),
        ),
      ),
    ];
  }

  _SpatialDimensions? _findSpatialDimensions(
      List<int> shape,
      ) {
    if (shape.length == 4) {
      // [1, 1, height, width]
      if (shape[1] == 1) {
        return _SpatialDimensions(
          width: shape[3],
          height: shape[2],
        );
      }

      // [1, height, width, 1]
      if (shape[3] == 1) {
        return _SpatialDimensions(
          width: shape[2],
          height: shape[1],
        );
      }

      // حل احتياطي.
      return _SpatialDimensions(
        width: shape[3],
        height: shape[2],
      );
    }

    // [1, height, width]
    if (shape.length == 3 && shape[0] == 1) {
      return _SpatialDimensions(
        width: shape[2],
        height: shape[1],
      );
    }

    // [height, width]
    if (shape.length == 2) {
      return _SpatialDimensions(
        width: shape[1],
        height: shape[0],
      );
    }

    return null;
  }

  dynamic _createTensor(
      List<int> shape, [
        int index = 0,
      ]) {
    if (index == shape.length - 1) {
      return List<double>.filled(
        shape[index],
        0.0,
      );
    }

    return List.generate(
      shape[index],
          (_) => _createTensor(shape, index + 1),
    );
  }

  List<double> _flatten(dynamic value) {
    final result = <double>[];

    void visit(dynamic item) {
      if (item is List) {
        for (final child in item) {
          visit(child);
        }
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

  const _SpatialDimensions({
    required this.width,
    required this.height,
  });
}