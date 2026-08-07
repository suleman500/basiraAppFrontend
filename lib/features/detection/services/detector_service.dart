import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tflite_flutter/tflite_flutter.dart';

import '../../../core/constants.dart';
import '../models/detected_object.dart';
import 'frame_converter.dart';

/// يحمّل موديل YOLO بصيغة TFLite ويشغّله محليًا على معالج الهاتف —
/// لا يوجد أي اتصال شبكة أو خادم هنا إطلاقًا.
///
/// ملاحظة مهمة: تنسيق مخرجات YOLO المصدَّر يختلف قليلاً حسب إصدار
/// ultralytics وطريقة التصدير. الكود هنا مبني على الشكل الشائع
/// [1, 4+numClasses, numAnchors] (YOLOv8/11)، بمدخل NCHW [1,3,size,size]
/// وإحداثيات مربعات مُطبَّعة بين 0 و1 — تأكدنا من الشكلين فعليًا أثناء
/// التطوير عبر فحص تنسورات الموديل مباشرة.
class DetectorService {
  Interpreter? _interpreter;
  IsolateInterpreter? _isolateInterpreter;
  List<String> _labels = [];
  bool get isReady => _isolateInterpreter != null && _labels.isNotEmpty;

  int _numClasses = 0;

  /// تحميل الموديل وملف الأسماء من assets. تُستدعى مرة وحدة عند بدء التطبيق.
  Future<void> load() async {
    _interpreter = await Interpreter.fromAsset(AppConstants.modelPath);

    // نلف الـ Interpreter بـ IsolateInterpreter حتى يشتغل الاستدلال
    // (وهو عملية ثقيلة) بخيط منفصل عن واجهة المستخدم، فما تتجمد
    // معاينة الكاميرا أثناء التحليل.
    _isolateInterpreter =
    await IsolateInterpreter.create(address: _interpreter!.address);

    final labelsRaw = await rootBundle.loadString(AppConstants.labelsPath);
    _labels = labelsRaw
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    final outputShape = _interpreter!.getOutputTensor(0).shape;
    _numClasses = outputShape[1] - 4;
  }

  /// يشغّل الاستدلال على إطار مُحوَّل مسبقًا (جاهز بالحجم والصيغة
  /// الصحيحة، أُنتِج بخيط منفصل عبر frame_converter.dart) ويرجّع قائمة
  /// الأجسام المكتشفة بعد تطبيق عتبة الثقة و NMS.
  ///
  /// fullWidth/fullHeight هما أبعاد إطار الكاميرا الحقيقي (بعد تصحيح
  /// الدوران، قبل أي تصغير) — نحتاجهم فقط لحساب موضع المربعات النهائي
  /// بمقياس صحيح، دون الحاجة لبناء صورة كاملة الحجم فعليًا.
  Future<List<DetectedObject>> detect(
      ConvertedFrame frame, {
        required int fullWidth,
        required int fullHeight,
      }) async {
    if (!isReady) return [];

    final input = _bytesToInputTensor(frame.rgbBytes, frame.size);

    final outputShape = _interpreter!.getOutputTensor(0).shape;
    final output = List.generate(
      outputShape[0],
          (_) => List.generate(
        outputShape[1],
            (_) => List.filled(outputShape[2], 0.0),
      ),
    );

    await _isolateInterpreter!.run(input, output);
    print('📦 عدد المخرجات: ${output.length}');
    if (output.length > 1) {
      print('📦 شكل المخرج الثاني (العمق): ${output[1].length} x ${output[1][0].length}');
    }

    final rawDetections = _decodeOutput(
      output[0],
      inputSize: frame.size,
      originalWidth: fullWidth,
      originalHeight: fullHeight,
    );

    return _nonMaxSuppression(rawDetections);
  }

  /// يبني مصفوفة الإدخال بترتيب NCHW: [1, 3, size, size] مباشرة من
  /// مصفوفة بايتات RGB مسطّحة (بدل الوصول بكسل-بكسل عبر img.getPixel،
  /// وهو أبطأ بكثير بسبب تخصيص كائن Pixel بكل استدعاء).
  List _bytesToInputTensor(Uint8List rgbBytes, int size) {
    return [
      List.generate(
        3,
            (c) => List.generate(
          size,
              (y) => List.generate(size, (x) {
            final idx = (y * size + x) * 3 + c;
            return rgbBytes[idx] / 255.0;
          }),
        ),
      ),
    ];
  }
  /// يفكّ تشفير مخرجات الموديل الخام إلى قائمة أجسام مكتشفة.
  /// هذه النسخة مخصصة لـ YOLO26n-depth بصيغة [N, 300, 6]
  /// حيث كل صف: [x1, y1, x2, y2, confidence, classId]
  List<DetectedObject> _decodeOutput(
      List<List<double>> output, {
        required int inputSize,
        required int originalWidth,
        required int originalHeight,
      }) {
    final results = <DetectedObject>[];
    // في YOLO26، output هي قائمة من المربعات (عددها 300)
    // وليس output[0] كما في YOLO11
    final numDetections = output.length; // عدد المربعات (300)
    final scaleX = originalWidth / inputSize;
    final scaleY = originalHeight / inputSize;

    for (int i = 0; i < numDetections; i++) {
      final row = output[i]; // كل صف هو [x1, y1, x2, y2, conf, classId]

      // استخراج الإحداثيات المطبعة (normalized)
      final x1 = row[0] * scaleX;
      final y1 = row[1] * scaleY;
      final x2 = row[2] * scaleX;
      final y2 = row[3] * scaleY;
      final confidence = row[4];
      final classId = row[5].toInt();

      // التحقق من الثقة والفئة
      if (confidence < AppConstants.confidenceThreshold ||
          classId < 0 ||
          classId >= _labels.length) {
        continue;
      }

      results.add(DetectedObject(
        label: _labels[classId],
        confidence: confidence,
        box: Rect.fromLTRB(x1, y1, x2, y2),
        distance: 0.0, // سيتم حسابها لاحقاً
      ));
    }
    return results;
  }

  /// خوارزمية Non-Max Suppression: تزيل المربعات المكرّرة/المتداخلة
  /// لنفس الجسم، وتبقي المربع الأعلى ثقة فقط.
  List<DetectedObject> _nonMaxSuppression(List<DetectedObject> boxes) {
    final sorted = [...boxes]
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
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
    if (intersection.width <= 0 || intersection.height <= 0) return 0;
    final intersectionArea = intersection.width * intersection.height;
    final unionArea =
        a.width * a.height + b.width * b.height - intersectionArea;
    return unionArea <= 0 ? 0 : intersectionArea / unionArea;
  }

  void dispose() {
    _isolateInterpreter?.close();
    _interpreter?.close();
  }
}