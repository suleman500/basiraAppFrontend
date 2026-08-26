import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../../core/constants.dart';
import '../models/detected_object.dart';
import 'frame_converter.dart';

/// خدمة كشف الأشياء باستخدام موديل YOLOX-Tiny (Apache 2.0).
///
/// ===========================================================================
/// طريقة الإضافة (مؤكَّدة فعليًا من تحويل حقيقي عبر onnx2tf، وليست افتراضًا):
/// 1) صدِّر YOLOX-Tiny: PyTorch (.pth) → ONNX (export_onnx.py ببيئة
///    Python 3.10 + torch 1.13.1) → TFLite (onnx2tf).
/// 2) ضع الملف الناتج باسم `yolox_tiny.tflite` داخل assets/models/
///    (أو غيّر AppConstants.detectionModelPath لو استخدمت اسمًا آخر).
/// 3) labels.txt الحالي (80 فئة COCO) يطابق مخرجات الموديل تمامًا —
///    لا حاجة لتعديله.
/// لا حاجة لأي تعديل إضافي على هذا الملف أو غيره.
/// ===========================================================================
///
/// شكل الموديل المؤكَّد (عبر فحص فعلي بـ Interpreter.get_input/output_details):
/// - المُدخل:  [1, 416, 416, 3]  float32  → NHWC، بقيم بكسل خام 0..255
///   (⚠️ بدون قسمة على 255 — YOLOX استثناء عن باقي الموديلات، راجع
///   تعليق _bytesToInputTensor).
/// - المُخرج:  [1, 85, 3549]     float32  → [1, 5+80 فئة, عدد الصناديق].
///
/// يعني بخلاف موديلات YOLOv8/YOLO11/YOLO26 (لا يوجد objectness منفصل،
/// فقط درجات فئات)، مخرجات YOLOX لكل صندوق هي:
/// [cx, cy, w, h, objectness, classScore0, classScore1, ...]
/// والثقة النهائية = objectness × أعلى classScore (وليس أحدهما فقط).
///
/// ⚠️ مؤكَّد فعليًا من اختبار حقيقي على الجهاز: 3549 = 52×52 (stride 8)
/// + 26×26 (stride 16) + 13×13 (stride 32) بالضبط — يعني الموديل
/// **يطبّق sigmoid على الثقة/الفئة فقط داخليًا، لكن لا يطبّق فك تشفير
/// الشبكة (grid decode) على إحداثيات الصندوق نفسها**. القيم cx/cy/w/h
/// الواصلة خام (نسبية لكل خلية شبكة صغيرة)، ولازم فك تشفيرها يدويًا
/// عبر الشبكة والـ stride (_decodeRawGrid) قبل استخدامها — وهذا مفعَّل
/// فعليًا بهذا الملف (_manualGridDecodeRequired = true).
/// الشيء الوحيد غير المدمج بالموديل هو NMS، فهذا الملف يطبّقه يدويًا
/// (_nonMaxSuppression) بعد فك التشفير.
class DetectorService {
  Interpreter? _interpreter;
  IsolateInterpreter? _isolateInterpreter;

  List<String> _labels = [];

  /// ⚠️ مفعَّل الآن (true) بعد تأكيد فعلي من اختبار على الجهاز: الموديل
  /// لا يطبّق فك تشفير الشبكة على الصندوق، فقط sigmoid على الثقة/الفئة.
  /// راجع تعليق الكلاس أعلاه للتفاصيل والدليل الحسابي (3549 = مجموع
  /// خلايا 3 مستويات الشبكة بالضبط).
  static const bool _manualGridDecodeRequired = true;

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

    final detections = _decodeYoloxOutput(
      output,
      outputShape,
      inputSize: frame.size,
      originalWidth: fullWidth,
      originalHeight: fullHeight,
    );

    return _nonMaxSuppression(detections);
  }

  /// يحول RGB إلى NHWC: [1, height, width, 3].
  ///
  /// ⚠️ ملاحظة حرجة خاصة بـ YOLOX (بخلاف كل موديلات الكشف الشائعة
  /// الأخرى مثل YOLOv8/YOLO11): المعالجة المسبقة الرسمية لـ YOLOX
  /// (`preproc()` بمستودعه الرسمي) **لا تقسم قيم البكسل على 255**.
  /// الموديل يتدرّب ويتوقّع قيم بكسل خام بمدى 0..255 مباشرة، مو 0..1.
  /// تغذيته بقيم مطبَّعة (÷255) ينتج مخرجات شبه صفرية بالكامل (بالضبط
  /// العرَض اللي شخّصناه: maxObjectness = 0.000 بكل إطار).
  ///
  /// مؤكَّد فعليًا (وليس افتراضًا) من فحص الموديل المصدَّر عبر onnx2tf:
  /// `Input: [1, 416, 416, 3] float32` — أي NHWC. هذا يطابق تمامًا ترتيب
  /// البايتات اللي يخرجها frame_converter.dart أصلًا (RGB متداخل
  /// pixel-by-pixel عبر img.ChannelOrder.rgb)، فلا حاجة لأي إعادة ترتيب
  /// قنوات — فقط تقسيم البايتات المسطّحة لأبعاد Tensor بدون أي تطبيع.
  List<List<List<List<double>>>> _bytesToInputTensor(
    Uint8List rgbBytes,
    int size,
  ) {
    return [
      List.generate(
        size,
        (y) => List.generate(
          size,
          (x) => List.generate(
            3,
            (channel) {
              final index = (y * size + x) * 3 + channel;
              // بدون قسمة على 255 — YOLOX يتوقّع القيمة الخام كما هي.
              return rgbBytes[index].toDouble();
            },
          ),
        ),
      ),
    ];
  }

  /// يفك مخرجات YOLOX-Tiny.
  ///
  /// مبني على الشكل المؤكَّد [1, 85, 3549] (صفات أولًا، ثم صناديق)، لكن
  /// يبقى مرنًا لو تغيّر ترتيب الأبعاد مستقبلًا (موديل آخر مصدَّر بأداة
  /// مختلفة) عبر فحص أي بُعد أصغر (وهو دومًا عدد الصفات، أصغر بكثير من
  /// عدد الصناديق بأي موديل واقعي).
  List<DetectedObject> _decodeYoloxOutput(
    dynamic output,
    List<int> shape, {
    required int inputSize,
    required int originalWidth,
    required int originalHeight,
  }) {
    final values = _flatten(output);

    if (shape.length != 3 || shape[0] != 1) {
      debugPrint('Unsupported YOLOX output shape: $shape');
      return [];
    }

    final results = <DetectedObject>[];

    final dimA = shape[1];
    final dimB = shape[2];
    final attributesFirst = dimA < dimB; // [1, attrs, N] مثل [1, 85, 3549]

    final attributes = attributesFirst ? dimA : dimB;
    final numberOfBoxes = attributesFirst ? dimB : dimA;
    final numberOfClasses = attributes - 5;

    if (numberOfClasses <= 0 || numberOfClasses != _labels.length) {
      debugPrint(
        'Mismatch: model reports $numberOfClasses classes, '
        'labels.txt has ${_labels.length}.',
      );
    }

    double at(int box, int attr) {
      if (attributesFirst) {
        // shape [1, attrs, N] -> index = attr * N + box
        return values[attr * numberOfBoxes + box];
      }
      // shape [1, N, attrs] -> index = box * attrs + attr
      return values[box * attributes + attr];
    }

    // ---- تشخيص مؤقت: يطبع أعلى ثقة وصلها الموديل بكل استدعاء ----
    // احذف هذا البلوك بعد ما تحل المشكلة.
    double debugMaxConfidence = 0.0;
    double debugMaxObjectness = 0.0;
    // ------------------------------------------------------------

    for (int i = 0; i < numberOfBoxes; i++) {
      final cx = at(i, 0);
      final cy = at(i, 1);
      final w = at(i, 2);
      final h = at(i, 3);
      final objectness = _sigmoidIfNeeded(at(i, 4));

      double bestClassScore = 0.0;
      int bestClassId = -1;

      for (int c = 0; c < numberOfClasses; c++) {
        final score = _sigmoidIfNeeded(at(i, 5 + c));
        if (score > bestClassScore) {
          bestClassScore = score;
          bestClassId = c;
        }
      }

      final confidence = objectness * bestClassScore;

      // ---- تشخيص مؤقت ----
      if (confidence > debugMaxConfidence) debugMaxConfidence = confidence;
      if (objectness > debugMaxObjectness) debugMaxObjectness = objectness;
      // ---------------------

      if (confidence < AppConstants.confidenceThreshold) continue;
      if (bestClassId < 0 || bestClassId >= _labels.length) continue;

      // الموديل يخرج إحداثيات خام نسبية لكل خلية شبكة (غير مصحَّحة) —
      // لازم فك تشفيرها عبر موقع الخلية والـ stride قبل استخدامها.
      double left, top, right, bottom;

      if (_manualGridDecodeRequired) {
        final decoded = _decodeRawGrid(
          boxIndex: i,
          cx: cx,
          cy: cy,
          w: w,
          h: h,
          inputSize: inputSize,
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

      final scaleX = originalWidth / inputSize;
      final scaleY = originalHeight / inputSize;

      final box = Rect.fromLTRB(
        (left * scaleX).clamp(0.0, originalWidth.toDouble()),
        (top * scaleY).clamp(0.0, originalHeight.toDouble()),
        (right * scaleX).clamp(0.0, originalWidth.toDouble()),
        (bottom * scaleY).clamp(0.0, originalHeight.toDouble()),
      );

      if (box.width <= 1 || box.height <= 1) continue;

      results.add(
        DetectedObject(
          label: _labels[bestClassId],
          confidence: confidence.clamp(0.0, 1.0),
          box: box,
          distance: 0.0,
        ),
      );
    }

    // ---- تشخيص مؤقت: احذف هذا السطر بعد ما تحل المشكلة ----
    debugPrint(
      'YOLOX debug -> boxes: $numberOfBoxes, classes: $numberOfClasses, '
      'maxObjectness: ${debugMaxObjectness.toStringAsFixed(3)}, '
      'maxConfidence: ${debugMaxConfidence.toStringAsFixed(3)}, '
      'passedThreshold: ${results.length}',
    );
    // ---------------------------------------------------------

    return results;
  }

  /// فك تشفير يدوي لصناديق YOLOX الخام (grid-relative).
  ///
  /// يعتمد على ترتيب توليد الشبكة القياسي بمكتبة YOLOX: كل مستوى
  /// stride (8 ثم 16 ثم 32) يُولَّد صفًا تلو الآخر (row-major) على كامل
  /// الصورة قبل الانتقال للمستوى التالي. مؤكَّد إن هذا الترتيب صحيح
  /// لأن 52×52 + 26×26 + 13×13 = 3549 يطابق عدد الصناديق بالضبط.
  Rect _decodeRawGrid({
    required int boxIndex,
    required double cx,
    required double cy,
    required double w,
    required double h,
    required int inputSize,
  }) {
    int remaining = boxIndex;

    for (final stride in AppConstants.yoloxStrides) {
      final gridSize = inputSize ~/ stride;
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

    // لم نجد المستوى (شكل غير متوقع) — نرجّع صندوقًا فارغًا بأمان.
    return Rect.zero;
  }

  /// بعض تصديرات TFLite تُخرج القيم بعد sigmoid فعليًا (0..1، وهذا مؤكَّد
  /// حالة موديلنا بوجود 80 عملية Sigmoid داخل الرسم البياني نفسه)،
  /// وبعضها الآخر (لو صدَّرت بأداة مختلفة مستقبلًا) قد يُخرجها خام
  /// (logits) وتحتاج sigmoid يدويًا. هذا الفحص يطبّق sigmoid فقط لو
  /// القيمة خارج المدى [0,1] — آمن للحالتين، ولن يُفعَّل مع موديلنا
  /// الحالي لأن القيم ستصل أصلًا ضمن [0,1].
  double _sigmoidIfNeeded(double value) {
    if (value >= 0.0 && value <= 1.0) return value;
    return 1.0 / (1.0 + math.exp(-value));
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
            _iou(current.box, other.box) > AppConstants.iouThreshold,
      );
    }

    return selected;
  }

  double _iou(Rect a, Rect b) {
    final intersection = a.intersect(b);

    if (intersection.width <= 0 || intersection.height <= 0) {
      return 0.0;
    }

    final intersectionArea = intersection.width * intersection.height;

    final unionArea =
        a.width * a.height + b.width * b.height - intersectionArea;

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