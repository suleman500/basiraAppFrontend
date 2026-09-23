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

/// حالة انفتاح الممر بمنطقة معيّنة (يسار/وسط/يمين).
enum PathOpenness { open, obstructed, unknown }

/// نتيجة تحليل الممر أمام المستخدم — ثلاث مناطق (يسار، وسط، يمين).
class FreeSpaceResult {
  final PathOpenness left;
  final PathOpenness center;
  final PathOpenness right;

  const FreeSpaceResult({
    required this.left,
    required this.center,
    required this.right,
  });

  /// هل فيه جهة بديلة مفتوحة (يسار أو يمين) لو الوسط مسدود؟
  bool get hasOpenAlternative =>
      left == PathOpenness.open || right == PathOpenness.open;
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

    // ✅ نتائج التشخيص الفعلي (مؤكَّدة من تشغيل حقيقي على الجهاز):
    // shape: [1, 256, 256, 3] → NHWC (كود _bytesToInputTensor وpredict()
    // صُحِّحا بناءً على هذا). type: float32، quantization scale=0/
    // zeroPoint=0 → بدون quantization، تطبيع عادي فقط. المتبقي غير
    // مؤكَّد 100%: مدى التطبيع الدقيق (راجع تعليق _bytesToInputTensor).
    debugPrint('Depth input shape: ${_interpreter!.getInputTensor(0).shape}');
    debugPrint('Depth input type: ${_interpreter!.getInputTensor(0).type}');
    debugPrint(
        'Depth input quantization params: ${_interpreter!.getInputTensor(0).params}');
    debugPrint('Depth output shape: ${_interpreter!.getOutputTensor(0).shape}');
    debugPrint('Depth output type: ${_interpreter!.getOutputTensor(0).type}');
  }

  /// تشغيل موديل العمق على إطار واحد.
  Future<DepthMap?> predict(ConvertedFrame frame) async {
    if (!isReady) return null;

    // ⚠️ مؤكَّد فعليًا (راجع تشخيص load()): الموديل NHWC [1, H, W, 3]،
    // مو NCHW. صُحِّح هون بعد تشغيل حقيقي على الجهاز.
    final flatInput = _bytesToInputTensor(frame.rgbBytes);
    final input = flatInput.reshape([1, frame.size, frame.size, 3]);

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

  // ⚠️⚠️⚠️ PLACEHOLDER — لسا ما اتعايرت على جهازك الحقيقي! هاي 3 نقاط
  // معايرة مفترَضة (قيمة raw عمق مقابل عدد خطوات معروف)، أرقام تخمينية
  // بس عشان الكود يشتغل بمنطق سليم مؤقتًا. استبدلها بالثلاث قيم الحقيقية
  // اللي تطلع من تجربتك (حط جسم على بعد خطوة، 3 خطوات، 6 خطوات، اضغط
  // "ما المسافة؟"، وسجّل قيمة distance الخام من الـlogs لكل حالة).
  //
  // القيم لازم تكون بترتيب تنازلي لو depthHigherValueMeansCloser=true
  // (قيمة أعلى = أقرب)، يعني [قيمة خطوة وحدة (أعلى)، قيمة 3 خطوات،
  // قيمة 6 خطوات (أوطى)].
  static const List<double> _calibrationRawValues = [0.85, 0.55, 0.30];
  static const List<double> _calibrationSteps = [1, 3, 6];

  /// يحوّل قيمة عمق خام (زي الراجعة من [distanceAt]) لعدد خطوات
  /// تقريبي، عبر استيفاء خطي (Linear Interpolation) بين نقاط المعايرة
  /// أعلاه. **تقريب استرشادي، مو قياس دقيق** — مخرجات MiDaS عمق نسبي
  /// بلا وحدة قياس حقيقية، فهذا أفضل تقريب ممكن بدون موديل متري
  /// (زي ZoeDepth اللي حكينا عنه كخيار مستقبلي).
  num estimateSteps(double rawValue) {
    final values = AppConstants.depthHigherValueMeansCloser
        ? _calibrationRawValues
        : _calibrationRawValues.reversed.toList();
    final steps = AppConstants.depthHigherValueMeansCloser
        ? _calibrationSteps
        : _calibrationSteps.reversed.toList();

    // أقرب من أقرب نقطة معايرة — نفترضها بنفس أقل عدد خطوات (مش أقل
    // من هيك منطقيًا لمشروعنا).
    if ((AppConstants.depthHigherValueMeansCloser && rawValue >= values.first) ||
        (!AppConstants.depthHigherValueMeansCloser && rawValue <= values.first)) {
      return steps.first;
    }

    for (int i = 0; i < values.length - 1; i++) {
      final v1 = values[i];
      final v2 = values[i + 1];
      final s1 = steps[i];
      final s2 = steps[i + 1];

      final inRange = AppConstants.depthHigherValueMeansCloser
          ? (rawValue <= v1 && rawValue >= v2)
          : (rawValue >= v1 && rawValue <= v2);

      if (inRange) {
        final t = (rawValue - v1) / (v2 - v1);
        final interpolated = s1 + t * (s2 - s1);
        return interpolated.round();
      }
    }

    // أبعد من أبعد نقطة معايرة — نمدّد نفس الميل الأخير بدل ما نرجع
    // رقم ثابت (أدق من التسطيح عند أبعد نقطة).
    final v1 = values[values.length - 2];
    final v2 = values.last;
    final s1 = steps[steps.length - 2];
    final s2 = steps.last;
    final t = (rawValue - v1) / (v2 - v1);
    final extrapolated = s1 + t * (s2 - s1);
    return extrapolated.round().clamp(steps.last, 999);
  }

  /// يفحص هل الكاميرا **مغطاة فعليًا** (إصبع، غطاء عدسة...) قبل ما
  /// نثق بأي نتيجة عمق. الفكرة: صورة حقيقية لمشهد داخلي (حتى لو حائط
  /// فاضي) دايمًا فيها تمايز إضاءة/نسيج بسيط، بينما عدسة مغطاة بتنتج
  /// صورة **شبه موحّدة تمامًا** (تباين قريب من الصفر). هذا الفحص
  /// مستقل كليًا عن موديل العمق نفسه — يشتغل مباشرة على بايتات
  /// الصورة الخام (rgb)، وبالتالي رخيص جدًا (حلقة وحدة على البايتات).
  ///
  /// ⚠️ القيمة الافتراضية (`varianceThreshold: 150`) تخمين أولي معقول
  /// (مبني على مبدأ الفكرة، مو رقم مقاس فعليًا على جهازك) — لازم
  /// معايرة: جرّب تغطي الكاميرا فعليًا وشوف قيمة التباين اللي تطبع،
  /// وقارنها بمشهد عادي مكشوف.
  bool isFrameLikelyBlocked(
      Uint8List rgbBytes, {
        double varianceThreshold = 150,
      }) {
    if (rgbBytes.isEmpty) return true;

    // نحوّل لدرجة رمادية تقريبية (متوسط القنوات الثلاث) بدل معالجة كل
    // قناة لحالها — كافي لفحص التباين العام، وأسرع.
    final sampleStep = (rgbBytes.length ~/ 3 ~/ 2000).clamp(1, 50);
    final samples = <double>[];

    for (int i = 0; i + 2 < rgbBytes.length; i += 3 * sampleStep) {
      final gray = (rgbBytes[i] + rgbBytes[i + 1] + rgbBytes[i + 2]) / 3.0;
      samples.add(gray);
    }

    if (samples.isEmpty) return true;

    final mean = samples.reduce((a, b) => a + b) / samples.length;
    final variance =
        samples.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
            samples.length;

    debugPrint('🔍 Camera blocked check: variance=$variance');

    return variance < varianceThreshold;
  }

  /// يحلل منطقة الممر أمام المستخدم مباشرة (الجزء السفلي-الأوسط من
  /// الصورة، مقسوم لثلاث مناطق: يسار/وسط/يمين) — بغض النظر عن وجود
  /// أي جسم مكتشَف من YOLO. هذا بالضبط الفرق عن [distanceAt]: هونيك
  /// كنا محتاجين صندوق كشف جاهز (جسم معروف)، هون بنحلل الأرقام الخام
  /// لمنطقة كاملة، فبيلتقط عوائق ما إلها صندوق كشف إطلاقًا (حيطان،
  /// أعمدة، درج، طاولة قريبة لا يشوفها YOLO لأي سبب).
  ///
  /// ⚠️ صفر تكلفة إضافية على الموديل — بتاخذ [DepthMap] جاهزة أصلًا
  /// من نتيجة [predict]، وبس تعالج أرقام موجودة.
  ///
  /// ⚠️ **مبدأ الأمان**: لازم تستدعي [isFrameLikelyBlocked] أول
  /// وتتأكد إنها false قبل ما تنادي هالدالة — لو المشهد مسطّح بالكامل
  /// (ما في تمايز عمق) **وتأكدنا الكاميرا مو مغطاة**، هذا دليل قوي
  /// على سطح قريب جدًا يملأ الرؤية (حائط)، فالدالة ترجع `obstructed`
  /// **مو** `unknown` بهالحالة — تحيّز مقصود نحو الحذر ("قول ما في
  /// مساحة" أرحم من "قول فاضي غلط").
  FreeSpaceResult analyzeFreeSpace(
      DepthMap map, {
        double roiTopFraction = 0.55,
        double roiBottomFraction = 0.95,
        double obstructedPercentile = 0.7,
      }) {
    final allValues = map.values.where((v) => v.isFinite && v > 0).toList();
    if (allValues.isEmpty) {
      return const FreeSpaceResult(
        left: PathOpenness.obstructed,
        center: PathOpenness.obstructed,
        right: PathOpenness.obstructed,
      );
    }

    allValues.sort();
    final minValue = allValues.first;
    final maxValue = allValues.last;

    // ⚠️ مشهد مسطّح بالكامل (صفر تقريبًا تمايز) — بافتراض إنه اتأكد
    // مسبقًا إن الكاميرا مو مغطاة (مسؤولية المستدعي)، هذا سطح قريب
    // يملأ الكادر بالكامل. تحيّز أمان: عائق بكل الاتجاهات، مو "غير
    // معروف".
    if ((maxValue - minValue).abs() < 1e-6) {
      return const FreeSpaceResult(
        left: PathOpenness.obstructed,
        center: PathOpenness.obstructed,
        right: PathOpenness.obstructed,
      );
    }

    final topY = (map.height * roiTopFraction).round().clamp(0, map.height);
    final bottomY =
    (map.height * roiBottomFraction).round().clamp(0, map.height);

    final leftEnd = (map.width * 0.33).round();
    final centerEnd = (map.width * 0.67).round();

    PathOpenness classifyRegion(int xStart, int xEnd) {
      final samples = <double>[];
      for (int y = topY; y < bottomY; y++) {
        for (int x = xStart; x < xEnd; x++) {
          final value = map.valueAt(x, y);
          if (value.isFinite && value > 0) samples.add(value);
        }
      }

      // ⚠️ تحيّز أمان: عيّنات فاضية بمنطقة معيّنة (نادر، بس ممكن يصير
      // بحواف الإطار) = عائق افتراضي، مو "غير معروف".
      if (samples.isEmpty) return PathOpenness.obstructed;

      samples.sort();
      final median = samples[samples.length ~/ 2];

      var normalized = (median - minValue) / (maxValue - minValue);
      if (!AppConstants.depthHigherValueMeansCloser) {
        normalized = 1.0 - normalized;
      }

      return normalized >= obstructedPercentile
          ? PathOpenness.obstructed
          : PathOpenness.open;
    }

    return FreeSpaceResult(
      left: classifyRegion(0, leftEnd),
      center: classifyRegion(leftEnd, centerEnd),
      right: classifyRegion(centerEnd, map.width),
    );
  }

  /// تحويل البكسل إلى Float32List مسطّح بصيغة NHWC.
  ///
  /// ✅ مؤكَّد فعليًا (تشخيص load()): الموديل NHWC [1, H, W, 3]، float32،
  /// بدون quantization (scale=0, zeroPoint=0). بما إنه [rgbBytes] أصلًا
  /// مخزَّنة متداخلة (R,G,B لكل بكسل بالتتابع، نفس ترتيب NHWC بالضبط)،
  /// التحويل صار نسخ مباشر بدون أي إعادة ترتيب قنوات — أبسط بكثير من
  /// نسخة NCHW القديمة.
  ///
  /// ⚠️ لسا غير مؤكَّد 100%: **مدى التطبيع الدقيق**. هون افترضنا قسمة
  /// على 255 (مدى [0,1])، بس موديلات MiDaS الأصلية أحيانًا تتوقع مدى
  /// [-1,1] أو تطبيع ImageNet كامل (mean/std لكل قناة). لو نتائج
  /// المسافة/الممر طلعت غير منطقية بالاختبار الفعلي (كل شي "قريب جدًا"
  /// أو كل شي "بعيد جدًا" بدون تمايز)، هاي أول نقطة نراجعها.
  Float32List _bytesToInputTensor(Uint8List rgbBytes) {
    final input = Float32List(rgbBytes.length);
    for (int i = 0; i < rgbBytes.length; i++) {
      input[i] = rgbBytes[i] / 255.0;
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