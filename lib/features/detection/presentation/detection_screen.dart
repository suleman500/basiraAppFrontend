import 'dart:convert' show base64Decode;

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:projctlitudei/core/theme/app_colors.dart';

import '../../../core/constants.dart';
import '../../voice/data/labels_ar.dart';

import '../../voice/services/flutter_tts_adapter.dart';
import '../../voice/services/sherpa-tts-adapter.dart';
import '../../voice/services/voice_announcer.dart';

import '../models/detected_object.dart';
import '../services/ai_command_rewriter.dar.dart';
import '../services/depth_service.dart';
import '../services/detector_service.dart';
import '../services/hand_tracker_service.dart';
import '../services/native_detector_service.dart';
import '../services/frame_converter.dart';
import '../services/gyroscope_service.dart';
import '../services/speech_service.dart';
import '../services/voice_command_parser.dart';
import '../services/detection_smoothing.dart';
import '../services/box_animation_controller.dart';
import '../services/proximity_service.dart';
import '../services/hand_gesture_controller.dart';
import '../services/camera_stream_controller.dart';
import '../services/navigation_controller.dart';
import '../services/ai_backend_client.dart';

import '../services/ai_response_composer.dart';
import '../services/ai_response_speaker.dart';
import '../services/object_summary.dart';
import 'widgets/bounding_box_painter.dart';
import 'widgets/hand_skeleton_painter.dart';
import 'widgets/hud_widgets.dart';
import 'spatial_map_screen.dart';
import '../services/object_memory_service.dart';
import '../../training/presentation/training_screen.dart';

class DetectionScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const DetectionScreen({super.key, required this.cameras});

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen>
    with SingleTickerProviderStateMixin {
  final CameraStreamController _camera = CameraStreamController();

  DepthMap? _lastDepthMap;
  bool _freeSpaceRequested = false;
  bool _isCheckingFreeSpace = false;
  final ObjectMemoryService memory = ObjectMemoryService();
  int _missingDetectionFrames = 0;
  int _processedFrameCounter = 0;
  final dynamic _detector = AppConstants.useNativeDetector
      ? NativeDetectorService()
      : DetectorService();
  final DepthService _depth = DepthService();
  final VoiceAnnouncer _voice = VoiceAnnouncer(
    engine: AppConstants.useSherpaTts
        ? SherpaTtsAdapter()
        : FlutterTtsAdapter(),
  );
  final GyroscopeService _gyro = GyroscopeService();
  final HandTrackerService _handTracker = HandTrackerService();
  late final SpeechService _speech = SpeechService(onText: _onSpeechText);

  // ⚠️ طبقة الـAI الاختيارية — الثلاث كائنات هون بيتشاركوا نفس

  // AiBackendClient (نفس الإعدادات: عنوان + مفتاح)، بس كل وحدة

  // مسؤولة عن مهمة مختلفة تمامًا (راجع تعليقات كل ملف): تصنيف نية

  // (Fallback لما الفهم المحلي يفشل) مقابل صياغة رد (بعد ما نعرف

  // شو الأمر وعنا بيانات أجسام). لا شي هون بيعمل أي اتصال فعلي إلا

  // لو AppConstants.aiBackendEnabled = true — القيمة الافتراضية false

  // فتشغيل التطبيق بدون تعديل أي شي يبقى محليًا بالكامل زي ما هو.

  late final AiBackendClient _aiClient = AiBackendClient(
    AiBackendConfig(
      baseUrl: AppConstants.aiBackendBaseUrl,
      apiKey: AppConstants.aiBackendApiKey,
    ),
  );
  late final AiCommandRewriter _aiCommandRewriter = AiCommandRewriter(
    _aiClient,
  );
  late final AiResponseComposer _aiResponseComposer = AiResponseComposer(
    _aiClient,
  );

  /// ⚠️ مشغّل صوت مخصّص للردود الجاهزة من السحابة (MP3 base64 من
  ///
  /// compose-and-speak) — منفصل تمامًا عن TtsAdapter المحلي
  ///
  /// (FlutterTtsAdapter/SherpaTtsAdapter داخل VoiceAnnouncer)، لأنه
  /// 
  /// هون بنشغّل ملف صوت جاهز، مو "ننطق نص" عبر محرك تحويل نص→كلام.
  ///
  final AudioPlayer _cloudAudioPlayer = AudioPlayer();

  late final ProximityAnnouncer _proximityAnnouncer = ProximityAnnouncer(
    voice: _voice,
    depth: _depth,
    memory: memory,
  );

  bool _isListeningForCommand = false;
  bool _micPressActive = false;
  int _micGestureId = 0;
  String _recognizedSpeechText = '';

  /// ⚠️ true لو إحنا (مو المستخدم من زر الكشف الحي) اللي فتحنا البث
  /// المستمر عشان أمر صوتي "بدي أروح لـ..." — بعكس دفعة الكاميرا
  /// القصيرة (_performBurstScan) اللي بتقفل نفسها لحالها، التوجيه
  /// محتاج بث مستمر طول فترة المشي، فما نقدر نستخدم نفس آلية القفل
  /// التلقائي. نستخدم هالعلم لنعرف: لما التوجيه ينتهي (وصول أو إلغاء)،
  /// هل نحن المسؤولين عن قفل الكاميرا، ولا كانت شغّالة أصلًا (المستخدم
  /// شغّلها بنفسه) وما لازم نلمسها.
  bool _weStartedCameraForNavigation = false;

  /// ⚠️ سؤال توضيح صوتي معلّق ("أي كرسي؟") — null يعني ما في سؤال
  /// مفتوح حاليًا. لما يكون فيه قيمة، أول شي بيعمله _onMicPressUp
  /// بالضغطة الجاية هو يحاول يفسّر الجواب كـ"رد على السؤال المعلّق"
  /// قبل ما يعامله كأمر عادي.
  _PendingDisambiguation? _pendingDisambiguation;

  List<DetectedObject> _detections = [];

  final Map<String, int> _detectionStreak = {};

  Map<String, String> _proximityLabels = {};

  int _imageWidth = 0;
  int _imageHeight = 0;
  int _frameCounter = 0;

  bool _isInitializing = true;
  bool _isRunning = false;
  bool _isProcessingFrame = false;
  String? _error;

  bool _depthRequested = false;
  bool _isMeasuringDistance = false;

  /// ⚠️ late final لأنها محتاجة _gyro و_voice (مُعرَّفين فوق كـlate
  /// final هم كمان) — نفس نمط باقي الكنترولرز بالملف.
  late final NavigationController _navigation = NavigationController(
    gyro: _gyro,
    voice: _voice,
  );

  bool get _isNavigating => _navigation.isNavigating;

  /// ⚠️ الحقول الثلاثة تحت هي حالة عرض بحتة (بيقرأها build() مباشرة)
  /// — لهيك بتضل هون بالشاشة، مو بـHandGestureController. الكنترولر
  /// بيحسبها كل إطار ويرجّعها، والشاشة هي اللي تخزّنها عبر setState.
  String? _touchedObjectKey;
  List<HandLandmark> _handPointsForDisplay = [];
  bool _isFistForDisplay = false;

  late final HandGestureController _handGesture = HandGestureController();

  /// ⚠️ الحقل الوحيد اللي محتاج `this` كـTickerProvider — لهيك لازم
  /// يُعرَّف بعد ما الكلاس يصير مؤهّل (SingleTickerProviderStateMixin
  /// بأعلى الكلاس). بيقرأ _detections و_handPointsForDisplay مباشرة
  /// من خلال getters (closures)، فأي تحديث عليهم بينعكس تلقائيًا
  /// بالتيك الجاي بدون أي ربط إضافي.
  late final BoxAnimationController _boxAnimation = BoxAnimationController(
    vsync: this,
    targetDetections: () => _detections,
    targetHandPoints: () => _handPointsForDisplay,
  );

  @override
  void initState() {
    super.initState();

    _initialize();
  }

  Future<void> _clearMemory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('مسح ذاكرة الأجسام؟'),
          content: const Text('سيتم حذف جميع الأجسام المحفوظة من الهاتف.'),
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

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('تم مسح ذاكرة الأجسام')));
  }

  Future<void> _initialize() async {
    try {
      await _detector.load();

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

      if (AppConstants.voiceCommandsEnabled) {
        try {
          await _speech.init();
        } catch (e) {
          debugPrint('تعذّر تهيئة الأوامر الصوتية (سيعمل التطبيق بدونها): $e');
        }
      }

      if (AppConstants.handTrackingEnabled) {
        try {
          await _handTracker.load();
        } catch (e) {
          debugPrint('تعذّر تحميل موديل تتبّع اليد (سيعمل التطبيق بدونه): $e');
        }
      }

      _gyro.start();

      if (widget.cameras.isEmpty) {
        throw Exception('لم يتم العثور على كاميرا');
      }

      await _camera.initialize(widget.cameras, 0);

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

  Future<void> _switchCamera() async {
    if (widget.cameras.length < 2) return;
    if (_camera.isBusy) return;

    final wasRunning = _isRunning;

    if (wasRunning) {
      await _camera.tryStopStream();
      _isRunning = false;
    }

    final nextIndex = (_camera.cameraIndex + 1) % widget.cameras.length;

    await _camera.initialize(widget.cameras, nextIndex);

    if (!mounted) return;

    // ⚠️ لازم setState هون حتى build() ياخد الـCameraController الجديد
    // (كان _initializeCamera يعملها ضمنيًا قبل الفصل — هلق الشاشة
    // هي المسؤولة، لأنها صاحبة setState/mounted، مو الكنترولر).
    setState(() {});

    if (wasRunning) {
      final started = await _camera.tryStartStream(_onFrame);

      if (mounted) {
        setState(() => _isRunning = started);
      } else {
        _isRunning = started;
      }
    }
  }

  void _toggleVoice() {
    setState(() {
      _voice.enabled = !_voice.enabled;
    });

    if (_voice.enabled) {
      _voice.speakNow('الصوت شغّال');
    }
  }

  Future<void> _toggleLanguage() async {
    final language = _voice.language == SpeechLanguage.arabic
        ? SpeechLanguage.english
        : SpeechLanguage.arabic;

    await _voice.setLanguage(language);

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _toggleDetection() async {
    if (_camera.controller == null) return;
    if (_camera.isBusy) return;

    if (_isRunning) {
      await _camera.tryStopStream();

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
      _freeSpaceRequested = false;
      _isCheckingFreeSpace = false;
      _navigation.cancelSilently();
      _detectionStreak.clear();
      _boxAnimation.reset();
      _touchedObjectKey = null;
      _handPointsForDisplay = [];
      _isFistForDisplay = false;
      _handGesture.reset();
    } else {
      final started = await _camera.tryStartStream(_onFrame);

      if (mounted) {
        setState(() => _isRunning = started);
      } else {
        _isRunning = started;
      }
    }
  }

  /// ⚠️ قلب المرحلة 2 من الخطة — "دفعة الكاميرا القصيرة". هاي الدالة
  /// هي اللي رح تخلي الأوامر الصوتية تفتح الكاميرا لحالها وتقفلها،
  /// بدل ما تعتمد على زر يدوي. ما فيها أي منطق كشف جديد — بتشغّل
  /// نفس مسار _onFrame/_processFrame الموجود أصلًا (اللي أصلاً بيعمل
  /// كشف + عمق عند الطلب + تحديث ذاكرة)، بتستنى مدة قصيرة، وبعدين
  /// توقف البث لو هي اللي بدأته.
  ///
  /// ⚠️ لو _isRunning كان شغّال أصلًا (مثلاً المستخدم شغّل الكشف الحي
  /// بنفسه)، ما منلمسه — منسيب الوضع الحالي زي ما هو،
  /// ومنستنى بس مدة الدفعة، بدون ما نطفي شي المستخدم شغّله بنفسه.
  ///
  /// ⚠️ عمدًا ما بتعمل reset لـ_detections أو الذاكرة بعد ما تخلص
  /// (بعكس _toggleDetection وقت الإيقاف اليدوي) — الهدف نبقي آخر
  /// نتيجة كشف متاحة فورًا للمستدعي (لصياغة الرد، أو لـobject_summary
  /// لو الـAI مفعّل)، والذاكرة أصلًا دايمة (ObjectMemoryService) وما
  /// إلها علاقة بحالة الكاميرا.
  Future<void> _performBurstScan({Duration? duration}) async {
    if (_camera.controller == null ||
        !_camera.controller!.value.isInitialized) {
      return;
    }

    // ⚠️ لو فيه عملية تانية عالبث شغّالة أصلًا (مثلاً المستخدم ضغط
    // زر الكشف الحي بنفس اللحظة)، منتجاهل الطلب بهدوء بدل ما نخاطر
    // بتصادم — الأمر الصوتي وقتها بيرد بمعلومة قديمة من الذاكرة
    // (أفضل من كاميرا معلّقة).
    if (_camera.isBusy) {
      debugPrint('⚠️ تجاهلت دفعة الكاميرا القصيرة — عملية تانية شغّالة');
      return;
    }

    final weStartedIt = !_isRunning;

    if (weStartedIt) {
      final started = await _camera.tryStartStream(_onFrame);
      if (!started) return;

      if (mounted) {
        setState(() => _isRunning = true);
      } else {
        _isRunning = true;
      }
    }

    await Future.delayed(duration ?? AppConstants.voiceBurstScanDuration);

    if (weStartedIt && _isRunning) {
      await _camera.tryStopStream();

      if (mounted) {
        setState(() => _isRunning = false);
      } else {
        _isRunning = false;
      }
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
    final frameStopwatch = Stopwatch()..start();

    try {
      final camera = widget.cameras[_camera.cameraIndex];
      final sensorOrientation = camera.sensorOrientation;

      final isRotated = sensorOrientation == 90 || sensorOrientation == 270;

      final fullWidth = isRotated ? image.height : image.width;

      final fullHeight = isRotated ? image.width : image.height;

      final job = FrameConversionJob(
        yBytes: image.planes[0].bytes,
        uBytes: image.planes[1].bytes,
        vBytes: image.planes[2].bytes,
        width: image.width,
        height: image.height,
        yRowStride: image.planes[0].bytesPerRow,
        uvRowStride: image.planes[1].bytesPerRow,
        uvPixelStride: image.planes[1].bytesPerPixel ?? 1,
        sensorOrientation: sensorOrientation,
        targetSize: AppConstants.modelInputSize,
      );

      final convertStart = frameStopwatch.elapsedMilliseconds;
      final converted = await compute(convertCameraFrame, job);
      final convertMs = frameStopwatch.elapsedMilliseconds - convertStart;

      _processedFrameCounter++;

      final detectStart = frameStopwatch.elapsedMilliseconds;
      final detectedObjects = await _detector.detect(
        converted,
        fullWidth: fullWidth,
        fullHeight: fullHeight,
      );
      final detectMs = frameStopwatch.elapsedMilliseconds - detectStart;

      debugPrint(
        '⏱️ إطار: تحويل=${convertMs}ms، كشف+فك تشفير=${detectMs}ms، '
        'إجمالي حتى الآن=${frameStopwatch.elapsedMilliseconds}ms',
      );

      final List<HandLandmark> handLandmarks;
      if (AppConstants.handTrackingEnabled &&
          _handTracker.isReady &&
          _processedFrameCounter % 2 == 0) {
        handLandmarks = await _handTracker.detect(
          converted.rgbBytes,
          width: converted.size,
          height: converted.size,
        );
      } else {
        handLandmarks = const <HandLandmark>[];
      }

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

        final depthFrame = await compute(convertCameraFrame, depthJob);

        final newDepthMap = await _depth.predict(depthFrame);

        if (newDepthMap != null) {
          _lastDepthMap = newDepthMap;

          final newProximityLabels = await _proximityAnnouncer
              .announceProximity(
                detectedObjects,
                newDepthMap,
                fullWidth: fullWidth,
                fullHeight: fullHeight,
              );

          if (newProximityLabels != null && mounted) {
            setState(() {
              _proximityLabels = newProximityLabels;
            });
          }
        } else {
          _voice.speakNow('تعذّر قياس المسافة الآن');
        }

        if (mounted) {
          setState(() {
            _isMeasuringDistance = false;
          });
        }
      }

      if (_freeSpaceRequested) {
        _freeSpaceRequested = false;

        final freeSpaceJob = FrameConversionJob(
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

        final freeSpaceFrame = await compute(convertCameraFrame, freeSpaceJob);

        if (_depth.isFrameLikelyBlocked(freeSpaceFrame.rgbBytes)) {
          _voice.speakNow(
            'الكاميرا يبدو أنها مغطاة، امسح العدسة وجرب مرة ثانية',
          );
        } else {
          final freeSpaceDepthMap = await _depth.predict(freeSpaceFrame);

          if (freeSpaceDepthMap != null) {
            _lastDepthMap = freeSpaceDepthMap;
            final result = _depth.analyzeFreeSpace(freeSpaceDepthMap);
            _proximityAnnouncer.announceFreeSpace(result);
          } else {
            _voice.speakNow('تعذّر تحليل المساحة الآن');
          }
        }

        if (mounted) {
          setState(() {
            _isCheckingFreeSpace = false;
          });
        }
      }

      final results = <DetectedObject>[];

      for (final object in detectedObjects) {
        double distance = object.distance;

        final depthMap = _lastDepthMap;

        if (depthMap != null) {
          distance =
              _depth.distanceAt(
                map: depthMap,
                box: object.box,
                fullWidth: fullWidth,
                fullHeight: fullHeight,
              ) ??
              object.distance;
        }

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
            box: object.box,
            fullWidth: fullWidth,
            fullHeight: fullHeight,
            confidence: object.confidence,
            distance: distance,
            headingRadians: _gyro.hasHeading ? _gyro.heading : null,
          );

          memoryId = memoryMatch.id;
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

      if (AppConstants.objectMemoryEnabled) {
        memory.sweepStatuses();
      }

      final handResult = _handGesture.process(
        handLandmarks: handLandmarks,
        results: results, // ⚠️ الكنترولر بيعدّل هالقائمة بالمكان
        fullWidth: fullWidth,
        fullHeight: fullHeight,
      );

      if (mounted) {
        setState(() {
          _touchedObjectKey = handResult.touchedObjectKey;
          _handPointsForDisplay = handResult.displayHandPoints;
          _isFistForDisplay = handResult.isFist;
        });
      }

      final justSelected = handResult.justSelectedObject;
      if (justSelected != null) {
        _voice.speakNow('${toArabicLabel(justSelected.label)} — تم التحديد');
        _startNavigation(justSelected);
      }

      List<DetectedObject> displayResults;

      if (results.isNotEmpty) {
        _missingDetectionFrames = 0;

        displayResults = smoothDetections(_detections, results);
      } else {
        _missingDetectionFrames++;

        if (_missingDetectionFrames <= AppConstants.detectionHoldFrames) {
          displayResults = _detections;
        } else {
          displayResults = [];
        }
      }

      if (!mounted) return;

      setState(() {
        _detections = displayResults;
        _imageWidth = fullWidth;
        _imageHeight = fullHeight;
      });

      final newStreak = <String, int>{};
      for (final obj in results) {
        final previousStreak = _detectionStreak[obj.trackingKey] ?? 0;
        newStreak[obj.trackingKey] = previousStreak + 1;
      }
      _detectionStreak
        ..clear()
        ..addAll(newStreak);

      if (_isNavigating) {
        _handleNavigation(displayResults, fullWidth, fullHeight);
      } else if (AppConstants.announceAllDetectionsAutomatically &&
          results.isNotEmpty) {
        final stableForAnnounce = displayResults.where((obj) {
          final streak = _detectionStreak[obj.trackingKey] ?? 0;
          return streak >= AppConstants.minDetectionStreakForAnnounce;
        }).toList();

        if (stableForAnnounce.isNotEmpty) {
          _voice.announceIfNeeded(stableForAnnounce);
        }
      }

      debugPrint(
        '⏱️ إجمالي معالجة الإطار كامل: '
        '${frameStopwatch.elapsedMilliseconds}ms',
      );
    } catch (e) {
      debugPrint('Frame processing error: $e');
    }
  }

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

      final sorted = [...objs]
        ..sort((a, b) => a.box.center.dx.compareTo(b.box.center.dx));

      for (int i = 0; i < sorted.length; i++) {
        final positionHint = sorted.length == 2
            ? (i == 0 ? 'يسار' : 'يمين')
            : 'رقم ${i + 1}';
        entries.add(('${toArabicLabel(label)} ($positionHint)', sorted[i]));
      }
    });

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (context) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'اختر الجسم اللي تريد تتوجّه نحوه',
                    style: TextStyle(
                      color: AppColors.onSurface,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ...entries.map((entry) {
                  return ListTile(
                    minTileHeight: 60,
                    leading: const Icon(
                      Icons.near_me,
                      color: AppColors.primary,
                    ),
                    title: Text(
                      entry.$1,
                      style: const TextStyle(
                        color: AppColors.onSurface,
                        fontSize: 16,
                      ),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      _startNavigation(entry.$2);
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _startNavigation(DetectedObject target) {
    setState(() {
      _navigation.start(target);
    });
  }

  /// ⚠️ يُستدعى من NavigateToObjectCommand — "بدي أروح للكرسي" مثلًا.
  /// مختلف جوهريًا عن _performBurstScan: التوجيه محتاج بث كاميرا
  /// **مستمر** طول فترة المشي (مو دفعة تقفل نفسها)، لأن _handleNavigation
  /// بيحتاج يتابع الهدف كل إطار لحد ما يوصل أو يضيع. فهون منفتح
  /// البث بنفس أسلوب _toggleDetection (تشغيل)، بس منستنى شوي أول
  /// حتى تتجمّع كشوفات كافية، وبعدين ندوّر على الهدف ونبدأ _startNavigation
  /// الموجودة أصلًا (هي اللي بتصفّر الجيروسكوب وتنطق بداية التوجيه).
  Future<void> _startVoiceNavigation({
    required String englishLabel,
    required String arabicLabel,
  }) async {
    if (_isNavigating) {
      _voice.speakNow(
        'في توجيه شغّال أصلًا — قول وقف الأول لو بدك تبدأ توجيه جديد',
      );
      return;
    }

    if (_camera.controller == null ||
        !_camera.controller!.value.isInitialized) {
      _voice.speakNow('الكاميرا غير جاهزة الآن');
      return;
    }

    if (_camera.isBusy) {
      _voice.speakNow('الكاميرا مشغولة حاليًا، جرّب بعد شوي');
      return;
    }

    _voice.speakNow('لحظة، خليني أدور على $arabicLabel');

    final weStartedStream = !_isRunning;

    if (weStartedStream) {
      final started = await _camera.tryStartStream(_onFrame);
      if (!started) {
        _voice.speakNow('تعذّر تشغيل الكاميرا الآن');
        return;
      }

      if (mounted) {
        setState(() => _isRunning = true);
      } else {
        _isRunning = true;
      }
    }

    // نستنى نفس مدة دفعة الكاميرا القصيرة حتى تتجمّع كشوفات كافية
    // قبل ما نحاول نلاقي الهدف — نفس المنطق، بس هون ما رح نقفل
    // البث بعدها (التوجيه محتاجه مستمر).
    await Future.delayed(AppConstants.voiceBurstScanDuration);

    final matches = _detections
        .where((obj) => obj.label == englishLabel)
        .toList();

    if (matches.isEmpty) {
      _voice.speakNow('مش قادر ألقى $arabicLabel حاليًا');

      if (weStartedStream) {
        await _camera.tryStopStream();
        if (mounted) {
          setState(() => _isRunning = false);
        } else {
          _isRunning = false;
        }
      }
      return;
    }

    if (matches.length == 1) {
      _weStartedCameraForNavigation = weStartedStream;
      _startNavigation(matches.first);
      return;
    }

    // ⚠️ أكتر من جسم بنفس الاسم — نسأل توضيح صوتي بدل ما نخمّن.
    // مرتّبة يسار→يمين (نفس ترتيب _openObjectPicker) حتى "يمين"/
    // "يسار" بجواب المستخدم يطابق _resolveDisambiguationAnswer.
    // منخلي الكاميرا شغّالة لحد ما يجاوب (أو يلغي/يحكي أمر تاني).
    final sorted = [...matches]
      ..sort((a, b) => a.box.center.dx.compareTo(b.box.center.dx));

    _weStartedCameraForNavigation = weStartedStream;
    _pendingDisambiguation = _PendingDisambiguation(candidates: sorted);

    if (sorted.length == 2) {
      _voice.speakNow(
        'لقيت أكتر من $arabicLabel، وحدة على يسارك ووحدة على '
        'يمينك — أي وحدة تقصد؟',
      );
    } else {
      _voice.speakNow(
        'لقيت ${sorted.length} من $arabicLabel، قول رقم الوحدة '
        'من واحد لـ${sorted.length}',
      );
    }
  }

  /// يحاول يفسّر [rawText] كجواب على سؤال توضيح معلّق (_pendingDisambiguation).
  /// يرجّع true لو نجح وبدأ التوجيه فعليًا (يعني تم التعامل مع
  /// الضغطة كاملة، ما لازم تُعالَج كأمر جديد). يرجّع false لو ما فيه
  /// سؤال معلّق أصلًا، أو الجواب مو مفهوم — بهاي الحالة المستدعي
  /// (_onMicPressUp) بيلغي السؤال المعلّق ويعامل النص كأمر عادي من
  /// الصفر (يغطي حالتين: المستخدم جاوب بصياغة غريبة، أو غيّر رأيه
  /// وحكى أمر تاني كليًا).
  bool _resolveDisambiguationAnswer(String rawText) {
    final pending = _pendingDisambiguation;
    if (pending == null) return false;

    final normalized = normalizeArabicText(rawText);
    DetectedObject? chosen;

    if (pending.candidates.length == 2) {
      // candidates مرتّبة يسار→يمين (نفس ترتيب _openObjectPicker).
      final saysRight = normalized.contains(normalizeArabicText('يمين'));
      final saysLeft =
          normalized.contains(normalizeArabicText('يسار')) ||
          normalized.contains(normalizeArabicText('شمال'));

      if (saysRight && !saysLeft) {
        chosen = pending.candidates[1];
      } else if (saysLeft && !saysRight) {
        chosen = pending.candidates[0];
      }
    } else {
      const numberWords = {
        'واحد': 1,
        'اول': 1,
        'أول': 1,
        'اثنين': 2,
        'ثنتين': 2,
        'تاني': 2,
        'ثاني': 2,
        'تلاتة': 3,
        'ثلاثة': 3,
        'ثالث': 3,
        'اربعة': 4,
        'أربعة': 4,
        'خمسة': 5,
      };

      for (final word in normalized.split(' ')) {
        final index = int.tryParse(word) ?? numberWords[word];
        if (index != null && index >= 1 && index <= pending.candidates.length) {
          chosen = pending.candidates[index - 1];
          break;
        }
      }
    }

    if (chosen == null) return false;

    _pendingDisambiguation = null;
    _startNavigation(chosen);
    return true;
  }

  /// يلغي أي سؤال توضيح معلّق بهدوء — يُستدعى لما الجواب ما انفهم،
  /// أو لما المستخدم حكى أمر تاني كليًا بدل ما يجاوب. لو إحنا فتحنا
  /// الكاميرا لأجل هالسؤال، منقفلها هون (النص الجديد، إذا احتاج
  /// كاميرا، رح يفتحها من جديد بنفسه عاديًا).
  Future<void> _cancelPendingDisambiguation() async {
    if (_pendingDisambiguation == null) return;
    _pendingDisambiguation = null;
    await _stopCameraIfWeStartedItForNavigation();
  }

  void _cancelNavigation() {
    if (!_isNavigating) return;

    setState(() {
      _navigation.cancel();
    });

    _stopCameraIfWeStartedItForNavigation();
  }

  /// يقفل بث الكاميرا لو إحنا (مو المستخدم من زر الكشف الحي) اللي
  /// فتحناه لأجل أمر "بدي أروح لـ..." — يُستدعى بعد وصول أو إلغاء
  /// التوجيه. لو الكاميرا كانت شغّالة أصلًا لسبب تاني،
  /// ما بنلمسها ونسيبها متل ما كانت.
  Future<void> _stopCameraIfWeStartedItForNavigation() async {
    if (!_weStartedCameraForNavigation) return;

    _weStartedCameraForNavigation = false;

    if (!_isRunning) return;

    await _camera.tryStopStream();

    if (mounted) {
      setState(() => _isRunning = false);
    } else {
      _isRunning = false;
    }
  }

  /// ⚠️ الشاشة هلق بس "توصّل" التيك للكنترولر وترد فعل على وصول
  /// الهدف (قفل كاميرا) — كل منطق التتبّع/النطق نفسه صار جوا
  /// NavigationController.handleFrame.
  Future<void> _handleNavigation(
    List<DetectedObject> currentDetections,
    int fullWidth,
    int fullHeight,
  ) async {
    final outcome = await _navigation.handleFrame(
      currentDetections,
      fullWidth,
      fullHeight,
    );

    if (outcome == NavigationTick.arrived) {
      if (mounted) setState(() {});
      await _stopCameraIfWeStartedItForNavigation();
    }
  }

  void _onSpeechText(String text, bool _) {
    if (!mounted || text == _recognizedSpeechText) return;

    setState(() {
      _recognizedSpeechText = text;
    });
  }

  Future<void> _onMicPressDown() async {
    if (!AppConstants.voiceCommandsEnabled || _micPressActive) return;

    debugPrint('🎤 المايك: pointer down');
    _micPressActive = true;
    final gestureId = ++_micGestureId;

    if (mounted) {
      setState(() {
        _isListeningForCommand = true;
        _recognizedSpeechText = '';
      });
    }

    if (!_speech.isAvailable) {
      _micPressActive = false;
      if (mounted) {
        setState(() {
          _isListeningForCommand = false;
        });
      }
      _voice.speakNow('الأوامر الصوتية غير متوفرة على هذا الجهاز');
      return;
    }

    final started = await _speech.startListening();
    debugPrint('🎤 المايك: startListening=$started');

    if (!_micPressActive || gestureId != _micGestureId) {
      if (started) {
        await _speech.stopListening();
      }
      return;
    }

    if (!started && mounted) {
      setState(() {
        _isListeningForCommand = false;
      });
    }
  }

  Future<void> _onMicPressUp() async {
    if (!_micPressActive) return;

    debugPrint('🎤 المايك: pointer up');
    _micPressActive = false;
    _micGestureId++;

    final recognizedText = await _speech.stopListening();

    if (mounted) {
      setState(() {
        _isListeningForCommand = false;
        if (recognizedText != null && recognizedText.isNotEmpty) {
          _recognizedSpeechText = recognizedText;
        }
      });
    }

    if (recognizedText == null || recognizedText.isEmpty) {
      debugPrint('🎤 المايك: لم يصل أي نص');
      _voice.speakNow('ما سمعت شي، حاول مرة ثانية');
      return;
    }

    debugPrint('🎤 أمر صوتي مسموع: "$recognizedText"');

    // ⚠️ لو فيه سؤال توضيح معلّق ("أي كرسي؟")، نجرّب نفسّر هالنص
    // كجواب عليه أول شي — قبل أي معالجة عادية. لو نجح، خلص، ما
    // لازم نكمل (تم بدء التوجيه فعليًا جوا الدالة). لو فشل، نلغي
    // السؤال المعلّق ونكمل معالجة النص كأمر عادي من الصفر.
    if (_pendingDisambiguation != null) {
      if (_resolveDisambiguationAnswer(recognizedText)) return;
      await _cancelPendingDisambiguation();
    }

    var command = parseVoiceCommand(recognizedText);

    // ⚠️ Fallback اختياري: لو الفهم المحلي فشل (UnknownCommand) وطبقة
    // الـAI مفعّلة، نطلب من الباك-اند "يعيد صياغة" النص لصيغة قانونية
    // معروفة (زي "نادي الكرسي" → "وين الكرسي")، وبعدين نعيد تمريره
    // لنفس parseVoiceCommand المحلي — مو AI يبني VoiceCommand بنفسه.
    // لو فشل الاتصال أو ما قدر الباك-اند يحدد قصد واضح، command بيضل
    // UnknownCommand زي ما كان، بدون أي تعطّل.
    if (command is UnknownCommand && AppConstants.aiBackendEnabled) {
      final rewrittenText = await _aiCommandRewriter.rewrite(recognizedText);

      if (rewrittenText != null) {
        final rewrittenCommand = parseVoiceCommand(rewrittenText);

        if (rewrittenCommand is! UnknownCommand) {
          debugPrint(
            '🤖 الباك-اند أعاد صياغة الأمر: "$recognizedText" → '
            '"$rewrittenText"',
          );
          command = rewrittenCommand;
        }
      }
    }

    await _executeVoiceCommand(command);

    debugPrint('🔍 النص بعد التطبيع: "${normalizeArabicText(recognizedText)}"');
    debugPrint(
      '🔍 استخراج الاسم: "${englishLabelForArabic(normalizeArabicText(recognizedText))}"',
    );
  }

  Future<void> _onMicPressCancel() async {
    if (!_micPressActive) return;

    _micPressActive = false;
    _micGestureId++;

    await _speech.cancelListening();

    if (mounted) {
      setState(() {
        _isListeningForCommand = false;
      });
    }
  }

  /// ⚠️ صار async — لأنه بعض الحالات (WhatsAround/FindObject) ممكن
  /// تنتظر رد الباك-اند (لو aiBackendEnabled) قبل ما تنطق. باقي
  /// الحالات (StopNavigation/Unknown) ما بتنتظر شي، بترجع فورًا زي
  /// ما كانت دايمًا.
  Future<void> _executeVoiceCommand(VoiceCommand command) async {
    // ⚠️ مقاطعة: لو فيه توجيه شغّال وجاء أمر جديد غير "وقف"، نوقف
    // التوجيه الحالي بهدوء أول (بدون رسالة "تم إلغاء" منفصلة، بس
    // سطر انتقالي قصير)، وبعدين نكمل تنفيذ الأمر الجديد عاديًا —
    // بالضبط سيناريو "وين الباب؟" وانت ماشي للكرسي.
    if (_isNavigating && command is! StopNavigationCommand) {
      if (mounted) {
        setState(() => _navigation.cancelSilently());
      } else {
        _navigation.cancelSilently();
      }

      await _stopCameraIfWeStartedItForNavigation();
      _voice.speakNow('أوقفت التوجيه.');
    }

    switch (command) {
      case FindObjectCommand(:final englishLabel, :final arabicLabel):
        if (!AppConstants.objectMemoryEnabled) {
          _voice.speakNow('ذاكرة الأجسام غير مفعّلة حاليًا');
          return;
        }

        var record = memory.findMostRelevantByLabel(englishLabel);

        // ⚠️ لو المعلومة مو موجودة أصلًا، أو موجودة بس حالتها LOST/
        // ARCHIVED (يعني مو أكيد لسا قدام الكاميرا)، نجرّب دفعة كاميرا
        // قصيرة نبحث فيها عنه تحديدًا قبل ما نستسلم. لو كانت ACTIVE
        // (شفناه مؤخرًا)، منجاوب فورًا من الذاكرة بدون فتح كاميرا —
        // بالضبط الفرق بين حالة 4 وحالة 5 بالسيناريو المتفق عليه.
        if (record == null || record.status != ObjectStatus.active) {
          _voice.speakNow('لحظة، خليني أبحث عن $arabicLabel');
          await _performBurstScan();
          record = memory.findMostRelevantByLabel(englishLabel);
        }

        if (record == null) {
          _voice.speakNow('ما شفت $arabicLabel لسا');
          return;
        }

        final statusHint = record.status == ObjectStatus.lost
            ? ' (آخر مكان شفته فيه)'
            : '';

        final distanceHint = record.distance != null
            ? '، يبعد عنك تقريبًا ${_depth.estimateSteps(record.distance!)} خطوات'
            : '';

        final localSentence =
            '$arabicLabel ${record.arabicDirection}$distanceHint$statusHint';

        if (await _trySpeakViaAi(localSentence)) return;

        _voice.speakNow(localSentence);
        return;

      case WhatsAroundCommand():
        if (!AppConstants.objectMemoryEnabled) {
          _voice.speakNow('ذاكرة الأجسام غير مفعّلة حاليًا');
          return;
        }

        // ⚠️ "شو حولي؟" هو أمر "مسح" (Scan) دايمًا حسب السيناريو —
        // مختلف عن FindObjectCommand اللي بيرجع للذاكرة أول. هون
        // دايمًا نفتح دفعة كاميرا قصيرة نجدد فيها الصورة، لأن قصد
        // المستخدم "شو الوضع الحالي" مو "شو آخر شي شفته".
        _voice.speakNow('لحظة شوي...');
        await _performBurstScan();

        final active = memory.activeRecords;

        if (active.isEmpty) {
          const localSentence = 'ما في شي واضح قدامك حاليًا';

          if (await _trySpeakViaAi(localSentence)) {
            return;
          }

          await _voice.speakNow(localSentence);
          return;
        }

        final localSentence = active
            .map((r) => '${toArabicLabel(r.label)} ${r.arabicDirection}')
            .join('، ');
        debugPrint('📝 شو قدامي: active=${active.length}, '
            'detectionsNow=${_detections.length}, sentence="$localSentence"');

        if (await _trySpeakViaAi(localSentence)) return;

        _voice.speakNow(localSentence);
        return;

      case StopNavigationCommand():
        if (_isNavigating) {
          _cancelNavigation();
        } else {
          _voice.speakNow('ما في توجيه شغّال حاليًا');
        }
        return;

      case NavigateToObjectCommand(:final englishLabel, :final arabicLabel):
        await _startVoiceNavigation(
          englishLabel: englishLabel,
          arabicLabel: arabicLabel,
        );
        return;

      case FreeSpaceQueryCommand():
        if (!_depth.isReady) {
          _voice.speakNow('موديل قياس المسافة غير متوفر بعد');
          return;
        }

        if (_isCheckingFreeSpace) return;

        // ⚠️ ما بنستخدم _requestFreeSpaceCheck() الموجودة (الأزرار
        // اليدوية) مباشرة لأنها بترفض العمل لو الكاميرا مو شغّالة
        // أصلًا (!_isRunning). هون بالعكس: نحط العلمين يدويًا، وبعدين
        // _performBurstScan هي اللي بتشغّل الكاميرا، فأول إطار
        // معالَج جوا _processFrame رح يلاقي _freeSpaceRequested=true
        // وينفّذ التحليل + ينطق النتيجة (نفس منطق _announceFreeSpace
        // الموجود أصلًا، صفر تكرار كود).
        setState(() {
          _freeSpaceRequested = true;
          _isCheckingFreeSpace = true;
        });

        await _performBurstScan();
        return;

      case UnknownCommand():
        _voice.speakNow('ما فهمت الأمر، جرّب تقول: وين الكرسي؟');
        return;
    }
  }

  /// يحاول صياغة رد أطبع عبر الباك-اند (لو aiBackendEnabled) بدل
  /// [localSentence] الثابتة، مستخدمًا بيانات الأجسام الحالية
  /// (_detections بأبعاد آخر إطار). يرجّع true لو نجح ونطق فعليًا —
  /// بهاي الحالة المستدعي ما لازم ينطق localSentence كمان. يرجّع
  /// false لأي سبب (معطّل، فشل اتصال، رد فاضي) — المستدعي وقتها
  /// بينطق localSentence زي ما كان يعمل دايمًا، بدون أي تغيير محسوس
  /// للمستخدم غير جودة الصياغة نفسها.
  Future<bool> _trySpeakViaAi(String localSentence) async {
    if (!AppConstants.aiBackendEnabled) return false;

    final summaries = buildObjectSummaries(
      _detections,
      imageWidth: _imageWidth,
      imageHeight: _imageHeight,
    );

    final composed = await _aiResponseComposer.compose(
      rawText: localSentence, // الجملة الجاهزة من التطبيق، مش كلام المستخدم
      objects: summaries,
    );

    if (composed == null) return false;

    // ⚠️ أولوية للصوت الجاهز من السحابة (Google TTS، أطبع من المحرك
    // المحلي) — لو موجود ونجح تشغيله، خلص. لو الصوت مفقود أو فشل
    // تشغيله رغم وصوله (راجع _playCloudAudio)، ننزل درجة واحدة:
    // ننطق النص المصاغ (composed.reply) بالمحرك المحلي بدل ما نرجع
    // كليًا للجملة الثابتة القديمة — صياغة أطبع حتى بصوت محلي أحسن
    // من ولا شي.
    if (composed.audioBase64 != null) {
      final played = await _playCloudAudio(composed.audioBase64!);
      if (played) return true;
    }

    if (composed.reply != null) {
      await speakAiResponse(_voice, composed.reply!);
      return true;
    }

    return false;
  }

  /// يفكّ [audioBase64] (صوت MP3 من الباك-اند) ويشغّله مباشرة من
  /// الذاكرة (بدون كتابة ملف مؤقت على القرص — أسرع وأنظف). يرجّع
  /// true لو نجح التشغيل فعليًا.
  Future<bool> _playCloudAudio(String audioBase64) async {
    try {
      var cleanBase64 = audioBase64.trim();

      // دعم الردين:
      //
      // 1. Base64 مباشر
      // 2. data:audio/mpeg;base64,....
      if (cleanBase64.startsWith('data:')) {
        final commaIndex = cleanBase64.indexOf(',');

        if (commaIndex != -1) {
          cleanBase64 = cleanBase64.substring(commaIndex + 1);
        }
      }

      if (cleanBase64.isEmpty) {
        debugPrint('⚠️ صوت السحابة فارغ');
        return false;
      }

      final bytes = base64Decode(cleanBase64);

      if (bytes.isEmpty) {
        debugPrint('⚠️ ملف صوت السحابة لا يحتوي بيانات');
        return false;
      }

      await _cloudAudioPlayer.stop();

      await _cloudAudioPlayer.play(BytesSource(bytes, mimeType: 'audio/mpeg'));

      debugPrint(
        '🔊 تم تشغيل الصوت الخارجي بنجاح '
        '(${bytes.length} bytes)',
      );

      return true;
    } catch (e) {
      debugPrint('⚠️ فشل تشغيل صوت السحابة: $e');
      return false;
    }
  }

  /// يُستدعى من صفحة الخريطة: تشغيل/إيقاف الكشف اللحظي من هناك.
  Future<void> _setLiveFromMap(bool live) async {
    if (live == _isRunning) return;
    await _toggleDetection();
  }

  void _requestFreeSpaceCheck() {
    if (!_isRunning || !_depth.isReady || _isCheckingFreeSpace) {
      if (!_depth.isReady) {
        _voice.speakNow('موديل قياس المسافة غير متوفر بعد');
      }
      return;
    }

    setState(() {
      _freeSpaceRequested = true;
      _isCheckingFreeSpace = true;
    });
  }

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

  @override
  void dispose() {
    _boxAnimation.dispose();
    _camera.dispose();
    _cloudAudioPlayer.dispose();
    _detector.dispose();
    _depth.dispose();
    _voice.dispose();
    _gyro.dispose();
    _handTracker.dispose();
    _speech.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.error,
                fontSize: 17,
                height: 1.5,
              ),
            ),
          ),
        ),
      );
    }

    final controller = _camera.controller;

    if (controller == null || !controller.value.isInitialized) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    // الواجهة عربية: نفرض RTL على الشاشة كلها.
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              // ===== الشريط العلوي =====
              HudTopBar(
                voiceEnabled: _voice.enabled,
                languageLabel: _voice.language == SpeechLanguage.arabic
                    ? 'AR'
                    : 'EN',
                canSwitchCamera: widget.cameras.length > 1,
                onBack: () => Navigator.of(context).maybePop(),
                onToggleVoice: _toggleVoice,
                onToggleLanguage: _toggleLanguage,
                onSwitchCamera: _switchCamera,
                onClearMemory: _clearMemory,
              ),

              // ===== إطار الكاميرا =====
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceLowest,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Center(
                          child: AspectRatio(
                            aspectRatio: 1 / controller.value.aspectRatio,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                if (AppConstants.showCameraPreviewForDebug)
                                  CameraPreview(controller)
                                else
                                  Container(color: AppColors.surfaceLowest),
                                ValueListenableBuilder<List<DetectedObject>>(
                                  valueListenable:
                                      _boxAnimation.animatedDetections,
                                  builder: (context, animatedList, _) {
                                    return CustomPaint(
                                      painter: BoundingBoxPainter(
                                        detections: animatedList,
                                        imageWidth: _imageWidth,
                                        imageHeight: _imageHeight,
                                        labelTranslator: toArabicLabel,
                                        proximityLabels: _proximityLabels,
                                        touchedKey: _touchedObjectKey,
                                      ),
                                    );
                                  },
                                ),
                                ValueListenableBuilder<List<HandLandmark>>(
                                  valueListenable:
                                      _boxAnimation.animatedHandPoints,
                                  builder: (context, animatedHandPoints, _) {
                                    return CustomPaint(
                                      painter: HandSkeletonPainter(
                                        landmarks: animatedHandPoints,
                                        imageWidth: _imageWidth,
                                        imageHeight: _imageHeight,
                                        isFist: _isFistForDisplay,
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),

                        // شارات الحالة أعلى الإطار
                        PositionedDirectional(
                          top: 12,
                          start: 12,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              HudStatusPill(
                                label: _isRunning ? 'الكشف يعمل' : 'متوقف',
                                color: _isRunning
                                    ? AppColors.primary
                                    : AppColors.onSurfaceVariant,
                              ),
                              if (_isNavigating) ...[
                                const SizedBox(width: 8),
                                const HudStatusPill(
                                  label: 'التوجيه شغّال',
                                  color: AppColors.tertiary,
                                ),
                              ],
                            ],
                          ),
                        ),

                        // زر فتح خريطة الأجسام (الرادار)
                        PositionedDirectional(
                          top: 8,
                          end: 8,
                          child: HudIconButton(
                            icon: Icons.radar,
                            tooltip: 'خريطة الأجسام',
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => SpatialMapScreen(
                                    memory: memory,
                                    gyro: _gyro,
                                    initialLive: _isRunning,
                                    isLive: () => _isRunning,
                                    onLiveChanged: _setLiveFromMap,
                                    onSpeak: (text) => _voice.speakNow(text),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                        // تلميح حين لا يوجد كشف
                        if (!_isRunning && _detections.isEmpty)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'اضغط «الكشف الحي» للبدء،\nأو اضغط مطوّلًا على المايك واسأل بصوتك',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.onSurfaceVariant,
                                  fontSize: 15,
                                  height: 1.6,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),

              // ===== الأجسام المرصودة =====
              HudObjectsRow(
                detections: _detections,
                labelTranslator: toArabicLabel,
                proximityLabels: _proximityLabels,
                touchedKey: _touchedObjectKey,
              ),

              // ===== لوحة الأمر الصوتي =====
              if (_recognizedSpeechText.isNotEmpty || _isListeningForCommand)
                HudVoicePanel(
                  isListening: _isListeningForCommand,
                  text: _recognizedSpeechText,
                ),

              // ===== بلاطات الإجراءات =====
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: HudActionTile(
                        icon: _isRunning
                            ? Icons.visibility
                            : Icons.visibility_off_outlined,
                        label: 'الكشف الحي',
                        subtitle: _isRunning ? 'نشط' : 'متوقف',
                        active: _isRunning,
                        onPressed: _toggleDetection,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: HudActionTile(
                        icon: Icons.straighten,
                        label: 'قياس العمق',
                        subtitle: 'المسافة',
                        loading: _isMeasuringDistance,
                        dimmed: !_isRunning,
                        onPressed: _isMeasuringDistance
                            ? () {}
                            : _requestDistance,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: HudActionTile(
                        icon: Icons.directions_walk,
                        label: 'مساحة المشي',
                        subtitle: 'هل أقدر أمشي؟',
                        loading: _isCheckingFreeSpace,
                        dimmed: !_isRunning,
                        onPressed: _isCheckingFreeSpace
                            ? () {}
                            : _requestFreeSpaceCheck,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _isNavigating
                          ? HudActionTile(
                              icon: Icons.close,
                              label: 'إلغاء التوجيه',
                              warning: true,
                              onPressed: _cancelNavigation,
                            )
                          : HudActionTile(
                              icon: Icons.near_me,
                              label: 'وجّهني',
                              subtitle: 'نحو جسم',
                              dimmed: _detections.isEmpty,
                              onPressed: _openObjectPicker,
                            ),
                    ),
                  ],
                ),
              ),

              // ===== زر المايك =====
              if (AppConstants.voiceCommandsEnabled)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: HudMicButton(
                    isListening: _isListeningForCommand,
                    isAvailable: _speech.isAvailable,
                    onPressDown: () => _onMicPressDown(),
                    onPressUp: () => _onMicPressUp(),
                    onPressCancel: () => _onMicPressCancel(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// حالة سؤال توضيح صوتي معلّق ("أي كرسي؟ يمين ولا يسار؟"). مرتّبة
/// يسار→يمين دايمًا (راجع _startVoiceNavigation و
/// _resolveDisambiguationAnswer بـ_DetectionScreenState).
class _PendingDisambiguation {
  final List<DetectedObject> candidates;

  const _PendingDisambiguation({required this.candidates});
}
