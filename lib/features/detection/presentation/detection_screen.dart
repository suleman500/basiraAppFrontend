import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../voice/data/labels_ar.dart';
import '../../voice/services/voice_announcer.dart';
import '../models/detected_object.dart';
import '../services/depth_service.dart';
import '../services/detector_service.dart';
import '../services/frame_converter.dart';
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
    extends State<DetectionScreen> {
  CameraController? _controller;
  DepthMap? _lastDepthMap;



  final ObjectMemoryService memory =
  ObjectMemoryService();
  int _processedFrameCounter = 0;
  int _missingDetectionFrames = 0;
  final DetectorService _detector = DetectorService();
  final DepthService _depth = DepthService();
  final VoiceAnnouncer _voice = VoiceAnnouncer();

  List<DetectedObject> _detections = [];

  int _imageWidth = 0;
  int _imageHeight = 0;
  int _cameraIndex = 0;
  int _frameCounter = 0;

  bool _isInitializing = true;
  bool _isRunning = false;
  bool _isProcessingFrame = false;
  String? _error;

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
      await _detector.load();
      await _depth.load();
      await _voice.init();
      await memory.init();

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
      final converted = await compute(
        convertCameraFrame,
        job,
      );

      _processedFrameCounter++;

      // موديل الكشف يعمل في كل إطار تتم معالجته.
      final detectedObjects = await _detector.detect(
        converted,
        fullWidth: fullWidth,
        fullHeight: fullHeight,
      );

      // موديل العمق لا يعمل كل مرة؛ نستخدم آخر خريطة محفوظة.
      final shouldUpdateDepth =
          _lastDepthMap == null ||
              _processedFrameCounter %
                  AppConstants.depthFrameInterval ==
                  0;

      if (shouldUpdateDepth) {
        final newDepthMap = await _depth.predict(converted);

        if (newDepthMap != null) {
          _lastDepthMap = newDepthMap;
        }
      }

      final results = <DetectedObject>[];

      for (final object in detectedObjects) {
        final fingerprint =
        memory.fingerprintFor(
          frame: converted,
          box: object.box,
          fullWidth: fullWidth,
          fullHeight: fullHeight,
        );

        final memoryMatch =
        await memory.remember(
          label: object.label,
          fingerprint: fingerprint,
        );

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
            memoryId: memoryMatch.id,
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

      // ننطق فقط عندما توجد نتيجة كشف جديدة،
      // وليس في كل إطار محفوظ.
      if (results.isNotEmpty) {
        await _voice.announceIfNeeded(displayResults);
      }
    } catch (e) {
      debugPrint('Frame processing error: $e');
    }
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

      final smoothBox = _lerpRect(
        previous.box,
        current.box,
        AppConstants.detectionSmoothing,
      );

      final smoothDistance = _smoothDistance(
        previous.distance,
        current.distance,
      );

      smoothed.add(
        DetectedObject(
          label: current.label,
          confidence: current.confidence,
          box: smoothBox,
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
    _controller?.dispose();
    _detector.dispose();
    _depth.dispose();
    _voice.dispose();
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
        actions: [
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const TrainingScreen(),
                ),
              );
            },
            icon: const Icon(Icons.model_training),
            tooltip: 'Training',
          ),
        ],
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
                      CameraPreview(controller),
                      CustomPaint(
                        painter: BoundingBoxPainter(
                          detections: _detections,
                          imageWidth: _imageWidth,
                          imageHeight: _imageHeight,
                          labelTranslator: toArabicLabel,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            DetectionChipsBar(
              detections: _detections,
              labelTranslator: toArabicLabel,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _toggleDetection,
        backgroundColor:
        _isRunning ? Colors.red : Colors.green,
        child: Icon(
          _isRunning
              ? Icons.stop
              : Icons.play_arrow,
        ),
      ),
    );
  }
}