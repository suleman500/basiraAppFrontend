import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:projctlitudei/features/detection/presentation/detection_screen.dart';
import 'package:projctlitudei/features/training/presentation/training_screen.dart';
import 'package:projctlitudei/main.dart';
import 'package:video_player/video_player.dart';

class BasiraHomeScreen extends StatefulWidget {
  const BasiraHomeScreen({super.key});

  @override
  State<BasiraHomeScreen> createState() => _BasiraHomeScreenState();
}

class _BasiraHomeScreenState extends State<BasiraHomeScreen>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _videoController;
  bool _videoReady = false;

  static const _backgroundColor = Color(0xff0c1324);
  static const _surfaceColor = Color(0xff151b2d);
  static const _primaryColor = Color(0xffb9c5ff);

  // ===== قياس مواقع الأزرار الفعلية على الشاشة =====
  final GlobalKey _stackKey = GlobalKey();
  final GlobalKey _button1Key = GlobalKey();
  final GlobalKey _button2Key = GlobalKey();

  Offset _button1Center = Offset.zero;
  Offset _button2Center = Offset.zero;
  Size _stackSize = Size.zero;
  bool _positionsReady = false;

  // ===== النقطة المضيئة الوحيدة (رحلة كاملة) =====
  late final Ticker _ticker;
  final ValueNotifier<Offset> _glowPosition = ValueNotifier<Offset>(Offset.zero);

  static const double _orbitRadius = 140;
  static const double _orbitDuration = 5.0;   // مدة الدوران حول كل زر (ثانية)
  static const double _travelDuration = 1.3;  // مدة الانتقال بين المراحل (ثانية)
  static const double _wanderDuration = 6.0;  // مدة التجول العشوائي (ثانية)

  static double get _totalDuration =>
      _orbitDuration * 2 + _travelDuration * 3 + _wanderDuration;

  @override
  void initState() {
    super.initState();
    _initVideo();
    _ticker = createTicker(_onTick)..start();
    WidgetsBinding.instance.addPostFrameCallback((_) => _measurePositions());
  }

  Future<void> _initVideo() async {
    final controller = VideoPlayerController.asset(
      'assets/stitch/basira_space_background.mp4',
    );

    try {
      await controller.initialize();
      controller
        ..setLooping(true)
        ..setVolume(0)
        ..play();

      if (!mounted) {
        controller.dispose();
        return;
      }

      setState(() {
        _videoController = controller;
        _videoReady = true;
      });
    } catch (e) {
      debugPrint('Video background failed to load: $e');
    }
  }

  void _measurePositions() {
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final b1Box = _button1Key.currentContext?.findRenderObject() as RenderBox?;
    final b2Box = _button2Key.currentContext?.findRenderObject() as RenderBox?;
    if (stackBox == null || b1Box == null || b2Box == null) return;

    final b1Global = b1Box.localToGlobal(b1Box.size.center(Offset.zero));
    final b2Global = b2Box.localToGlobal(b2Box.size.center(Offset.zero));

    setState(() {
      _button1Center = stackBox.globalToLocal(b1Global);
      _button2Center = stackBox.globalToLocal(b2Global);
      _stackSize = stackBox.size;
      _positionsReady = true;
    });
  }

  void _onTick(Duration elapsed) {
    if (!_positionsReady) return;
    final totalSeconds = elapsed.inMicroseconds / 1e6;
    final cycleIndex = (totalSeconds / _totalDuration).floor();
    final localT = totalSeconds - cycleIndex * _totalDuration;
    _glowPosition.value = _computeGlowPosition(localT, cycleIndex);
  }

  /// يحسب موقع النقطة المضيئة بناءً على المرحلة الحالية من الرحلة:
  /// دوران حول الزر1 -> انتقال -> دوران حول الزر2 -> انتقال -> تجول عشوائي -> عودة
  Offset _computeGlowPosition(double t, int cycleIndex) {
    double cursor = 0;

    // المرحلة 1: دوران حول الزر الأول
    if (t < cursor + _orbitDuration) {
      final angle = ((t - cursor) / _orbitDuration) * 2 * math.pi;
      return _pointOnOrbit(_button1Center, angle);
    }
    cursor += _orbitDuration;

    // المرحلة 2: انتقال من مدار الزر1 إلى مدار الزر2
    if (t < cursor + _travelDuration) {
      final p = Curves.easeInOut.transform((t - cursor) / _travelDuration);
      final from = _pointOnOrbit(_button1Center, 2 * math.pi);
      final to = _pointOnOrbit(_button2Center, 0);
      return Offset.lerp(from, to, p)!;
    }
    cursor += _travelDuration;

    // المرحلة 3: دوران حول الزر الثاني
    if (t < cursor + _orbitDuration) {
      final angle = ((t - cursor) / _orbitDuration) * 2 * math.pi;
      return _pointOnOrbit(_button2Center, angle);
    }
    cursor += _orbitDuration;

    final waypoints = _wanderWaypoints(cycleIndex);

    // المرحلة 4: انتقال من مدار الزر2 إلى أول نقطة عشوائية
    if (t < cursor + _travelDuration) {
      final p = Curves.easeInOut.transform((t - cursor) / _travelDuration);
      final from = _pointOnOrbit(_button2Center, 2 * math.pi);
      return Offset.lerp(from, waypoints[0], p)!;
    }
    cursor += _travelDuration;

    // المرحلة 5: تجول عشوائي بالشاشة عبر عدة نقاط
    if (t < cursor + _wanderDuration) {
      final localT = t - cursor;
      final segmentDuration = _wanderDuration / (waypoints.length - 1);
      final segmentIndex =
          (localT / segmentDuration).floor().clamp(0, waypoints.length - 2);
      final segmentT =
          ((localT - segmentIndex * segmentDuration) / segmentDuration)
              .clamp(0.0, 1.0);
      final p = Curves.easeInOut.transform(segmentT);
      return Offset.lerp(
        waypoints[segmentIndex],
        waypoints[segmentIndex + 1],
        p,
      )!;
    }
    cursor += _wanderDuration;

    // المرحلة 6: عودة إلى بداية مدار الزر الأول (ثم تعيد الدورة من جديد)
    final p = Curves.easeInOut
        .transform(((t - cursor) / _travelDuration).clamp(0.0, 1.0));
    final from = waypoints.last;
    final to = _pointOnOrbit(_button1Center, 0);
    return Offset.lerp(from, to, p)!;
  }

  Offset _pointOnOrbit(Offset center, double angle) {
    return center +
        Offset(_orbitRadius * math.cos(angle), _orbitRadius * math.sin(angle));
  }

  /// نقاط عشوائية جديدة بكل دورة (ثابتة خلال نفس الدورة عبر الـ seed)
  List<Offset> _wanderWaypoints(int cycleIndex) {
    if (_stackSize.width <= 0 || _stackSize.height <= 0) {
      return const [Offset.zero, Offset.zero, Offset.zero];
    }
    final random = math.Random(cycleIndex * 7919 + 13);
    const margin = 56.0;
    final width = _stackSize.width;
    final height = _stackSize.height;

    Offset randomPoint() => Offset(
          margin + random.nextDouble() * (width - margin * 2),
          margin + random.nextDouble() * (height - margin * 2),
        );

    return [randomPoint(), randomPoint(), randomPoint()];
  }

  @override
  void dispose() {
    _ticker.dispose();
    _glowPosition.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Theme(
      data: theme.copyWith(
        scaffoldBackgroundColor: _backgroundColor,
        colorScheme: theme.colorScheme.copyWith(
          primary: _primaryColor,
          surface: _surfaceColor,
        ),
      ),
      child: Scaffold(
        body: Stack(
          key: _stackKey,
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: _backgroundColor),

            // ===== الخلفية: فيديو متحرك =====
            if (_videoReady && _videoController != null)
              RepaintBoundary(
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _videoController!.value.size.width,
                    height: _videoController!.value.size.height,
                    child: VideoPlayer(_videoController!),
                  ),
                ),
              ),

            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 1.1,
                  colors: [Colors.transparent, Color(0xcc0c1324)],
                  stops: [0.2, 1],
                ),
              ),
            ),

            // ===== الأزرار: ثابتة بالموقع، وظيفية بالكامل =====
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _BasiraActionButton(
                        buttonKey: _button1Key,
                        buttonCenter: _button1Center,
                        glowPosition: _glowPosition,
                        positionsReady: _positionsReady,
                        icon: Icons.photo_camera_outlined,
                        label: 'Camera',
                        onPressed: () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => DetectionScreen(cameras: cameras!),));
                        },
                      ),
                      const SizedBox(height: 48),
                      _BasiraActionButton(
                        buttonKey: _button2Key,
                        buttonCenter: _button2Center,
                        glowPosition: _glowPosition,
                        positionsReady: _positionsReady,
                        icon: Icons.psychology_outlined,
                        label: 'Training',
                        onPressed: () {
                          // TODO: Navigate to Training Screen.
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const TrainingScreen()));
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ===== النقطة المضيئة المتجولة (شكل فقط، لا تستقبل لمس) =====
            ValueListenableBuilder<Offset>(
              valueListenable: _glowPosition,
              builder: (context, pos, _) {
                if (!_positionsReady) return const SizedBox.shrink();
                return Positioned(
                  left: pos.dx - 6,
                  top: pos.dy - 6,
                  child: IgnorePointer(
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xff9fe8ff),
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x8838bdf8),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                          BoxShadow(
                            color: Color(0x4438bdf8),
                            blurRadius: 16,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BasiraActionButton extends StatelessWidget {
  const _BasiraActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.buttonKey,
    required this.buttonCenter,
    required this.glowPosition,
    required this.positionsReady,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final GlobalKey buttonKey;
  final Offset buttonCenter;
  final ValueListenable<Offset> glowPosition;
  final bool positionsReady;

  static const double _buttonSize = 220;
  static const double _maxGlowDistance = 260; // مسافة تلاشي الانعكاس

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      key: buttonKey,
      dimension: _buttonSize,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // ===== الزر الفعلي (وظيفي بالكامل) =====
          Semantics(
            button: true,
            label: label,
            child: Material(
              color: const Color(0xff151b2d),
              shape: const CircleBorder(),
              elevation: 0,
              shadowColor: const Color(0xff38bdf8),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onPressed,
                splashColor: const Color(0x3338bdf8),
                highlightColor: const Color(0x1438bdf8),
                child: Container(
                  height: 150,
                  width: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: const Color(0x3338bdf8)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x2638bdf8),
                        blurRadius: 24,
                        spreadRadius: 2,
                      ),
                      BoxShadow(
                        color: Color(0x1438bdf8),
                        blurRadius: 10,
                        spreadRadius: 8,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, size: 48, color: const Color(0xffdce1fb)),
                      const SizedBox(height: 12),
                      Text(
                        label.toUpperCase(),
                        style: const TextStyle(
                          color: Color(0xffdce1fb),
                          fontFamily: 'Sora',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ===== انعكاس الضوء: شكلي بحت، شدته تعتمد على قرب النقطة =====
          IgnorePointer(
            child: ClipOval(
              child: ValueListenableBuilder<Offset>(
                valueListenable: glowPosition,
                builder: (context, glowPos, _) {
                  if (!positionsReady) return const SizedBox.shrink();
                  final delta = glowPos - buttonCenter;
                  final distance = delta.distance;
                  final angle = math.atan2(delta.dy, delta.dx);
                  final proximity =
                      (1 - (distance / _maxGlowDistance)).clamp(0.0, 1.0);
                  final opacity = 0.32 * math.pow(proximity, 1.6);

                  if (opacity <= 0.01) return const SizedBox.shrink();

                  return Opacity(
                    opacity: opacity.toDouble(),
                    child: Transform.rotate(
                      angle: angle,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          width: _buttonSize * 0.65,
                          height: _buttonSize,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.centerRight,
                              end: Alignment.centerLeft,
                              colors: [Color(0xccdff6ff), Colors.transparent],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}