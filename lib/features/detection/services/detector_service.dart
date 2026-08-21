import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../../core/constants.dart';
import '../models/detected_object.dart';
import 'frame_converter.dart';

/// خدمة كشف الأشياء باستخدام model.tflite.
class DetectorService {
  Interpreter? _interpreter;
  IsolateInterpreter? _isolateInterpreter;

  List<String> _labels = [];

  bool get isReady =>
      _isolateInterpreter != null && _labels.isNotEmpty;

  Future<void> load() async {
    if (isReady) return;

    _interpreter = await Interpreter.fromAsset(
      AppConstants.detectionModelPath,
    );

    _isolateInterpreter = await IsolateInterpreter.create(
      address: _interpreter!.address,
    );

    final labelsRaw = await rootBundle.loadString(
      AppConstants.labelsPath,
    );

    _labels = labelsRaw
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    debugPrint(
      'Detection input shape: '
          '${_interpreter!.getInputTensor(0).shape}',
    );

    debugPrint(
      'Detection output shape: '
          '${_interpreter!.getOutputTensor(0).shape}',
    );
  }

  /// يشغّل موديل الكشف على الإطار.
  Future<List<DetectedObject>> detect(
      ConvertedFrame frame, {
        required int fullWidth,
        required int fullHeight,
      }) async {
    if (!isReady) return [];

    final input = _bytesToInputTensor(
      frame.rgbBytes,
      frame.size,
    );

    final outputTensor = _interpreter!.getOutputTensor(0);
    final outputShape = outputTensor.shape;

    final output = _createTensor(outputShape);

    await _isolateInterpreter!.run(input, output);

    final detections = _decodeOutput(
      output,
      outputShape,
      inputSize: frame.size,
      originalWidth: fullWidth,
      originalHeight: fullHeight,
    );

    return _nonMaxSuppression(detections);
  }

  /// يحول RGB إلى NCHW:
  /// [1, 3, height, width]
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

  /// يفك مخرجات نماذج YOLO الشائعة.
  ///
  /// يدعم شكلين:
  ///
  /// [1, 300, 6]
  /// كل صف:
  /// [x1, y1, x2, y2, confidence, classId]
  ///
  /// أو:
  ///
  /// [1, 4 + classes, detections]
  /// وهو الشكل الشائع في YOLOv8 و YOLO11.
  List<DetectedObject> _decodeOutput(
      dynamic output,
      List<int> shape, {
        required int inputSize,
        required int originalWidth,
        required int originalHeight,
      }) {
    final values = _flatten(output);

    if (shape.length != 3 || shape[0] != 1) {
      debugPrint(
        'Unsupported detection output shape: $shape',
      );
      return [];
    }

    final results = <DetectedObject>[];

    // الشكل [1, detections, 6]
    if (shape[2] == 6) {
      final numberOfDetections = shape[1];

      for (int i = 0; i < numberOfDetections; i++) {
        final rowStart = i * 6;

        if (rowStart + 5 >= values.length) {
          break;
        }

        final x1 = values[rowStart];
        final y1 = values[rowStart + 1];
        final x2 = values[rowStart + 2];
        final y2 = values[rowStart + 3];
        final confidence = values[rowStart + 4];
        final classId = values[rowStart + 5].round();

        _addDetectionIfValid(
          results,
          x1: x1,
          y1: y1,
          x2: x2,
          y2: y2,
          confidence: confidence,
          classId: classId,
          inputSize: inputSize,
          originalWidth: originalWidth,
          originalHeight: originalHeight,
          coordinatesAreCenterBased: false,
        );
      }

      return results;
    }

    // الشكل [1, 6, detections]
    if (shape[1] == 6) {
      final numberOfDetections = shape[2];

      for (int i = 0; i < numberOfDetections; i++) {
        final x1 = values[i];
        final y1 = values[numberOfDetections + i];
        final x2 = values[(numberOfDetections * 2) + i];
        final y2 = values[(numberOfDetections * 3) + i];
        final confidence = values[(numberOfDetections * 4) + i];
        final classId =
        values[(numberOfDetections * 5) + i].round();

        _addDetectionIfValid(
          results,
          x1: x1,
          y1: y1,
          x2: x2,
          y2: y2,
          confidence: confidence,
          classId: classId,
          inputSize: inputSize,
          originalWidth: originalWidth,
          originalHeight: originalHeight,
          coordinatesAreCenterBased: false,
        );
      }

      return results;
    }

    // الشكل [1, 4 + classes, detections]
    final attributes = shape[1];
    final numberOfDetections = shape[2];

    if (attributes < 5) {
      debugPrint(
        'Invalid detection attributes count: $attributes',
      );
      return [];
    }

    for (int i = 0; i < numberOfDetections; i++) {
      final cx = values[i];
      final cy = values[numberOfDetections + i];
      final width = values[(numberOfDetections * 2) + i];
      final height = values[(numberOfDetections * 3) + i];

      double bestConfidence = 0.0;
      int bestClassId = -1;

      final numberOfClasses = attributes - 4;

      for (int classIndex = 0;
      classIndex < numberOfClasses;
      classIndex++) {
        final scoreIndex =
            (numberOfDetections * (4 + classIndex)) + i;

        if (scoreIndex >= values.length) continue;

        final score = values[scoreIndex];

        if (score > bestConfidence) {
          bestConfidence = score;
          bestClassId = classIndex;
        }
      }

      _addDetectionIfValid(
        results,
        x1: cx,
        y1: cy,
        x2: width,
        y2: height,
        confidence: bestConfidence,
        classId: bestClassId,
        inputSize: inputSize,
        originalWidth: originalWidth,
        originalHeight: originalHeight,
        coordinatesAreCenterBased: true,
      );
    }

    return results;
  }

  void _addDetectionIfValid(
      List<DetectedObject> results, {
        required double x1,
        required double y1,
        required double x2,
        required double y2,
        required double confidence,
        required int classId,
        required int inputSize,
        required int originalWidth,
        required int originalHeight,
        required bool coordinatesAreCenterBased,
      }) {
    if (confidence < AppConstants.confidenceThreshold) {
      return;
    }

    if (classId < 0 || classId >= _labels.length) {
      return;
    }

    double left;
    double top;
    double right;
    double bottom;

    if (coordinatesAreCenterBased) {
      final centerX = _coordinateToInputPixels(x1, inputSize);
      final centerY = _coordinateToInputPixels(y1, inputSize);
      final boxWidth = _coordinateToInputPixels(x2, inputSize);
      final boxHeight = _coordinateToInputPixels(y2, inputSize);

      left = centerX - boxWidth / 2;
      top = centerY - boxHeight / 2;
      right = centerX + boxWidth / 2;
      bottom = centerY + boxHeight / 2;
    } else {
      left = _coordinateToInputPixels(x1, inputSize);
      top = _coordinateToInputPixels(y1, inputSize);
      right = _coordinateToInputPixels(x2, inputSize);
      bottom = _coordinateToInputPixels(y2, inputSize);
    }

    final scaleX = originalWidth / inputSize;
    final scaleY = originalHeight / inputSize;

    final box = Rect.fromLTRB(
      (left * scaleX).clamp(0.0, originalWidth.toDouble()),
      (top * scaleY).clamp(0.0, originalHeight.toDouble()),
      (right * scaleX).clamp(0.0, originalWidth.toDouble()),
      (bottom * scaleY).clamp(0.0, originalHeight.toDouble()),
    );

    if (box.width <= 1 || box.height <= 1) {
      return;
    }

    results.add(
      DetectedObject(
        label: _labels[classId],
        confidence: confidence.clamp(0.0, 1.0),
        box: box,
        distance: 0.0,
      ),
    );
  }

  /// بعض الموديلات ترجع إحداثيات normalized،
  /// وبعضها يرجع إحداثيات بالبكسل على صورة الإدخال.
  double _coordinateToInputPixels(
      double value,
      int inputSize,
      ) {
    if (value.abs() <= 1.5) {
      return value * inputSize;
    }

    return value;
  }

  List<DetectedObject> _nonMaxSuppression(
      List<DetectedObject> boxes,
      ) {
    final sorted = [...boxes]
      ..sort(
            (a, b) => b.confidence.compareTo(a.confidence),
      );

    final selected = <DetectedObject>[];

    while (sorted.isNotEmpty) {
      final current = sorted.removeAt(0);
      selected.add(current);

      sorted.removeWhere(
            (other) =>
        other.label == current.label &&
            _iou(current.box, other.box) >
                AppConstants.iouThreshold,
      );
    }

    return selected;
  }

  double _iou(Rect a, Rect b) {
    final intersection = a.intersect(b);

    if (intersection.width <= 0 ||
        intersection.height <= 0) {
      return 0.0;
    }

    final intersectionArea =
        intersection.width * intersection.height;

    final unionArea =
        a.width * a.height +
            b.width * b.height -
            intersectionArea;

    if (unionArea <= 0) return 0.0;

    return intersectionArea / unionArea;
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