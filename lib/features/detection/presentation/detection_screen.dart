import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:flutter/scheduler.dart' show Ticker;

import '../../../core/constants.dart';
import '../../voice/data/labels_ar.dart';
import '../../voice/services/voice_announcer.dart';
import '../models/detected_object.dart';
import '../services/depth_service.dart';
import '../services/detector_service.dart';
import '../services/native_detector_service.dart';
import '../services/frame_converter.dart';
import '../services/gyroscope_service.dart';
import 'widgets/bounding_box_painter.dart';
import 'widgets/detection_chips_bar.dart';
import 'dart:math' as math;
import '../services/object_memory_service.dart';
import '../../training/presentation/training_screen.dart';

class DetectionScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const DetectionScreen({
    super.key,
    required this.cameras,
  });

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState
    extends State<DetectionScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _controller;

  DepthMap? _lastDepthMap;

  final ObjectMemoryService memory =
  ObjectMemoryService();
  int _missingDetectionFrames = 0;
  int _processedFrameCounter = 0;
  // 🔀 نقطة التبديل الوحيدة — dynamic هون عمدًا (بدل DetectorService)
  // حتى نقدر نستخدم NativeDetectorService الجديد بدون أي تعديل على
  // detector_service.dart الأصلي. القديم يبقى بالضبط زي ما هو.
  final dynamic _detector = AppConstants.useNativeDetector
      ? NativeDetectorService()
      : DetectorService();
  final DepthService _depth = DepthService();
  final VoiceAnnouncer _voice = VoiceAnnouncer();
  final GyroscopeService _gyro = GyroscopeService();

  /// "الهدف" — آخر نتيجة كشف وصلت من الموديل (يتحدّث بس كل ما يخلص
  /// الموديل إطار جديد، يعني أقصى تقدير كل ~1/15 ثانية).
  List<DetectedObject> _detections = [];

  // ---------------- تحريك سلس للمربعات (نفس تقنية النقطة المضيئة
  // بـ basira_home_screen.dart) ----------------
  // بدل ما ينتظر المربع كل تحديث من الموديل (بطيء نسبيًا، يعطي إحساس
  // "قفزات")، Ticker مستقل يشتغل بمعدل تحديث الشاشة (~60 مرة بالثانية)
  // ويحسب موقع وسيط بين آخر موضع معروض وآخر "هدف" من الموديل باستمرار
  // — فيصير المربع يتحرك بسلاسة بدل ما يقفز، وبسرعة يلحق أي تحديث جديد
  // فور وصوله، بغض النظر عن سرعة الموديل نفسه.
  late final Ticker _boxAnimationTicker;

  /// "المعروض فعليًا" — الموضع المتحرّك بسلاسة نحو _detections. مغلّف
  /// بـ ValueNotifier (زي _glowPosition بالضبط) حتى يعيد رسم صندوق
  /// الرسم بس (CustomPaint)، مو الشاشة كاملة، كل تِك.
  final ValueNotifier<List<DetectedObject>> _animatedDetections =
  ValueNotifier<List<DetectedObject>>([]);

  Duration? _lastAnimationTickElapsed;

  /// عدّاد الإطارات المتتالية اللي ظهر فيها كل جسم (بهويته trackingKey).
  /// يُستخدم فلتر استقرار قبل النطق — يمنع نطق كشوفات وهمية لحظية
  /// ناتجة عن ضبابية حركة الكاميرا السريعة (motion blur)، بدون ما
  /// يأثر على سرعة ظهور المربع البصري نفسه.
  final Map<String, int> _detectionStreak = {};

  /// نص وصف القرب النسبي الحالي لكل جسم (id الجسم -> "قريب جدًا"...).
  /// يُحدَّث فقط بعد طلب قياس مسافة صريح، ويُمسح لما يتغيّر المشهد
  /// (نتوقف أو نبدّل كاميرا) لأنه لا معنى له بدون خريطة عمق حديثة.
  Map<String, String> _proximityLabels = {};

  int _imageWidth = 0;
  int _imageHeight = 0;
  int _cameraIndex = 0;
  int _frameCounter = 0;

  bool _isInitializing = true;
  bool _isRunning = false;
  bool _isProcessingFrame = false;
  String? _error;

  // ---------------- قياس المسافة عند الطلب (On-Demand) ----------------
  // خلافًا للتصميم القديم (تشغيل موديل العمق تلقائيًا كل عدة إطارات)،
  // موديل العمق الآن يعمل فقط لما المستخدم يضغط زر "ما المسافة؟"
  // صراحة. _depthRequested يُرفَع من زر الواجهة، ويُلتقَط ويُنفَّذ داخل
  // _processFrame (لأنه المكان الوحيد اللي عندنا فيه وصول للإطار الخام
  // من الكاميرا)، ثم يرجع false فورًا حتى ما يتكرر كل إطار.
  bool _depthRequested = false;
  bool _isMeasuringDistance = false;

  // ---------------- وضع التوجيه (Navigation Mode) ----------------
  /// اسم الفئة (label بالإنجليزي، زي ما يرجّعه الموديل) اللي المستخدم
  /// يوجّه نحوها حاليًا، أو null لو ما في توجيه شغّال.
  String? _navigationTargetLabel;

  /// هوية الجسم المحدَّد بالضبط (trackingKey = memoryId عادةً، بصمة
  /// بصرية دائمة من object_memory_service). هذا هو المفتاح الحقيقي
  /// اللي يمنع الالتباس لو في أكتر من جسم بنفس التسمية بالمشهد (مثلًا
  /// كرسيّين) — بدون هذا، الكود كان بس يلاحق "أكبر صندوق بنفس
  /// التسمية" كل إطار، فممكن يتقفز بين الكرسيين لو تقاربوا بالحجم.
  String? _navigationTargetId;

  bool get _isNavigating => _navigationTargetLabel != null;

  DateTime? _lastNavigationAnnounce;
  DateTime? _lastObstacleWarning;
  DateTime? _lastLostAnnounce;

  @override
  void initState() {
    super.initState();

    _boxAnimationTicker = createTicker(_onBoxAnimationTick)..start();

    _initialize();
  }



  /// يُستدعى ~60 مرة بالثانية (بمعدل تحديث الشاشة). لكل جسم بالهدف
  /// الحالي (_detections)، يحسب موقع وسيط بين آخر موضع معروض فعليًا
  /// وموقع الهدف — بنفس أسلوب smoothing المستقل عن معدل الإطارات
  /// (framerate-independent) المستخدم بـ basira_home_screen.dart.
  ///
  /// الفرق عن smoothing الموديل (AppConstants.detectionSmoothing):
  /// ذاك يشتغل مرة وحدة كل ما الموديل يرجّع نتيجة جديدة (بطيء نسبيًا).
  /// هذا يشتغل باستمرار 60 مرة بالثانية بغض النظر عن سرعة الموديل —
  /// فيصير المربع "يزحف" بسلاسة نحو آخر هدف معروف، بدل ما يقفز إليه
  /// دفعة وحدة بالتحديث التالي من الموديل.
  void _onBoxAnimationTick(Duration elapsed) {
    final previousElapsed = _lastAnimationTickElapsed;
    _lastAnimationTickElapsed = elapsed;

    if (previousElapsed == null) return;

    final dtSeconds =
        (elapsed - previousElapsed).inMicroseconds / 1e6;

    if (dtSeconds <= 0) return;

    final targets = _detections;
    final previousAnimated = _animatedDetections.value;

    // ⚡ خروج مبكر: ما في شي نرسمه ولا شي كان مرسوم قبل — أشيَع حالة
    // (مافي كشف حاليًا، أو التطبيق متوقّف). بدون هذا الخروج، كنا
    // نخصّص Map وList فاضيين 60 مرة بالثانية بلا داعي طول ما التطبيق
    // مفتوح — هذا كان مصدر تراكم ذاكرة تدريجي لاحظناه فعليًا بالاختبار.
    if (targets.isEmpty && previousAnimated.isEmpty) return;

    // خريطة سريعة للوصول للموضع المعروض سابقًا بكل جسم عبر هويته.
    final previousByKey = <String, DetectedObject>{
      for (final obj in previousAnimated) obj.trackingKey: obj,
    };

    // معامل التقارب: كل ما زاد، كل ما "لحق" المربع الهدف أسرع.
    // الصيغة framerate-independent (بعكس lerp بسيط) — نفس النتيجة
    // بالضبط سواء الشاشة تحدّث 30 أو 60 أو 120 مرة بالثانية.
    final convergence =
        1 - math.exp(-AppConstants.boxAnimationSpeed * dtSeconds);

    final nextAnimated = <DetectedObject>[];
    var anyStillMoving = false;

    for (final target in targets) {
      final previous = previousByKey[target.trackingKey];

      if (previous == null) {
        // جسم جديد كليًا — يظهر فورًا بمكانه الصحيح، بدون ما "يطير"
        // من نقطة الصفر أو من مكان جسم تاني.
        nextAnimated.add(target);
        anyStillMoving = true;
        continue;
      }

      // ⚡ لو وصل قريب كفاية من الهدف (أقل من نص بكسل بكل ضلع)، اعتبره
      // "وصل" واستخدم موقع الهدف مباشرة — يوقف التقارب اللانهائي
      // نظريًا (exponential decay رياضيًا ما يوصل صفر تمامًا أبدًا)
      // ويقلل تغييرات دقيقة غير محسوسة بصريًا كانت تسبب إعادة رسم
      // وتخصيص ذاكرة كل تِك حتى بمشهد ثابت تمامًا.
      const converged = 0.5;
      final closeEnough =
          (previous.box.left - target.box.left).abs() < converged &&
              (previous.box.top - target.box.top).abs() < converged &&
              (previous.box.right - target.box.right).abs() < converged &&
              (previous.box.bottom - target.box.bottom).abs() < converged;

      if (closeEnough) {
        nextAnimated.add(target);
        continue;
      }

      anyStillMoving = true;

      final animatedBox = Rect.lerp(
        previous.box,
        target.box,
        convergence,
      )!;

      nextAnimated.add(
        DetectedObject(
          label: target.label,
          confidence: target.confidence,
          box: animatedBox,
          distance: target.distance,
          memoryId: target.memoryId,
        ),
      );
    }

    // ⚡ لو كل شي وصل لهدفه ومافي جسم جديد، ما داعي نحدّث القيمة كل
    // تِك — يقلل إعادة رسم/تخصيص غير محسوس بمشهد ثابت.
    if (!anyStillMoving &&
        previousAnimated.length == nextAnimated.length) {
      return;
    }

    _animatedDetections.value = nextAnimated;
  }

  Future<void> _clearMemory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('مسح ذاكرة الأجسام؟'),
          content: const Text(
            'سيتم حذف جميع الأجسام المحفوظة من الهاتف.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(false);
              },
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              child: const Text('مسح'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    await memory.clear();

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('تم مسح ذاكرة الأجسام'),
      ),
    );
  }

  Future<void> _initialize() async {
    try {
      // موديل الكشف إجباري — لو فشل، نوقف التطبيق ونعرض الخطأ.
      await _detector.load();

      // موديل العمق أصبح اختياريًا (يعمل عند الطلب فقط حسب الخطة
      // الجديدة). لو ملفه غير موجود بعد (مثلًا لسا ما أضفت MiDaS)،
      // لا نوقف التطبيق بالكامل — نكمل بدون قياس مسافة مؤقتًا.
      try {
        await _depth.load();
      } catch (e) {
        debugPrint(
          'تعذّر تحميل موديل العمق (سيعمل التطبيق بدون قياس '
              'المسافة لغاية إضافة الملف): $e',
        );
      }

      await _voice.init();
      await memory.init();

      _gyro.start();

      if (widget.cameras.isEmpty) {
        throw Exception('لم يتم العثور على كاميرا');
      }

      await _initializeCamera(0);

      if (!mounted) return;

      setState(() {
        _isInitializing = false;
      });
    } catch (e) {
      debugPrint('Initialization error: $e');

      if (!mounted) return;

      setState(() {
        _isInitializing = false;
        _error = 'فشل تجهيز النظام:\n$e';
      });
    }
  }

  Future<void> _initializeCamera(int index) async {
    final oldController = _controller;

    final controller = CameraController(
      widget.cameras[index],
      ResolutionPreset.medium,
      enableAudio: false,
    );

    _controller = controller;
    _cameraIndex = index;

    await controller.initialize();

    try {
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);
    } catch (e) {
      debugPrint('Camera settings error: $e');
    }

    await oldController?.dispose();

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _switchCamera() async {
    if (widget.cameras.length < 2) return;

    final wasRunning = _isRunning;

    if (wasRunning) {
      await _controller?.stopImageStream();
      _isRunning = false;
    }

    final nextIndex =
        (_cameraIndex + 1) % widget.cameras.length;

    await _initializeCamera(nextIndex);

    if (!mounted) return;

    if (wasRunning) {
      setState(() {
        _isRunning = true;
      });

      await _controller?.startImageStream(_onFrame);
    }
  }

  /// يشغّل/يوقف الصوت بالكامل بضغطة وحدة — مفيد للاختبار (هل التجمّد
  /// سببه الصوت فعلًا؟) ومفيد للاستخدام العادي (كتم مؤقت بمكان هادئ).
  void _toggleVoice() {
    setState(() {
      _voice.enabled = !_voice.enabled;
    });

    if (_voice.enabled) {
      _voice.speakNow('الصوت شغّال');
    }
  }

  Future<void> _toggleLanguage() async {
    final language =
    _voice.language == SpeechLanguage.arabic
        ? SpeechLanguage.english
        : SpeechLanguage.arabic;

    await _voice.setLanguage(language);

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _toggleDetection() async {
    final controller = _controller;

    if (controller == null) return;

    if (_isRunning) {
      await controller.stopImageStream();

      if (!mounted) return;

      setState(() {
        _isRunning = false;
        _detections = [];
      });

      _lastDepthMap = null;
      _missingDetectionFrames = 0;
      _processedFrameCounter = 0;
      _proximityLabels = {};
      _depthRequested = false;
      _isMeasuringDistance = false;
      _navigationTargetLabel = null;
      _navigationTargetId = null;
      _detectionStreak.clear();
      _lastNavigationAnnounce = null;
      _lastObstacleWarning = null;
      _lastLostAnnounce = null;
      _animatedDetections.value = [];
      _lastAnimationTickElapsed = null;
    } else {
      setState(() {
        _isRunning = true;
      });

      await controller.startImageStream(_onFrame);
    }
  }

  void _onFrame(CameraImage image) {
    if (!_isRunning || _isProcessingFrame) {
      return;
    }

    _frameCounter++;

    if (_frameCounter % AppConstants.frameSkip != 0) {
      return;
    }

    _isProcessingFrame = true;

    _processFrame(image).whenComplete(() {
      _isProcessingFrame = false;
    });
  }

  Future<void> _processFrame(CameraImage image) async {
    // ⏱️ قياس زمني مؤقت — نحتاج أرقام حقيقية (ميلي ثانية) بدل التخمين
    // لمعرفة أي مرحلة فعليًا تاخد الوقت الأكبر. احذف هذا البلوك بعد ما
    // نحسم السبب.
    final frameStopwatch = Stopwatch()..start();

    try {
      final camera = widget.cameras[_cameraIndex];
      final sensorOrientation = camera.sensorOrientation;

      final isRotated =
          sensorOrientation == 90 ||
              sensorOrientation == 270;

      final fullWidth = isRotated
          ? image.height
          : image.width;

      final fullHeight = isRotated
          ? image.width
          : image.height;

      final job = FrameConversionJob(
        yBytes: image.planes[0].bytes,
        uBytes: image.planes[1].bytes,
        vBytes: image.planes[2].bytes,
        width: image.width,
        height: image.height,
        yRowStride: image.planes[0].bytesPerRow,
        uvRowStride: image.planes[1].bytesPerRow,
        uvPixelStride:
        image.planes[1].bytesPerPixel ?? 1,
        sensorOrientation: sensorOrientation,
        targetSize: AppConstants.modelInputSize,
      );

      // تحويل إطار الكاميرا إلى RGB.
      final convertStart = frameStopwatch.elapsedMilliseconds;
      final converted = await compute(
        convertCameraFrame,
        job,
      );
      final convertMs =
          frameStopwatch.elapsedMilliseconds - convertStart;

      _processedFrameCounter++;

      // موديل الكشف يعمل في كل إطار تتم معالجته.
      final detectStart = frameStopwatch.elapsedMilliseconds;
      final detectedObjects = await _detector.detect(
        converted,
        fullWidth: fullWidth,
        fullHeight: fullHeight,
      );
      final detectMs =
          frameStopwatch.elapsedMilliseconds - detectStart;

      debugPrint(
        '⏱️ إطار: تحويل=${convertMs}ms، كشف+فك تشفير=${detectMs}ms، '
            'إجمالي حتى الآن=${frameStopwatch.elapsedMilliseconds}ms',
      );

      // موديل العمق يعمل فقط لما المستخدم يطلب صراحة (زر "ما المسافة؟")،
      // وليس تلقائيًا. لما نلتقط الطلب هون، نعيد تحويل نفس الإطار الخام
      // بحجم إدخال موديل العمق (قد يختلف عن حجم موديل الكشف)، ثم
      // نشغّل موديل العمق مرة واحدة بس.
      if (_depthRequested) {
        _depthRequested = false;

        final depthJob = FrameConversionJob(
          yBytes: image.planes[0].bytes,
          uBytes: image.planes[1].bytes,
          vBytes: image.planes[2].bytes,
          width: image.width,
          height: image.height,
          yRowStride: image.planes[0].bytesPerRow,
          uvRowStride: image.planes[1].bytesPerRow,
          uvPixelStride: image.planes[1].bytesPerPixel ?? 1,
          sensorOrientation: sensorOrientation,
          targetSize: AppConstants.depthInputSize,
        );

        final depthFrame = await compute(
          convertCameraFrame,
          depthJob,
        );

        final newDepthMap = await _depth.predict(depthFrame);

        if (newDepthMap != null) {
          _lastDepthMap = newDepthMap;
          await _announceProximity(
            detectedObjects,
            newDepthMap,
            fullWidth: fullWidth,
            fullHeight: fullHeight,
          );
        } else {
          _voice.speakNow('تعذّر قياس المسافة الآن');
        }

        if (mounted) {
          setState(() {
            _isMeasuringDistance = false;
          });
        }
      }

      final results = <DetectedObject>[];

      for (final object in detectedObjects) {
        // ⚠️ ذاكرة الأجسام (بصمة لونية + ملف JSON) معطَّلة حاليًا
        // (AppConstants.objectMemoryEnabled = false) — نتخطى الفحص
        // والحفظ كليًا، ونستخدم التسمية بس كهوية. أخف وأسرع بكثير،
        // بس بدون تمييز جسمين مختلفين بنفس التسمية (كرسي يسار/يمين).
        String? memoryId;

        if (AppConstants.objectMemoryEnabled) {
          final fingerprint = memory.fingerprintFor(
            frame: converted,
            box: object.box,
            fullWidth: fullWidth,
            fullHeight: fullHeight,
          );

          final memoryMatch = await memory.remember(
            label: object.label,
            fingerprint: fingerprint,
          );

          memoryId = memoryMatch.id;
        }

        double distance = object.distance;

        final depthMap = _lastDepthMap;

        if (depthMap != null) {
          distance = _depth.distanceAt(
            map: depthMap,
            box: object.box,
            fullWidth: fullWidth,
            fullHeight: fullHeight,
          ) ??
              object.distance;
        }

        results.add(
          DetectedObject(
            label: object.label,
            confidence: object.confidence,
            box: object.box,
            distance: distance,
            memoryId: memoryId,
          ),
        );
      }

      List<DetectedObject> displayResults;

      if (results.isNotEmpty) {
        // وجدنا الجسم؛ نعيد عداد الفقدان للصفر.
        _missingDetectionFrames = 0;

        // تنعيم حركة المربعات.
        displayResults = _smoothDetections(results);
      } else {
        // لم يجد الموديل الجسم في هذا الإطار فقط.
        _missingDetectionFrames++;

        if (_missingDetectionFrames <=
            AppConstants.detectionHoldFrames) {
          // نحتفظ بالنتيجة السابقة مؤقتًا.
          displayResults = _detections;
        } else {
          // اختفى الجسم فعلًا لفترة أطول.
          displayResults = [];
        }
      }

      if (!mounted) return;

      setState(() {
        _detections = displayResults;
        _imageWidth = fullWidth;
        _imageHeight = fullHeight;
      });

      // تحديث عدّاد الاستقرار: نبني الخريطة من جديد كل إطار بالاعتماد
      // على `results` (كشف هذا الإطار الفعلي فقط، مو المربعات
      // المحفوظة مؤقتًا) — أي جسم مو موجود بهذا الإطار يسقط من
      // الخريطة تلقائيًا (يرجع يبدأ من الصفر لو ظهر بعدين).
      final newStreak = <String, int>{};
      for (final obj in results) {
        final previousStreak = _detectionStreak[obj.trackingKey] ?? 0;
        newStreak[obj.trackingKey] = previousStreak + 1;
      }
      _detectionStreak
        ..clear()
        ..addAll(newStreak);

      // وضع التوجيه له أولوية على النطق العادي — نوقف الإعلانات
      // العشوائية عن الأجسام حتى ما تتداخل مع إرشادات التوجيه الحرجة.
      //
      // ⚠️ بدون await عمدًا: هذا هو الإصلاح الأهم للأداء — النطق
      // الصوتي (يمكن يأخذ ثانية أو أكتر لجملة كاملة) ما لازم يوقف
      // معالجة إطار الكاميرا التالي. قبل هذا التعديل، كل جملة نطق
      // كانت "تجمّد" الكشف بالكامل لحد ما تخلص — وهذا سبب رئيسي
      // لبطء الأداء المحسوس، خصوصًا إنه تطبيق لازم يبقى سريع الاستجابة
      // لمستخدم كفيف.
      if (_isNavigating) {
        _handleNavigation(displayResults, fullWidth, fullHeight);
      } else if (results.isNotEmpty) {
        // ننطق بس الأجسام المستقرة (ظهرت بإطارين متتاليين على الأقل)
        // — يفلتر كشوفات وهمية لحظية من ضبابية حركة الكاميرا السريعة.
        final stableForAnnounce = displayResults.where((obj) {
          final streak = _detectionStreak[obj.trackingKey] ?? 0;
          return streak >= AppConstants.minDetectionStreakForAnnounce;
        }).toList();

        if (stableForAnnounce.isNotEmpty) {
          _voice.announceIfNeeded(stableForAnnounce);
        }
      }

      // ⏱️ الزمن الكامل من بداية استلام الإطار لحد ما صار جاهز للعرض
      // على الشاشة (بدون احتساب رسم الشاشة نفسه، اللي يصير بخطوة
      // منفصلة لاحقة عبر setState/Ticker).
      debugPrint(
        '⏱️ إجمالي معالجة الإطار كامل: '
            '${frameStopwatch.elapsedMilliseconds}ms',
      );
    } catch (e) {
      debugPrint('Frame processing error: $e');
    }
  }
  /// يحسب القرب النسبي لكل جسم مكتشَف حاليًا بالاعتماد على خريطة عمق
  /// جديدة، وينطق ملخصًا صوتيًا (الأقرب أولًا)، ويحدّث _proximityLabels
  /// لعرضها بالواجهة (chips/صناديق).
  ///
  /// ⚠️ القيم هنا نسبية (relative depth) وليست أمتارًا حقيقية — MiDaS
  /// بدون معايرة إضافية ما يعطي مسافة متّرية دقيقة، بس ترتيب "مين أقرب
  /// من مين" بنفس المشهد. لهذا ننطق تصنيف قرب (قريب جدًا/قريب/متوسط/
  /// بعيد) بدل رقم بالمتر قد يكون مضلِّلًا.
  Future<void> _announceProximity(
      List<DetectedObject> objects,
      DepthMap depthMap, {
        required int fullWidth,
        required int fullHeight,
      }) async {
    if (objects.isEmpty) {
      _voice.speakNow('ما في أشياء واضحة أمامك الآن');
      return;
    }

    final withDepth = <MapEntry<DetectedObject, double>>[];

    for (final obj in objects) {
      final rawValue = _depth.distanceAt(
        map: depthMap,
        box: obj.box,
        fullWidth: fullWidth,
        fullHeight: fullHeight,
      );

      if (rawValue != null) {
        withDepth.add(MapEntry(obj, rawValue));
      }
    }

    if (withDepth.isEmpty) {
      _voice.speakNow('تعذّر تقدير المسافة لهذي الأشياء');
      return;
    }

    // رتّب من الأقرب للأبعد.
    withDepth.sort((a, b) {
      final cmp = AppConstants.depthHigherValueMeansCloser
          ? b.value.compareTo(a.value)
          : a.value.compareTo(b.value);
      return cmp;
    });

    final values = withDepth.map((e) => e.value).toList();
    final minValue = values.reduce(math.min);
    final maxValue = values.reduce(math.max);

    final newLabels = <String, String>{};

    for (final entry in withDepth) {
      final category = _proximityCategory(
        value: entry.value,
        minValue: minValue,
        maxValue: maxValue,
        higherIsCloser: AppConstants.depthHigherValueMeansCloser,
      );
      // نستخدم label (مو trackingKey) كمفتاح، لأن الأجسام هون خارجة
      // مباشرة من الموديل بدون معرّف ذاكرة بعد (يُضاف لاحقًا بمرحلة
      // مطابقة الذاكرة بـ _processFrame) — label ثابت ومضمون التطابق.
      newLabels[entry.key.label] = category;
    }

    if (mounted) {
      setState(() {
        _proximityLabels = newLabels;
      });
    }

    // نطق موجز: الأقرب فقط لو جسم واحد، أو الأقرب + الثاني لو أكثر.
    final nearestLabel = toArabicLabel(withDepth.first.key.label);

    if (withDepth.length == 1) {
      _voice.speakNow('$nearestLabel هو الأقرب إليك');
    } else {
      final secondLabel = toArabicLabel(withDepth[1].key.label);
      _voice.speakNow(
        'الأقرب إليك هو $nearestLabel، وبعده $secondLabel',
      );
    }
  }

  /// يحوّل قيمة عمق خام لتصنيف نصي بالعربي بالاعتماد على موقعها ضمن
  /// مدى القيم الحالي بنفس المشهد (وليس عتبات مطلقة، لأن المدى يختلف
  /// كثيرًا حسب الإضاءة والمشهد بموديلات العمق النسبي).
  String _proximityCategory({
    required double value,
    required double minValue,
    required double maxValue,
    required bool higherIsCloser,
  }) {
    if ((maxValue - minValue).abs() < 1e-6) {
      return 'متوسط';
    }

    var normalized = (value - minValue) / (maxValue - minValue);

    if (!higherIsCloser) {
      normalized = 1.0 - normalized;
    }

    if (normalized >= 0.75) return 'قريب جدًا';
    if (normalized >= 0.45) return 'قريب';
    if (normalized >= 0.2) return 'متوسط';
    return 'بعيد';
  }

  /// يفتح قائمة تختار منها جسم من الأجسام المكتشفة حاليًا لتبدأ التوجّه
  /// نحوه. لو في أكتر من جسم بنفس التسمية (مثلًا كرسيّين)، يعرض كل
  /// وحد لحاله مع تمييز موقعه (يسار/يمين/رقم) حتى تقدر تحدّد بالضبط
  /// أي وحد تقصد — القفل بعدها يصير بهويته البصرية الفعلية
  /// (trackingKey)، مو بس بتسميته.
  void _openObjectPicker() {
    if (_detections.isEmpty) return;

    final byLabel = <String, List<DetectedObject>>{};
    for (final obj in _detections) {
      byLabel.putIfAbsent(obj.label, () => []).add(obj);
    }

    final entries = <(String display, DetectedObject target)>[];

    byLabel.forEach((label, objs) {
      if (objs.length == 1) {
        entries.add((toArabicLabel(label), objs.first));
        return;
      }

      // أكتر من جسم بنفس التسمية — رتّبهم من اليسار لليمين بالصورة
      // ونضيف تمييز واضح لكل وحد.
      final sorted = [...objs]
        ..sort((a, b) => a.box.center.dx.compareTo(b.box.center.dx));

      for (int i = 0; i < sorted.length; i++) {
        final positionHint = sorted.length == 2
            ? (i == 0 ? 'يسار' : 'يمين')
            : 'رقم ${i + 1}';
        entries.add(
          ('${toArabicLabel(label)} ($positionHint)', sorted[i]),
        );
      }
    });

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.black87,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'اختر الجسم اللي تريد تتوجّه نحوه',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
              ...entries.map((entry) {
                return ListTile(
                  leading: const Icon(
                    Icons.near_me,
                    color: Colors.blueAccent,
                  ),
                  title: Text(
                    entry.$1,
                    style: const TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.of(context).pop();
                    _startNavigation(entry.$2);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _startNavigation(DetectedObject target) {
    setState(() {
      _navigationTargetLabel = target.label;
      _navigationTargetId = target.trackingKey;
      _lastNavigationAnnounce = null;
      _lastObstacleWarning = null;
      _lastLostAnnounce = null;
    });

    _gyro.resetYaw();

    _voice.speakNow(
      'بدأنا التوجّه نحو ${toArabicLabel(target.label)}. امشِ للأمام ببطء',
    );
  }

  void _cancelNavigation() {
    if (!_isNavigating) return;

    setState(() {
      _navigationTargetLabel = null;
      _navigationTargetId = null;
    });

    _voice.speakNow('تم إلغاء التوجيه');
  }

  /// يُستدعى بكل إطار مُعالَج أثناء وضع التوجيه. يراقب حجم صندوق الهدف
  /// (مؤشر تقارب بدون حاجة لموديل عمق)، وينبّه لو في عائق قريب بمنتصف
  /// الكادر، ولو فُقد الهدف من الرؤية.
  Future<void> _handleNavigation(
      List<DetectedObject> currentDetections,
      int fullWidth,
      int fullHeight,
      ) async {
    final targetLabel = _navigationTargetLabel;
    if (targetLabel == null) return;

    final targetId = _navigationTargetId;

    DetectedObject? target;
    for (final obj in currentDetections) {
      if (obj.label != targetLabel) continue;
      // نطابق بالهوية بالضبط (بصمة بصرية دائمة)، مو بس بأكبر صندوق
      // بنفس التسمية — هذا يمنع الالتباس لو في أكتر من جسم بنفس
      // التسمية بالمشهد (مثلًا كرسيّين جنب بعض).
      if (targetId != null && obj.trackingKey == targetId) {
        target = obj;
        break;
      }
    }

    if (target == null) {
      final now = DateTime.now();

      // إعلان فوري أول مرة يُفقَد فيها الهدف (مو انتظار عدة إطارات) —
      // المستخدم كفيف ولازم يعرف فورًا إنه فقد الرؤية، مو بعد نص ثانية.
      // بعدها نستخدم فترة انتظار قصيرة (cooldown) لتجنّب تكرار مزعج لو
      // ضل مفقود لفترة أطول.
      final canAnnounce = _lastLostAnnounce == null ||
          now.difference(_lastLostAnnounce!) >
              Duration(
                seconds: AppConstants.navigationLostAnnounceCooldownSeconds,
              );

      if (canAnnounce) {
        _lastLostAnnounce = now;

        final yaw = _gyro.cumulativeYaw;

        if (yaw.abs() < AppConstants.gyroMinYawToGuessDirection) {
          // ما لف بزاوية واضحة — الجسم اختفى لسبب تاني (احتجاب،
          // بعد كبير)، مو لأنه غيّر اتجاهه بنفسه.
          //
          // ⚠️ بدون await عمدًا: النطق ما لازم يوقف معالجة الإطار
          // التالي — لو المستخدم كفيف ورجع لاتجاهه صح، لازم التطبيق
          // "يشوف" هذا فورًا بأقرب إطار، مو يستنى لحد ما تخلص الجملة.
          _voice.speakNow(
            'فقدت ${toArabicLabel(targetLabel)} من مجال الرؤية، '
                'وجّه الكاميرا نحوه',
          );
        } else {
          final turnedLeft = AppConstants.gyroYawPositiveMeansTurnedLeft
              ? yaw > 0
              : yaw < 0;

          final direction = turnedLeft ? 'اليسار' : 'اليمين';
          final correction = turnedLeft ? 'يمين' : 'يسار';

          _voice.speakNow(
            'التفتّ ل$direction، ارجع شوي لل$correction حتى نرجع '
                'نلاقي ${toArabicLabel(targetLabel)}',
          );
        }
      }
      return;
    }

    _lastLostAnnounce = null;

    // شفنا الهدف فعليًا هالإطار — نصفّر عدّاد الدوران حتى يبقى يقيس
    // "الدوران منذ آخر مرة شفنا فيها الهدف" بس، مو من بداية التوجيه.
    _gyro.resetYaw();

    final heightRatio = target.box.height / fullHeight;

    if (heightRatio >= AppConstants.navigationArrivalBoxHeightRatio) {
      _voice.speakNow(
        'وصلت! ${toArabicLabel(targetLabel)} أمامك مباشرة',
      );

      if (mounted) {
        setState(() {
          _navigationTargetLabel = null;
          _navigationTargetId = null;
        });
      }
      return;
    }

    // فحص العوائق: أي جسم غير الهدف، كبير الحجم بالكادر، وقريب من
    // منتصفه أفقيًا (يعني بمسار المشي).
    final now = DateTime.now();

    for (final obj in currentDetections) {
      if (identical(obj, target)) continue;

      final areaRatio =
          (obj.box.width * obj.box.height) / (fullWidth * fullHeight);

      final centerOffset =
          (obj.box.center.dx - fullWidth / 2).abs() / fullWidth;

      final isObstacle =
          areaRatio >= AppConstants.navigationObstacleBoxAreaRatio &&
              centerOffset <= AppConstants.navigationObstacleCenterTolerance;

      if (!isObstacle) continue;

      final canWarn = _lastObstacleWarning == null ||
          now.difference(_lastObstacleWarning!) >
              Duration(
                seconds: AppConstants.navigationObstacleCooldownSeconds,
              );

      if (canWarn) {
        _lastObstacleWarning = now;
        _voice.speakNow(
          'انتبه! ${toArabicLabel(obj.label)} أمامك مباشرة',
        );
      }

      break;
    }

    // إرشاد دوري ("استمر") — بمعدّل محدود حتى ما يصير إزعاج.
    final canAnnounceProgress = _lastNavigationAnnounce == null ||
        now.difference(_lastNavigationAnnounce!) >
            Duration(
              seconds:
              AppConstants.navigationProgressAnnounceCooldownSeconds,
            );

    if (canAnnounceProgress) {
      _lastNavigationAnnounce = now;
      _voice.speakNow('استمر بالمشي');
    }
  }


  /// يُستدعى من زر "ما المسافة؟" بالواجهة. لا يشغّل الموديل مباشرة هون
  /// (لأنه ما عنده وصول للإطار الخام) — بس يرفع فلاغ، ويلتقطه
  /// _processFrame بأقرب إطار قادم وينفّذ القياس الفعلي.
  void _requestDistance() {
    if (!_isRunning || !_depth.isReady || _isMeasuringDistance) {
      if (!_depth.isReady) {
        _voice.speakNow('موديل قياس المسافة غير متوفر بعد');
      }
      return;
    }

    setState(() {
      _depthRequested = true;
      _isMeasuringDistance = true;
    });
  }

  List<DetectedObject> _smoothDetections(
      List<DetectedObject> incoming,
      ) {
    if (_detections.isEmpty) {
      return incoming;
    }

    final usedOldIndexes = <int>{};
    final smoothed = <DetectedObject>[];

    for (final current in incoming) {
      int? bestIndex;
      double bestScore = 0.0;

      for (int i = 0; i < _detections.length; i++) {
        if (usedOldIndexes.contains(i)) {
          continue;
        }

        final previous = _detections[i];

        if (previous.label != current.label) {
          continue;
        }

        final overlap = _boxIou(
          previous.box,
          current.box,
        );

        final centerDistance = _centerDistance(
          previous.box,
          current.box,
        );

        final allowedDistance = math.max(
          50.0,
          previous.box.longestSide * 0.8,
        );

        final isSameObject =
            overlap > 0.05 ||
                centerDistance < allowedDistance;

        if (!isSameObject) {
          continue;
        }

        final score = overlap +
            (1.0 -
                (centerDistance /
                    (allowedDistance * 2)))
                .clamp(0.0, 1.0);

        if (score > bestScore) {
          bestScore = score;
          bestIndex = i;
        }
      }

      if (bestIndex == null) {
        smoothed.add(current);
        continue;
      }

      usedOldIndexes.add(bestIndex);

      final previous = _detections[bestIndex];

      // ⚡ ما نعمل smoothing بالموقع هون بعد الآن — الـTicker
      // (_onBoxAnimationTick) صار يتكفّل بالتحريك السلس باستمرار
      // 60fps. لو عملنا smoothing هون كمان، بيصير تنعيم فوق تنعيم
      // (طبقتين)، والنتيجة إحساس "تأخر" أبطأ بدل أسرع. نمرر موقع
      // الهدف الخام مباشرة، والـTicker هو اللي يزحف نحوه بسلاسة.
      final smoothDistance = _smoothDistance(
        previous.distance,
        current.distance,
      );

      smoothed.add(
        DetectedObject(
          label: current.label,
          confidence: current.confidence,
          box: current.box,
          distance: smoothDistance,
          memoryId: current.memoryId ?? previous.memoryId,
        ),
      );
    }

    return smoothed;
  }

  Rect _lerpRect(
      Rect oldRect,
      Rect newRect,
      double amount,
      ) {
    return Rect.fromLTRB(
      oldRect.left +
          (newRect.left - oldRect.left) * amount,
      oldRect.top +
          (newRect.top - oldRect.top) * amount,
      oldRect.right +
          (newRect.right - oldRect.right) * amount,
      oldRect.bottom +
          (newRect.bottom - oldRect.bottom) * amount,
    );
  }

  double _smoothDistance(
      double oldDistance,
      double newDistance,
      ) {
    if (newDistance <= 0) {
      return oldDistance;
    }

    if (oldDistance <= 0) {
      return newDistance;
    }

    const newValueWeight = 0.65;
    const oldValueWeight = 0.35;

    return oldDistance * oldValueWeight +
        newDistance * newValueWeight;
  }

  double _centerDistance(
      Rect first,
      Rect second,
      ) {
    final dx = first.center.dx - second.center.dx;
    final dy = first.center.dy - second.center.dy;

    return math.sqrt(dx * dx + dy * dy);
  }

  double _boxIou(
      Rect first,
      Rect second,
      ) {
    final left = math.max(
      first.left,
      second.left,
    );

    final top = math.max(
      first.top,
      second.top,
    );

    final right = math.min(
      first.right,
      second.right,
    );

    final bottom = math.min(
      first.bottom,
      second.bottom,
    );

    final intersectionWidth = right - left;
    final intersectionHeight = bottom - top;

    if (intersectionWidth <= 0 ||
        intersectionHeight <= 0) {
      return 0.0;
    }

    final intersectionArea =
        intersectionWidth * intersectionHeight;

    final firstArea =
        first.width * first.height;

    final secondArea =
        second.width * second.height;

    final unionArea =
        firstArea + secondArea - intersectionArea;

    if (unionArea <= 0) {
      return 0.0;
    }

    return intersectionArea / unionArea;
  }
  @override
  void dispose() {
    _boxAnimationTicker.dispose();
    _animatedDetections.dispose();
    _controller?.dispose();
    _detector.dispose();
    _depth.dispose();
    _voice.dispose();
    _gyro.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.red,
              ),
            ),
          ),
        ),
      );
    }

    final controller = _controller;

    if (controller == null ||
        !controller.value.isInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,

      ),
      body: SafeArea(
        child: Column(
          children: [




            Container(
              color: Colors.black87,
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              child: Row(
                children: [
                  Text(
                    _isRunning
                        ? 'الكشف يعمل'
                        : 'متوقف',
                    style: const TextStyle(
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),



                  IconButton(
                    onPressed: _toggleVoice,
                    icon: Icon(
                      _voice.enabled
                          ? Icons.volume_up
                          : Icons.volume_off,
                      color: Colors.white,
                    ),
                    tooltip: _voice.enabled
                        ? 'كتم الصوت'
                        : 'تفعيل الصوت',
                  ),

                  TextButton.icon(
                    onPressed: _toggleLanguage,
                    icon: const Icon(
                      Icons.translate,
                      color: Colors.white,
                    ),
                    label: Text(
                      _voice.language ==
                          SpeechLanguage.arabic
                          ? 'AR'
                          : 'EN',
                      style: const TextStyle(
                        color: Colors.white,
                      ),
                    ),
                  ),


                  IconButton(
                    onPressed: _clearMemory,
                    icon: const Icon(
                      Icons.delete_sweep,
                      color: Colors.white,
                    ),
                    tooltip: 'مسح ذاكرة الأجسام',
                  ),

                  IconButton(
                    onPressed:
                    widget.cameras.length > 1
                        ? _switchCamera
                        : null,
                    icon: const Icon(
                      Icons.cameraswitch,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio:
                  1 / controller.value.aspectRatio,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (AppConstants.showCameraPreviewForDebug)
                        CameraPreview(controller)
                      else
                      // المستخدم الفعلي (كفيف) ما بيشوف هذا إطلاقًا
                      // — خلفية بسيطة بدل الفيديو الحي توفّر تركيب
                      // رسوميات حقيقي بدون أي خسارة وظيفية.
                        Container(color: Colors.black),
                      // مغلّف بـ ValueListenableBuilder (نفس أسلوب
                      // النقطة المضيئة بـ basira_home_screen.dart) —
                      // فيعيد رسم صندوق المربعات بس كل تِك (60fps)،
                      // بدون إعادة بناء الشاشة كاملة كل مرة.
                      ValueListenableBuilder<List<DetectedObject>>(
                        valueListenable: _animatedDetections,
                        builder: (context, animatedList, _) {
                          return CustomPaint(
                            painter: BoundingBoxPainter(
                              detections: animatedList,
                              imageWidth: _imageWidth,
                              imageHeight: _imageHeight,
                              labelTranslator: toArabicLabel,
                              proximityLabels: _proximityLabels,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            DetectionChipsBar(
              detections: _detections,
              labelTranslator: toArabicLabel,
              proximityLabels: _proximityLabels,
            ),
          ],
        ),
      ),
      floatingActionButton: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_isRunning && _isNavigating) ...[
            FloatingActionButton(
              heroTag: 'cancel_nav_fab',
              onPressed: _cancelNavigation,
              backgroundColor: Colors.orange,
              tooltip: 'إلغاء التوجيه',
              child: const Icon(Icons.close),
            ),
            const SizedBox(width: 12),
          ] else if (_isRunning && _detections.isNotEmpty) ...[
            FloatingActionButton(
              heroTag: 'navigate_fab',
              onPressed: _openObjectPicker,
              backgroundColor: Colors.purpleAccent,
              tooltip: 'توجّهني نحو شيء',
              child: const Icon(Icons.near_me),
            ),
            const SizedBox(width: 12),
          ],
          if (_isRunning) ...[
            FloatingActionButton(
              heroTag: 'distance_fab',
              onPressed: _isMeasuringDistance
                  ? null
                  : _requestDistance,
              backgroundColor: _depth.isReady
                  ? Colors.blueAccent
                  : Colors.grey,
              tooltip: 'ما المسافة؟',
              child: _isMeasuringDistance
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Icon(Icons.straighten),
            ),
            const SizedBox(width: 12),
          ],
          FloatingActionButton(
            heroTag: 'toggle_fab',
            onPressed: _toggleDetection,
            backgroundColor:
            _isRunning ? Colors.red : Colors.green,
            child: Icon(
              _isRunning
                  ? Icons.stop
                  : Icons.play_arrow,
            ),
          ),
        ],
      ),
    );
  }
}