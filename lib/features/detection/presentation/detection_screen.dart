import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../voice/data/labels_ar.dart';
import '../../voice/services/voice_announcer.dart';
import '../models/detected_object.dart';
import '../services/detector_service.dart';
import '../services/frame_converter.dart';
import 'widgets/bounding_box_painter.dart';
import 'widgets/detection_chips_bar.dart';

/// شاشة الكشف باستخدام الكاميرا.
/// تعرض معاينة حية للكاميرا، وتقوم بكشف الأشياء باستخدام YOLO،
/// وتظهر الصناديق المحيطة والتسميات العربية، بالإضافة إلى شريط الرقائق
/// في الأسفل لعرض الأسماء والنسب المئوية.
class DetectionScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const DetectionScreen({super.key, required this.cameras});

  @override
  State<DetectionScreen> createState() => _DetectionScreenState();
}

class _DetectionScreenState extends State<DetectionScreen> {
  CameraController? _controller;
  final VoiceAnnouncer _voice = VoiceAnnouncer();
  final DetectorService _detector = DetectorService();

  List<DetectedObject> _detections = [];
  int _imageWidth = 0;
  int _imageHeight = 0;

  bool _isRunning = false;
  bool _isProcessingFrame = false;
  int _frameCounter = 0;
  int _camIndex = 0;

  bool _isInitializing = true;
  String? _initError;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _detector.load();
      await _voice.init();
      await _initCamera(_camIndex);
      setState(() => _isInitializing = false);
    } catch (e) {
      setState(() {
        _isInitializing = false;
        _initError = 'فشل تجهيز النظام: $e';
      });
    }
  }

  Future<void> _initCamera(int index) async {
    if (widget.cameras.isEmpty) return;
    final old = _controller;
    _controller = CameraController(
      widget.cameras[index],
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await _controller!.initialize();
    await old?.dispose();
    if (!mounted) return;
    setState(() {});
    if (_isRunning) {
      _controller!.startImageStream(_onFrame);
    }
  }

  Future<void> _switchCamera() async {
    if (widget.cameras.length < 2) return;
    _camIndex = (_camIndex + 1) % widget.cameras.length;
    await _initCamera(_camIndex);
  }

  /// يبدّل لغة النطق بين العربي والإنجليزي — مفيد بالأجهزة اللي ما
  /// عندها محرك نطق عربي مثبَّت (مثل بعض هواتف هواوي بدون خدمات Google).
  Future<void> _toggleVoiceLanguage() async {
    final newLang = _voice.language == SpeechLanguage.arabic
        ? SpeechLanguage.english
        : SpeechLanguage.arabic;
    await _voice.setLanguage(newLang);
    if (mounted) setState(() {});
  }

  void _toggleRunning() {
    if (_isRunning) {
      _controller?.stopImageStream();
      setState(() {
        _isRunning = false;
        _detections = [];
      });
    } else {
      setState(() => _isRunning = true);
      _controller?.startImageStream(_onFrame);
    }
  }

  void _onFrame(CameraImage cameraImage) {
    if (!_isRunning || _isProcessingFrame) return;
    _frameCounter++;
    if (_frameCounter % AppConstants.frameSkip != 0) return;

    _isProcessingFrame = true;
    _processFrame(cameraImage).whenComplete(() {
      _isProcessingFrame = false;
    });
  }

  Future<void> _processFrame(CameraImage cameraImage) async {
    try {
      final sensorOrientation = widget.cameras[_camIndex].sensorOrientation;
      final rotated = sensorOrientation == 90 || sensorOrientation == 270;
      final fullWidth = rotated ? cameraImage.height : cameraImage.width;
      final fullHeight = rotated ? cameraImage.width : cameraImage.height;

      final job = FrameConversionJob(
        yBytes: cameraImage.planes[0].bytes,
        uBytes: cameraImage.planes[1].bytes,
        vBytes: cameraImage.planes[2].bytes,
        width: cameraImage.width,
        height: cameraImage.height,
        yRowStride: cameraImage.planes[0].bytesPerRow,
        uvRowStride: cameraImage.planes[1].bytesPerRow,
        uvPixelStride: cameraImage.planes[1].bytesPerPixel ?? 1,
        sensorOrientation: sensorOrientation,
        targetSize: AppConstants.modelInputSize,
      );

      final converted = await compute(convertCameraFrame, job);

      final results = await _detector.detect(
        converted,
        fullWidth: fullWidth,
        fullHeight: fullHeight,
      );

      if (!mounted) return;
      setState(() {
        _detections = results;
        _imageWidth = fullWidth;
        _imageHeight = fullHeight;
      });
      await _voice.announceIfNeeded(results);

    } catch (e) {
      debugPrint('خطأ في معالجة الإطار: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _detector.dispose();
    _voice.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_initError != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _initError!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),
      );
    }

    if (_controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: Colors.black87,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              child: Row(
                children: [
                  Text(
                    _isRunning ? 'الكشف يعمل' : 'متوقف',
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                  const Spacer(),
                  // زر تبديل لغة النطق (عربي/إنجليزي)
                  TextButton.icon(
                    onPressed: _toggleVoiceLanguage,
                    icon: const Icon(Icons.translate, color: Colors.white, size: 18),
                    label: Text(
                      _voice.language == SpeechLanguage.arabic ? 'AR' : 'EN',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.cameraswitch, color: Colors.white),
                    onPressed: widget.cameras.length > 1 ? _switchCamera : null,
                    tooltip: 'تبديل الكاميرا',
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 1 / _controller!.value.aspectRatio,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CameraPreview(_controller!),
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
        onPressed: _toggleRunning,
        backgroundColor: _isRunning ? Colors.red : Colors.green,
        child: Icon(_isRunning ? Icons.stop : Icons.play_arrow),
      ),
    );
  }
}