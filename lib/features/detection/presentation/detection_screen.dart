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
import '../services/hand_tracker_service.dart';
import '../services/native_detector_service.dart';
import '../services/frame_converter.dart';
import '../services/gyroscope_service.dart';
import '../services/speech_service.dart';
import '../services/voice_command_parser.dart';
import 'widgets/bounding_box_painter.dart';
import 'widgets/hand_skeleton_painter.dart';
import 'widgets/detection_chips_bar.dart';
import 'dart:math' as math;
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
  CameraController? _controller;

  DepthMap? _lastDepthMap;

  final ObjectMemoryService memory = ObjectMemoryService();
  int _missingDetectionFrames = 0;
  int _processedFrameCounter = 0;
  final dynamic _detector = AppConstants.useNativeDetector
      ? NativeDetectorService()
      : DetectorService();
  final DepthService _depth = DepthService();
  final VoiceAnnouncer _voice = VoiceAnnouncer();
  final GyroscopeService _gyro = GyroscopeService();
  final HandTrackerService _handTracker = HandTrackerService();
  late final SpeechService _speech = SpeechService(onText: _onSpeechText);

  bool _isListeningForCommand = false;
  bool _micPressActive = false;
  int _micGestureId = 0;
  String _recognizedSpeechText = '';

  List<DetectedObject> _detections = [];

  late final Ticker _boxAnimationTicker;

  final ValueNotifier<List<DetectedObject>> _animatedDetections =
      ValueNotifier<List<DetectedObject>>([]);

  Duration? _lastAnimationTickElapsed;

  final Map<String, int> _detectionStreak = {};

  Map<String, String> _proximityLabels = {};

  int _imageWidth = 0;
  int _imageHeight = 0;
  int _cameraIndex = 0;
  int _frameCounter = 0;

  bool _isInitializing = true;
  bool _isRunning = false;
  bool _isProcessingFrame = false;
  String? _error;

  bool _depthRequested = false;
  bool _isMeasuringDistance = false;

  String? _navigationTargetLabel;

  String? _navigationTargetId;

  bool get _isNavigating => _navigationTargetLabel != null;

  DateTime? _lastNavigationAnnounce;
  DateTime? _lastObstacleWarning;
  DateTime? _lastLostAnnounce;

  String? _touchedObjectKey;

  DateTime? _lastTouchTriggerAt;

  bool _wasFistLastFrame = false;

  List<HandLandmark> _handPointsForDisplay = [];
  bool _isFistForDisplay = false;

  List<HandLandmark> _lastRawHandLandmarks = [];

  final ValueNotifier<List<HandLandmark>> _animatedHandPoints =
      ValueNotifier<List<HandLandmark>>([]);

  @override
  void initState() {
    super.initState();

    _boxAnimationTicker = createTicker(_onBoxAnimationTick)..start();

    _initialize();
  }

  void _onBoxAnimationTick(Duration elapsed) {
    final previousElapsed = _lastAnimationTickElapsed;
    _lastAnimationTickElapsed = elapsed;

    if (previousElapsed == null) return;

    final dtSeconds = (elapsed - previousElapsed).inMicroseconds / 1e6;

    if (dtSeconds <= 0) return;

    final targets = _detections;
    final previousAnimated = _animatedDetections.value;

    if (targets.isEmpty && previousAnimated.isEmpty) return;

    final previousByKey = <String, DetectedObject>{
      for (final obj in previousAnimated) obj.trackingKey: obj,
    };

    final convergence =
        1 - math.exp(-AppConstants.boxAnimationSpeed * dtSeconds);

    final nextAnimated = <DetectedObject>[];
    var anyStillMoving = false;

    for (final target in targets) {
      final previous = previousByKey[target.trackingKey];

      if (previous == null) {
        nextAnimated.add(target);
        anyStillMoving = true;
        continue;
      }

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

      final animatedBox = Rect.lerp(previous.box, target.box, convergence)!;

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

    final boxesConverged =
        !anyStillMoving && previousAnimated.length == nextAnimated.length;

    if (!boxesConverged) {
      _animatedDetections.value = nextAnimated;
    }

    final handTargets = _handPointsForDisplay;
    final previousHandPoints = _animatedHandPoints.value;

    if (handTargets.isEmpty && previousHandPoints.isEmpty) {
      // لا شيء
    } else if (handTargets.length != previousHandPoints.length) {
      _animatedHandPoints.value = handTargets;
    } else {
      final nextHandPoints = <HandLandmark>[];

      for (int i = 0; i < handTargets.length; i++) {
        final target = handTargets[i];
        final previous = previousHandPoints[i];

        nextHandPoints.add(
          HandLandmark(
            x: previous.x + (target.x - previous.x) * convergence,
            y: previous.y + (target.y - previous.y) * convergence,
            z: previous.z + (target.z - previous.z) * convergence,
          ),
        );
      }

      _animatedHandPoints.value = nextHandPoints;
    }
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

    final nextIndex = (_cameraIndex + 1) % widget.cameras.length;

    await _initializeCamera(nextIndex);

    if (!mounted) return;

    if (wasRunning) {
      setState(() {
        _isRunning = true;
      });

      await _controller?.startImageStream(_onFrame);
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
      _touchedObjectKey = null;
      _lastTouchTriggerAt = null;
      _wasFistLastFrame = false;
      _handPointsForDisplay = [];
      _isFistForDisplay = false;
      _animatedHandPoints.value = [];
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
    final frameStopwatch = Stopwatch()..start();

    try {
      final camera = widget.cameras[_cameraIndex];
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

      // كشف اليد متوقف بالكامل حاليًا. لا نكتفي بمنع تحميل النموذج في
      // init؛ هذه الحراسة تمنع أي استدعاء للقناة لو تغيّر ترتيب التهيئة
      // أو أصبح الكاشف جاهزًا من شاشة سابقة. الكود والرسم محفوظان
      // لاستخدام لاحق عندما نعيد AppConstants.handTrackingEnabled إلى true.
      final List<HandLandmark> handLandmarks;
      if (AppConstants.handTrackingEnabled &&
          _handTracker.isReady &&
          _processedFrameCounter % 2 == 0) {
        handLandmarks = await _handTracker.detect(
          converted.rgbBytes,
          width: converted.size,
          height: converted.size,
        );
        _lastRawHandLandmarks = handLandmarks;
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

      Rect? handBox;

      if (handLandmarks.isNotEmpty) {
        double minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0;

        for (final point in handLandmarks) {
          if (point.x < minX) minX = point.x;
          if (point.y < minY) minY = point.y;
          if (point.x > maxX) maxX = point.x;
          if (point.y > maxY) maxY = point.y;
        }

        handBox = Rect.fromLTRB(
          minX * fullWidth,
          minY * fullHeight,
          maxX * fullWidth,
          maxY * fullHeight,
        );
      }

      if (handBox != null) {
        results.removeWhere((obj) {
          if (obj.label != 'person') return false;

          final intersection = obj.box.intersect(handBox!);
          if (intersection.width <= 0 || intersection.height <= 0) {
            return false;
          }

          final overlapArea = intersection.width * intersection.height;
          final handArea = handBox.width * handBox.height;
          if (handArea <= 0) return false;

          final overlapRatio = overlapArea / handArea;
          return overlapRatio > AppConstants.handMisdetectionOverlapThreshold;
        });
      }

      DetectedObject? touchedObject;

      if (handLandmarks.length > 8) {
        final indexFingertip = handLandmarks[8];
        final fingertipPoint = Offset(
          indexFingertip.x * fullWidth,
          indexFingertip.y * fullHeight,
        );

        const touchTolerance = 10.0;

        for (final obj in results) {
          final tolerantBox = obj.box.inflate(touchTolerance);
          if (tolerantBox.contains(fingertipPoint)) {
            touchedObject = obj;
            break;
          }
        }
      }

      if (mounted) {
        setState(() {
          _touchedObjectKey = touchedObject?.trackingKey;
        });
      }

      final isFistNow = _isFistGesture(handLandmarks);

      if (touchedObject != null && isFistNow && !_wasFistLastFrame) {
        final now = DateTime.now();
        final cooldownElapsed =
            _lastTouchTriggerAt == null ||
            now.difference(_lastTouchTriggerAt!) >
                Duration(seconds: AppConstants.touchSelectionCooldownSeconds);

        if (cooldownElapsed) {
          _lastTouchTriggerAt = now;

          _voice.speakNow('${toArabicLabel(touchedObject.label)} — تم التحديد');

          _startNavigation(touchedObject);
        }
      }

      _wasFistLastFrame = isFistNow;

      if (mounted) {
        setState(() {
          _handPointsForDisplay = handLandmarks
              .map(
                (p) => HandLandmark(
                  x: p.x * fullWidth,
                  y: p.y * fullHeight,
                  z: p.z,
                ),
              )
              .toList();
          _isFistForDisplay = isFistNow;
        });
      }

      List<DetectedObject> displayResults;

      if (results.isNotEmpty) {
        _missingDetectionFrames = 0;

        displayResults = _smoothDetections(results);
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
      newLabels[entry.key.label] = category;
    }

    if (mounted) {
      setState(() {
        _proximityLabels = newLabels;
      });
    }

    final nearestLabel = toArabicLabel(withDepth.first.key.label);

    if (withDepth.length == 1) {
      _voice.speakNow('$nearestLabel هو الأقرب إليك');
    } else {
      final secondLabel = toArabicLabel(withDepth[1].key.label);
      _voice.speakNow('الأقرب إليك هو $nearestLabel، وبعده $secondLabel');
    }
  }

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
                  leading: const Icon(Icons.near_me, color: Colors.blueAccent),
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

  bool _isFistGesture(List<HandLandmark> landmarks) {
    if (landmarks.length < 21) return false;

    final wrist = landmarks[0];
    final middleMcp = landmarks[9];

    double distance(HandLandmark a, HandLandmark b) {
      final dx = a.x - b.x;
      final dy = a.y - b.y;
      return math.sqrt(dx * dx + dy * dy);
    }

    final handSize = distance(wrist, middleMcp);
    if (handSize < 1e-6) return false;

    const fingertipIndices = [4, 8, 12, 16, 20];
    double totalDistance = 0;

    for (final index in fingertipIndices) {
      totalDistance += distance(landmarks[index], wrist);
    }

    final averageDistance = totalDistance / fingertipIndices.length;
    final ratio = averageDistance / handSize;

    const fistThreshold = 0.9;
    return ratio < fistThreshold;
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
      if (targetId != null && obj.trackingKey == targetId) {
        target = obj;
        break;
      }
    }

    if (target == null) {
      final now = DateTime.now();

      final canAnnounce =
          _lastLostAnnounce == null ||
          now.difference(_lastLostAnnounce!) >
              Duration(
                seconds: AppConstants.navigationLostAnnounceCooldownSeconds,
              );

      if (canAnnounce) {
        _lastLostAnnounce = now;

        final yaw = _gyro.cumulativeYaw;

        if (yaw.abs() < AppConstants.gyroMinYawToGuessDirection) {
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

    _gyro.resetYaw();

    final heightRatio = target.box.height / fullHeight;

    if (heightRatio >= AppConstants.navigationArrivalBoxHeightRatio) {
      _voice.speakNow('وصلت! ${toArabicLabel(targetLabel)} أمامك مباشرة');

      if (mounted) {
        setState(() {
          _navigationTargetLabel = null;
          _navigationTargetId = null;
        });
      }
      return;
    }

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

      final canWarn =
          _lastObstacleWarning == null ||
          now.difference(_lastObstacleWarning!) >
              Duration(seconds: AppConstants.navigationObstacleCooldownSeconds);

      if (canWarn) {
        _lastObstacleWarning = now;
        _voice.speakNow('انتبه! ${toArabicLabel(obj.label)} أمامك مباشرة');
      }

      break;
    }

    final canAnnounceProgress =
        _lastNavigationAnnounce == null ||
        now.difference(_lastNavigationAnnounce!) >
            Duration(
              seconds: AppConstants.navigationProgressAnnounceCooldownSeconds,
            );

    if (canAnnounceProgress) {
      _lastNavigationAnnounce = now;
      _voice.speakNow('استمر بالمشي');
    }
  }

  /// يُستدعى لحظة ما إصبع المستخدم يلمس زر الميكروفون (onPointerDown
  /// عبر الـListener اللي لافّ الزر بالواجهة). يبدأ جلسة استماع
  /// مستمرة تفضل شغّالة طول ما الإصبع لسا ضاغط — لا نطق تمهيدي هون
  /// عمدًا (زي "تفضّل" بالتصميم القديم)، لأن TTS وSTT بيتنافسوا على
  /// التحكم بالصوت (Audio Focus) بأندرويد، وهالتزامن كان يزيد احتمال
  /// تضارب مع محرك STT، بالإضافة إنه مو ضروري أصلًا — المستخدم نفسه
  /// متحكم بتوقيت الضغط.
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

    // نغيّر الحالة بصريًا فور الضغط، لا بعد انتهاء startListening().
    // هذا يمنع ضغطة الرفع السريعة من أن تضيع قبل وصول Future البدء.
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

    // قد يكون المستخدم رفع إصبعه أثناء مهلة بدء المحرك. في هذه الحالة
    // نغلق أي جلسة فتحت بالخطأ ولا ننتظر ضغطة أخرى لإيقافها.
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

  /// يُستدعى لحظة ما المستخدم يرفع إصبعه عن زر الميكروفون
  /// (onPointerUp) — يوقف الاستماع، ياخذ النص النهائي، ويفسّره وينفّذه
  /// كأمر فورًا.
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

    final command = parseVoiceCommand(recognizedText);
    _executeVoiceCommand(command);

    //  عشان الاختبار
    debugPrint('🔍 النص بعد التطبيع: "${normalizeArabicText(recognizedText)}"');
    debugPrint(
      '🔍 استخراج الاسم: "${englishLabelForArabic(normalizeArabicText(recognizedText))}"',
    );
  }

  /// يُستدعى لو الإصبع انسحب برّة منطقة الزر قبل ما يُرفَع
  /// (onPointerCancel) — نعتبرها "تراجع" عن الأمر، فنلغي الجلسة بدون
  /// تنفيذ أي شي (بعكس onPointerUp اللي دايمًا ينفّذ اللي انسمع).
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

  void _executeVoiceCommand(VoiceCommand command) {
    switch (command) {
      case FindObjectCommand(:final englishLabel, :final arabicLabel):
        if (!AppConstants.objectMemoryEnabled) {
          _voice.speakNow('ذاكرة الأجسام غير مفعّلة حاليًا');
          return;
        }

        final record = memory.findMostRelevantByLabel(englishLabel);

        if (record == null) {
          _voice.speakNow('ما شفت $arabicLabel لسا');
          return;
        }

        final statusHint = record.status == ObjectStatus.lost
            ? ' (آخر مكان شفته فيه)'
            : '';

        _voice.speakNow('$arabicLabel ${record.arabicDirection}$statusHint');
        return;

      case WhatsAroundCommand():
        if (!AppConstants.objectMemoryEnabled) {
          _voice.speakNow('ذاكرة الأجسام غير مفعّلة حاليًا');
          return;
        }

        final active = memory.activeRecords;

        if (active.isEmpty) {
          _voice.speakNow('ما في شي واضح قدامك حاليًا');
          return;
        }

        final sentence = active
            .map((r) => '${toArabicLabel(r.label)} ${r.arabicDirection}')
            .join('، ');

        _voice.speakNow(sentence);
        return;

      case StopNavigationCommand():
        if (_isNavigating) {
          _cancelNavigation();
        } else {
          _voice.speakNow('ما في توجيه شغّال حاليًا');
        }
        return;

      case UnknownCommand():
        _voice.speakNow('ما فهمت الأمر، جرّب تقول: وين الكرسي؟');
        return;
    }
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

  List<DetectedObject> _smoothDetections(List<DetectedObject> incoming) {
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

        final overlap = _boxIou(previous.box, current.box);

        final centerDistance = _centerDistance(previous.box, current.box);

        final allowedDistance = math.max(50.0, previous.box.longestSide * 0.8);

        final isSameObject = overlap > 0.05 || centerDistance < allowedDistance;

        if (!isSameObject) {
          continue;
        }

        final score =
            overlap +
            (1.0 - (centerDistance / (allowedDistance * 2))).clamp(0.0, 1.0);

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

  Rect _lerpRect(Rect oldRect, Rect newRect, double amount) {
    return Rect.fromLTRB(
      oldRect.left + (newRect.left - oldRect.left) * amount,
      oldRect.top + (newRect.top - oldRect.top) * amount,
      oldRect.right + (newRect.right - oldRect.right) * amount,
      oldRect.bottom + (newRect.bottom - oldRect.bottom) * amount,
    );
  }

  double _smoothDistance(double oldDistance, double newDistance) {
    if (newDistance <= 0) {
      return oldDistance;
    }

    if (oldDistance <= 0) {
      return newDistance;
    }

    const newValueWeight = 0.65;
    const oldValueWeight = 0.35;

    return oldDistance * oldValueWeight + newDistance * newValueWeight;
  }

  double _centerDistance(Rect first, Rect second) {
    final dx = first.center.dx - second.center.dx;
    final dy = first.center.dy - second.center.dy;

    return math.sqrt(dx * dx + dy * dy);
  }

  double _boxIou(Rect first, Rect second) {
    final left = math.max(first.left, second.left);

    final top = math.max(first.top, second.top);

    final right = math.min(first.right, second.right);

    final bottom = math.min(first.bottom, second.bottom);

    final intersectionWidth = right - left;
    final intersectionHeight = bottom - top;

    if (intersectionWidth <= 0 || intersectionHeight <= 0) {
      return 0.0;
    }

    final intersectionArea = intersectionWidth * intersectionHeight;

    final firstArea = first.width * first.height;

    final secondArea = second.width * second.height;

    final unionArea = firstArea + secondArea - intersectionArea;

    if (unionArea <= 0) {
      return 0.0;
    }

    return intersectionArea / unionArea;
  }

  @override
  void dispose() {
    _boxAnimationTicker.dispose();
    _animatedDetections.dispose();
    _animatedHandPoints.dispose();
    _controller?.dispose();
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),
      );
    }

    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black87),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: Colors.black87,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Text(
                    _isRunning ? 'الكشف يعمل' : 'متوقف',
                    style: const TextStyle(color: Colors.white),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: _toggleVoice,
                    icon: Icon(
                      _voice.enabled ? Icons.volume_up : Icons.volume_off,
                      color: Colors.white,
                    ),
                    tooltip: _voice.enabled ? 'كتم الصوت' : 'تفعيل الصوت',
                  ),
                  TextButton.icon(
                    onPressed: _toggleLanguage,
                    icon: const Icon(Icons.translate, color: Colors.white),
                    label: Text(
                      _voice.language == SpeechLanguage.arabic ? 'AR' : 'EN',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  IconButton(
                    onPressed: _clearMemory,
                    icon: const Icon(Icons.delete_sweep, color: Colors.white),
                    tooltip: 'مسح ذاكرة الأجسام',
                  ),
                  IconButton(
                    onPressed: widget.cameras.length > 1 ? _switchCamera : null,
                    icon: const Icon(Icons.cameraswitch, color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1 / controller.value.aspectRatio,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (AppConstants.showCameraPreviewForDebug)
                        CameraPreview(controller)
                      else
                        Container(color: Colors.black),
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
                              touchedKey: _touchedObjectKey,
                            ),
                          );
                        },
                      ),
                      ValueListenableBuilder<List<HandLandmark>>(
                        valueListenable: _animatedHandPoints,
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
            ),
            DetectionChipsBar(
              detections: _detections,
              labelTranslator: toArabicLabel,
              proximityLabels: _proximityLabels,
            ),
            if (_recognizedSpeechText.isNotEmpty || _isListeningForCommand)
              Container(
                width: double.infinity,
                constraints: const BoxConstraints(minHeight: 38, maxHeight: 72),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                color: Colors.blueGrey.shade900,
                child: Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    Icon(
                      _isListeningForCommand
                          ? Icons.mic
                          : Icons.record_voice_over,
                      size: 18,
                      color: _isListeningForCommand
                          ? Colors.redAccent
                          : Colors.tealAccent,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _recognizedSpeechText.isEmpty
                            ? 'استمع...'
                            : _recognizedSpeechText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
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
          if (AppConstants.voiceCommandsEnabled) ...[
            // ⚠️ Listener (لا "يبلع" أحداث اللمس، بس يراقبها بالتوازي
            // مع الزر) يلتقط لحظة الضغط ولحظة الرفع بالضبط — أدق من
            // FloatingActionButton.onPressed العادي (اللي بس يعرف
            // "انضغط" ككل، مو "متى ضُغط" و"متى اتُرفع" منفصلين).
            // onPressed هون فارغ عمدًا (بس حتى يبان الزر "مفعّل"
            // بصريًا بلونه الكامل) — كل المنطق الفعلي بالـListener.
            Listener(
              onPointerDown: (_) => _onMicPressDown(),
              onPointerUp: (_) => _onMicPressUp(),
              onPointerCancel: (_) => _onMicPressCancel(),
              child: FloatingActionButton(
                heroTag: 'voice_command_fab',
                onPressed: () {},
                backgroundColor: _isListeningForCommand
                    ? Colors.redAccent
                    : (_speech.isAvailable ? Colors.teal : Colors.grey),
                tooltip: 'اضغط مطوّلًا واسأل بصوتك',
                child: const Icon(Icons.mic, color: Colors.white),
              ),
            ),
            const SizedBox(width: 12),
          ],
          if (_isRunning) ...[
            FloatingActionButton(
              heroTag: 'distance_fab',
              onPressed: _isMeasuringDistance ? null : _requestDistance,
              backgroundColor: _depth.isReady ? Colors.blueAccent : Colors.grey,
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
            backgroundColor: _isRunning ? Colors.red : Colors.green,
            child: Icon(_isRunning ? Icons.stop : Icons.play_arrow),
          ),
        ],
      ),
    );
  }
}
