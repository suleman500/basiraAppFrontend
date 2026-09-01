import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../../core/constants.dart';
import '../models/detected_object.dart';
import 'frame_converter.dart';

/// بيانات فك تشفير YOLOX.
/// للتفاصيل الكاملة راجع DETECTOR_DEVELOPMENT_NOTES.md.
class YoloxDecodeJob {
  final Float32List values;
  final int dimA;
  final int dimB;
  final List<String> labels;
  final int inputSize;
  final int originalWidth;
  final int originalHeight;
  final double confidenceThreshold;
  final double iouThreshold;
  final bool manualGridDecodeRequired;
  final List<int> yoloxStrides;

  const YoloxDecodeJob({
    required this.values,
    required this.dimA,
    required this.dimB,
    required this.labels,
    required this.inputSize,
    required this.originalWidth,
    required this.originalHeight,
    required this.confidenceThreshold,
    required this.iouThreshold,
    required this.manualGridDecodeRequired,
    required this.yoloxStrides,
  });
}

/// فك تشفير مخرجات YOLOX.
/// للتفاصيل الكاملة راجع DETECTOR_DEVELOPMENT_NOTES.md.
List<DetectedObject> decodeYoloxDetections(YoloxDecodeJob job) {
  final values = job.values;
  final numberOfBoxes = job.dimB > job.dimA ? job.dimB : job.dimA;
  final attributesFirst = job.dimA < job.dimB;
  final attributes = attributesFirst ? job.dimA : job.dimB;
  final numberOfClasses = attributes - 5;

  double at(int box, int attr) {
    if (attributesFirst) {
      return values[attr * numberOfBoxes + box];
    }
    return values[box * attributes + attr];
  }

  double sigmoidIfNeeded(double value) {
    if (value >= 0.0 && value <= 1.0) return value;
    return 1.0 / (1.0 + math.exp(-value));
  }

  /// فك تشفير الشبكة (Grid Decode) – خاص بـ YOLOX.
  Rect decodeRawGrid({
    required int boxIndex,
    required double cx,
    required double cy,
    required double w,
    required double h,
  }) {
    int remaining = boxIndex;
    for (final stride in job.yoloxStrides) {
      final gridSize = job.inputSize ~/ stride;
      final cellsInLevel = gridSize * gridSize;
      if (remaining < cellsInLevel) {
        final gridX = remaining % gridSize;
        final gridY = remaining ~/ gridSize;
        final decodedCx = (cx + gridX) * stride;
        final decodedCy = (cy + gridY) * stride;
        final decodedW = math.exp(w) * stride;
        final decodedH = math.exp(h) * stride;
        return Rect.fromLTRB(
          decodedCx - decodedW / 2,
          decodedCy - decodedH / 2,
          decodedCx + decodedW / 2,
          decodedCy + decodedH / 2,
        );
      }
      remaining -= cellsInLevel;
    }
    return Rect.zero;
  }

  final results = <DetectedObject>[];

  for (int i = 0; i < numberOfBoxes; i++) {
    final objectness = sigmoidIfNeeded(at(i, 4));
    if (objectness < job.confidenceThreshold) continue;

    double bestClassScore = 0.0;
    int bestClassId = -1;
    for (int c = 0; c < numberOfClasses; c++) {
      final score = sigmoidIfNeeded(at(i, 5 + c));
      if (score > bestClassScore) {
        bestClassScore = score;
        bestClassId = c;
      }
    }

    final confidence = objectness * bestClassScore;
    if (confidence < job.confidenceThreshold) continue;
    if (bestClassId < 0 || bestClassId >= job.labels.length) continue;

    final cx = at(i, 0);
    final cy = at(i, 1);
    final w = at(i, 2);
    final h = at(i, 3);

    double left, top, right, bottom;
    if (job.manualGridDecodeRequired) {
      final decoded = decodeRawGrid(
        boxIndex: i,
        cx: cx,
        cy: cy,
        w: w,
        h: h,
      );
      left = decoded.left;
      top = decoded.top;
      right = decoded.right;
      bottom = decoded.bottom;
    } else {
      left = cx - w / 2;
      top = cy - h / 2;
      right = cx + w / 2;
      bottom = cy + h / 2;
    }

    final scaleX = job.originalWidth / job.inputSize;
    final scaleY = job.originalHeight / job.inputSize;

    final box = Rect.fromLTRB(
      (left * scaleX).clamp(0.0, job.originalWidth.toDouble()),
      (top * scaleY).clamp(0.0, job.originalHeight.toDouble()),
      (right * scaleX).clamp(0.0, job.originalWidth.toDouble()),
      (bottom * scaleY).clamp(0.0, job.originalHeight.toDouble()),
    );

    if (box.width <= 1 || box.height <= 1) continue;

    results.add(
      DetectedObject(
        label: job.labels[bestClassId],
        confidence: confidence.clamp(0.0, 1.0),
        box: box,
        distance: 0.0,
      ),
    );
  }

  return _nonMaxSuppressionTopLevel(results, job.iouThreshold);
}

double _iouTopLevel(Rect a, Rect b) {
  final intersection = a.intersect(b);
  if (intersection.width <= 0 || intersection.height <= 0) return 0.0;
  final intersectionArea = intersection.width * intersection.height;
  final unionArea = a.width * a.height + b.width * b.height - intersectionArea;
  if (unionArea <= 0) return 0.0;
  return intersectionArea / unionArea;
}

/// NMS على مرحلتين.
/// للتفاصيل راجع DETECTOR_DEVELOPMENT_NOTES.md.
List<DetectedObject> _nonMaxSuppressionTopLevel(
    List<DetectedObject> boxes,
    double iouThreshold,
    ) {
  final sorted = [...boxes]..sort((a, b) => b.confidence.compareTo(a.confidence));
  final selected = <DetectedObject>[];

  while (sorted.isNotEmpty) {
    final current = sorted.removeAt(0);
    selected.add(current);
    sorted.removeWhere(
          (other) =>
      other.label == current.label &&
          _iouTopLevel(current.box, other.box) > iouThreshold,
    );
  }

  const crossLabelIouThreshold = 0.75;
  final bySizeDesc = [...selected]..sort((a, b) => b.confidence.compareTo(a.confidence));
  final finalSelected = <DetectedObject>[];

  for (final candidate in bySizeDesc) {
    final overlapsExisting = finalSelected.any(
          (kept) => _iouTopLevel(kept.box, candidate.box) > crossLabelIouThreshold,
    );
    if (!overlapsExisting) {
      finalSelected.add(candidate);
    }
  }

  return finalSelected;
}

/// خدمة كشف الأشياء باستخدام YOLOX-Tiny.
/// للتفاصيل الكاملة راجع DETECTOR_DEVELOPMENT_NOTES.md.
class DetectorService {
  Interpreter? _interpreter;
  List<String> _labels = [];
  List<int>? _inputShape;
  List<int>? _outputShape;

  static const bool _manualGridDecodeRequired = true;

  bool get isReady => _interpreter != null && _labels.isNotEmpty;

  Future<void> load() async {
    if (isReady) return;

    final options = InterpreterOptions()..threads = 4;
    try {
      options.addDelegate(XNNPackDelegate());
      debugPrint('YOLOX: XNNPack enabled');
    } catch (e) {
      debugPrint('YOLOX: XNNPack failed, using CPU: $e');
    }

    _interpreter = await Interpreter.fromAsset(
      AppConstants.detectionModelPath,
      options: options,
    );

    _inputShape = _interpreter!.getInputTensor(0).shape;
    _outputShape = _interpreter!.getOutputTensor(0).shape;

    final labelsRaw = await rootBundle.loadString(AppConstants.labelsPath);
    _labels = labelsRaw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    debugPrint('Detection input shape: $_inputShape');
    debugPrint('Detection output shape: $_outputShape');
  }

  /// تشغيل الكشف على إطار معين.
  Future<List<DetectedObject>> detect(
      ConvertedFrame frame, {
        required int fullWidth,
        required int fullHeight,
      }) async {
    if (!isReady) return [];

    final sw = Stopwatch()..start();

    final flatInput = _bytesToInputTensor(frame.rgbBytes, frame.size);
    final buildInputMs = sw.elapsedMilliseconds;

    final input = flatInput.reshape(_inputShape!);
    final reshapeInputMs = sw.elapsedMilliseconds - buildInputMs;

    final totalOutputElements = _outputShape!.reduce((a, b) => a * b);
    final outputBuffer = Float32List(totalOutputElements);
    final output = outputBuffer.reshape(_outputShape!);
    final reshapeOutputMs = sw.elapsedMilliseconds - buildInputMs - reshapeInputMs;

    // استدلال مباشر (أسرع إعداد تم اختباره).
    // التفاصيل في DETECTOR_DEVELOPMENT_NOTES.md.
    _interpreter!.run(input, output);

    final inferenceMs = sw.elapsedMilliseconds -
        buildInputMs -
        reshapeInputMs -
        reshapeOutputMs;

    final flatOutput = Float32List.fromList(_flatten(output));

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
      manualGridDecodeRequired: _manualGridDecodeRequired,
      yoloxStrides: AppConstants.yoloxStrides,
    );

    final result = decodeYoloxDetections(job);
    final decodeMs = sw.elapsedMilliseconds -
        buildInputMs -
        reshapeInputMs -
        reshapeOutputMs -
        inferenceMs;

    debugPrint(
      '⏱️ detect(): buildInput=${buildInputMs}ms, reshapeInput=${reshapeInputMs}ms, '
          'reshapeOutput=${reshapeOutputMs}ms, inference=${inferenceMs}ms, '
          'decode+NMS=${decodeMs}ms',
    );

    return result;
  }

  /// تحويل البكسل إلى Float32List (NHWC).
  /// ⚠️ لا نقسم على 255 – YOLOX يتوقّع قيماً خام (0..255).
  Float32List _bytesToInputTensor(Uint8List rgbBytes, int size) {
    final input = Float32List(size * size * 3);
    for (int i = 0; i < input.length; i++) {
      input[i] = rgbBytes[i].toDouble();
    }
    return input;
  }

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
    _interpreter?.close();
    _interpreter = null;
  }
}