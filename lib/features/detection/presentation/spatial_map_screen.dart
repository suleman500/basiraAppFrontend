import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:projctlitudei/core/theme/app_colors.dart';

import '../../../core/constants.dart';
import '../../voice/data/labels_ar.dart';
import '../services/gyroscope_service.dart';
import '../services/object_memory_service.dart';
import 'widgets/hud_widgets.dart';

/// صفحة "الملاحة المكانية": رادار يرسم الأجسام **المحفوظة** حول المستخدم.
///
/// - الافتراضي: الخريطة ثابتة من الأجسام المحفوظة سابقًا (بدون كشف لحظي).
/// - زر "الكشف اللحظي": يشغّل الكاميرا فتُضاف الأجسام الجديدة للخريطة فورًا.
/// - كل جسم يُرسم باتجاهه الحقيقي (أمام/جانب/خلف) اعتمادًا على
///   الجيروسكوب + البوصلة، والخريطة تدور مع دوران الهاتف (الأمام للأعلى).
/// - أزرار + / − وقرص الأصبعين للتقريب، وسحب الأصبع لتحريك الخريطة.
class SpatialMapScreen extends StatefulWidget {
  const SpatialMapScreen({
    super.key,
    required this.memory,
    this.gyro,
    this.onSpeak,
    this.onLiveChanged,
    this.isLive,
    this.initialLive = false,
  });

  final ObjectMemoryService memory;

  /// مصدر اتجاه الهاتف. بدونه تُرسم الخريطة بوضع "الشمال للأعلى" بدون دوران.
  final GyroscopeService? gyro;

  /// لنطق الإرشاد الصوتي (مثلًا: (t) => _voice.speakNow(t)).
  final void Function(String text)? onSpeak;

  /// تشغيل/إيقاف الكشف اللحظي (تنفّذه شاشة الكشف لأنها صاحبة الكاميرا).
  final Future<void> Function(bool live)? onLiveChanged;

  /// الحالة الفعلية للكشف بعد محاولة التبديل.
  final bool Function()? isLive;

  final bool initialLive;

  @override
  State<SpatialMapScreen> createState() => _SpatialMapScreenState();
}

class _SpatialMapScreenState extends State<SpatialMapScreen> {
  /// المدى الظاهر بدون تقريب (متر).
  static const double _baseRange = 5.0;

  /// أقصى مسافة تُرسم (أبعد من ذلك تُقصّ).
  static const double _dataMax = 10.0;

  /// طول الخطوة التقريبي لتحويل المسافة إلى خطوات.
  static const double _stepMeters = 0.7;

  static const double _minZoom = 0.5;
  static const double _maxZoom = 8.0;

  /// زاوية مجال رؤية الكاميرا (للمخروط المرسوم).
  static const double _fov = 0.96;

  Timer? _liveTimer;
  Timer? _headingTimer;
  final ValueNotifier<double> _heading = ValueNotifier<double>(0);

  late bool _live = widget.initialLive;
  bool _togglingLive = false;

  List<_MapObject> _objects = const [];
  String? _targetId;

  double _zoom = 1.0;
  double _baseZoom = 1.0;
  Offset _pan = Offset.zero;
  double _radarSize = 320;

  @override
  void initState() {
    super.initState();

    _objects = _collect();

    // دوران الخريطة مع الهاتف (خفيف، لا علاقة له بالكشف).
    _headingTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
      final h = widget.gyro?.heading ?? 0.0;
      if ((h - _heading.value).abs() > 0.012) _heading.value = h;
    });
    _heading.value = widget.gyro?.heading ?? 0.0;

    // الخريطة لا تتحدث إلا بالوضع اللحظي.
    _liveTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_live && mounted) {
        setState(() => _objects = _collect());
      }
    });
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _headingTimer?.cancel();
    _heading.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------
  // الكشف اللحظي
  // ---------------------------------------------------------------

  Future<void> _toggleLive() async {
    if (_togglingLive || widget.onLiveChanged == null) return;

    final want = !_live;
    setState(() {
      _togglingLive = true;
      _live = want;
    });

    await widget.onLiveChanged!(want);

    if (!mounted) return;
    setState(() {
      _live = widget.isLive?.call() ?? want;
      _togglingLive = false;
      _objects = _collect();
    });
  }

  // ---------------------------------------------------------------
  // البيانات
  // ---------------------------------------------------------------

  ObjectStatus _statusOf(ObjectMemoryRecord r, DateTime now) {
    final elapsed = now.difference(r.lastSeenAt).inSeconds;
    if (elapsed > AppConstants.objectArchivedAfterSeconds) {
      return ObjectStatus.archived;
    }
    if (elapsed > AppConstants.objectLostAfterSeconds) {
      return ObjectStatus.lost;
    }
    return ObjectStatus.active;
  }

  List<_MapObject> _collect() {
    final now = DateTime.now();
    final bySlot = <HorizontalPosition, List<ObjectMemoryRecord>>{};

    for (final r in widget.memory.allRecords) {
      // الأجسام المؤرشفة (غابت لفترة طويلة جدًا) لا تُرسم.
      if (_statusOf(r, now) == ObjectStatus.archived) continue;
      bySlot.putIfAbsent(r.horizontalPosition, () => []).add(r);
    }

    final result = <_MapObject>[];

    bySlot.forEach((slot, list) {
      list.sort((a, b) => a.id.compareTo(b.id));

      // للسجلات القديمة بدون اتجاه مطلق: نرسمها بالمنطقة فقط (تقريبي).
      final base = switch (slot) {
        HorizontalPosition.left => -0.52,
        HorizontalPosition.center => 0.0,
        HorizontalPosition.right => 0.52,
      };

      for (var k = 0; k < list.length; k++) {
        final r = list[k];
        final jitter = list.length == 1 ? 0.0 : ((k % 3) - 1) * 0.16;

        final hasDistance = r.distance != null && r.distance! > 0;
        final raw = hasDistance ? r.distance! : 2.5 + (k ~/ 3) * 0.4;

        result.add(
          _MapObject(
            record: r,
            status: _statusOf(r, now),
            bearing: r.bearing,
            fallbackAngle: base + jitter,
            plotDistance: raw.clamp(0.3, _dataMax).toDouble(),
            hasDistance: hasDistance,
          ),
        );
      }
    });

    return result;
  }

  List<_MapObject> _byDistance(List<_MapObject> objects) {
    return [...objects]..sort((a, b) {
      if (a.isLost != b.isLost) return a.isLost ? 1 : -1;
      return a.plotDistance.compareTo(b.plotDistance);
    });
  }

  _MapObject? _targetOf(List<_MapObject> objects) {
    if (objects.isEmpty) return null;
    for (final o in objects) {
      if (o.id == _targetId) return o;
    }
    return _byDistance(objects).first;
  }

  void _cycleTarget(List<_MapObject> objects, _MapObject? current) {
    if (objects.isEmpty) return;
    final sorted = _byDistance(objects);
    final index = sorted.indexWhere((o) => o.id == current?.id);
    final next = sorted[(index + 1) % sorted.length];
    setState(() => _targetId = next.id);
  }

  // ---------------------------------------------------------------
  // التقريب والتحريك
  // ---------------------------------------------------------------

  void _setZoom(double z) {
    setState(() => _zoom = z.clamp(_minZoom, _maxZoom).toDouble());
  }

  void _resetView() {
    setState(() {
      _zoom = 1.0;
      _pan = Offset.zero;
    });
  }

  /// يقرّب ويحرّك الخريطة بحيث يصير الهدف في المنتصف.
  void _focusTarget(_MapObject? target) {
    if (target == null) return;

    const newZoom = 3.0;
    final plotRadius = _radarSize / 2 - 44;
    final rel = target.angleAt(_heading.value);
    final r = plotRadius * (target.plotDistance / (_baseRange / newZoom));
    final v = Offset(math.sin(rel), -math.cos(rel)) * r;

    setState(() {
      _zoom = newZoom;
      _pan = -v;
    });
  }

  // ---------------------------------------------------------------
  // نصوص مساعدة
  // ---------------------------------------------------------------

  /// زاوية بين -π و π (موجب = يمين).
  double _normPi(double a) {
    var v = a % (2 * math.pi);
    if (v < 0) v += 2 * math.pi;
    if (v > math.pi) v -= 2 * math.pi;
    return v;
  }

  String _directionText(double rel) {
    final deg = _normPi(rel) * 180 / math.pi;
    final a = deg.abs();
    if (a <= 20) return 'أمامك مباشرة';
    if (a >= 150) return 'خلفك';
    if (a < 70) return deg > 0 ? 'أمامك على يمينك' : 'أمامك على يسارك';
    if (a <= 110) return deg > 0 ? 'على يمينك' : 'على يسارك';
    return deg > 0 ? 'خلفك على اليمين' : 'خلفك على اليسار';
  }

  String _shortDirection(double rel) {
    final deg = _normPi(rel) * 180 / math.pi;
    final a = deg.abs();
    if (a <= 20) return 'أمامك';
    if (a >= 150) return 'خلفك';
    return deg > 0 ? 'يمين' : 'يسار';
  }

  int _stepsOf(_MapObject o) =>
      math.max(1, (o.record.distance! / _stepMeters).round());

  String _guidanceText(_MapObject o, double heading) {
    final label = toArabicLabel(o.record.label);
    final distanceHint =
    o.hasDistance ? '، يبعد تقريبًا ${_stepsOf(o)} خطوات' : '';
    final lostHint = o.isLost ? ' (آخر مكان شفته فيه)' : '';
    return '$label ${_directionText(o.angleAt(heading))}'
        '$distanceHint$lostHint';
  }

  String _ago(DateTime t) {
    final s = DateTime.now().difference(t).inSeconds;
    if (s < 10) return 'الآن';
    if (s < 60) return 'منذ $s ثانية';
    final m = s ~/ 60;
    if (m < 60) return 'منذ $m دقيقة';
    return 'منذ ${m ~/ 60} ساعة';
  }

  // ---------------------------------------------------------------
  // الواجهة
  // ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: ValueListenableBuilder<double>(
            valueListenable: _heading,
            builder: (context, heading, _) => _buildPage(heading),
          ),
        ),
      ),
    );
  }

  Widget _buildPage(double heading) {
    final objects = _objects;
    final target = _targetOf(objects);
    final activeCount = objects.where((o) => !o.isLost).length;
    final hasCompass = widget.gyro?.hasCompass ?? false;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // ===== العنوان =====
        Row(
          children: [
            HudIconButton(
              icon: Icons.arrow_back,
              tooltip: 'رجوع',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'الملاحة المكانية',
                style: TextStyle(
                  color: AppColors.onSurface,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            HudStatusPill(
              label: _live ? 'كشف لحظي' : 'محفوظات',
              color: _live ? AppColors.primary : AppColors.onSurfaceVariant,
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ===== زر الكشف اللحظي =====
        if (widget.onLiveChanged != null) ...[
          _LiveToggle(
            live: _live,
            busy: _togglingLive,
            onTap: _toggleLive,
          ),
          const SizedBox(height: 12),
        ],

        // ===== الرادار =====
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.radar, size: 20, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${objects.length} أجسام محفوظة ($activeCount حديثة)',
                      style: const TextStyle(
                        color: AppColors.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '×${_zoom.toStringAsFixed(1)}',
                    style: const TextStyle(
                      color: AppColors.secondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (widget.gyro != null && !hasCompass) ...[
                const SizedBox(height: 6),
                const Text(
                  'البوصلة غير متوفرة — الاتجاهات نسبية لبداية التشغيل (جيروسكوب فقط).',
                  style: TextStyle(color: AppColors.tertiary, fontSize: 12),
                ),
              ],
              const SizedBox(height: 12),
              if (objects.isEmpty)
                const _EmptyMap()
              else
                LayoutBuilder(
                  builder: (context, c) {
                    final size = c.maxWidth;
                    _radarSize = size;

                    return SizedBox(
                      width: size,
                      height: size,
                      child: Stack(
                        children: [
                          // الرادار + إيماءات التقريب والتحريك
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onScaleStart: (_) => _baseZoom = _zoom,
                                onScaleUpdate: (d) {
                                  setState(() {
                                    _zoom = (_baseZoom * d.scale)
                                        .clamp(_minZoom, _maxZoom)
                                        .toDouble();
                                    final limit = size * 0.8;
                                    _pan = Offset(
                                      (_pan.dx + d.focalPointDelta.dx)
                                          .clamp(-limit, limit)
                                          .toDouble(),
                                      (_pan.dy + d.focalPointDelta.dy)
                                          .clamp(-limit, limit)
                                          .toDouble(),
                                    );
                                  });
                                },
                                child: _RadarView(
                                  size: size,
                                  objects: objects,
                                  targetId: target?.id,
                                  heading: heading,
                                  zoom: _zoom,
                                  pan: _pan,
                                  baseRange: _baseRange,
                                  fov: _fov,
                                  labelOf: (o) {
                                    final name = toArabicLabel(o.record.label);
                                    return o.hasDistance
                                        ? '$name • ${o.record.distance!.toStringAsFixed(1)}م'
                                        : name;
                                  },
                                  directionOf: (o) =>
                                      _directionText(o.angleAt(heading)),
                                  onSelect: (id) =>
                                      setState(() => _targetId = id),
                                ),
                              ),
                            ),
                          ),

                          // أزرار التقريب
                          PositionedDirectional(
                            top: 0,
                            end: 0,
                            child: Column(
                              children: [
                                HudIconButton(
                                  icon: Icons.add,
                                  tooltip: 'تقريب',
                                  onPressed: () => _setZoom(_zoom * 1.6),
                                ),
                                const SizedBox(height: 6),
                                HudIconButton(
                                  icon: Icons.remove,
                                  tooltip: 'تبعيد',
                                  onPressed: () => _setZoom(_zoom / 1.6),
                                ),
                                const SizedBox(height: 6),
                                HudIconButton(
                                  icon: Icons.gps_fixed,
                                  tooltip: 'تركيز على الهدف',
                                  color: AppColors.secondary,
                                  onPressed: () => _focusTarget(target),
                                ),
                                const SizedBox(height: 6),
                                HudIconButton(
                                  icon: Icons.center_focus_strong,
                                  tooltip: 'إعادة العرض',
                                  onPressed: _resetView,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // ===== المفتاح =====
        const _Legend(),
        const SizedBox(height: 14),

        if (target != null) ...[
          // ===== بطاقة الهدف =====
          _Card(
            highlighted: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.graphic_eq,
                      size: 18,
                      color: AppColors.secondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'الهدف: ${toArabicLabel(target.record.label)}',
                      style: const TextStyle(
                        color: AppColors.secondary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '“${_guidanceText(target, heading)}”',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    height: 1.6,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _WideButton(
                        label: 'إعادة الإرشاد الصوتي',
                        icon: Icons.replay,
                        filled: true,
                        onTap: () => widget.onSpeak?.call(
                          _guidanceText(target, _heading.value),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _WideButton(
                        label: 'تبديل الهدف',
                        icon: Icons.swap_horiz,
                        onTap: () => _cycleTarget(objects, target),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // ===== الأرقام =====
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  title: 'المسافة للهدف',
                  value: target.hasDistance
                      ? target.record.distance!.toStringAsFixed(1)
                      : '—',
                  unit: 'متر',
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCard(
                  title: 'خطوات المشي',
                  value: target.hasDistance ? '${_stepsOf(target)}' : '—',
                  unit: 'خطوات',
                  color: AppColors.secondary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCard(
                  title: 'الاتجاه',
                  value: _shortDirection(target.angleAt(heading)),
                  unit:
                  '${(_normPi(target.angleAt(heading)).abs() * 180 / math.pi).round()}°',
                  color: AppColors.tertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
        ],

        // ===== السجل =====
        if (objects.isNotEmpty) ...[
          const Text(
            'سجل الأجسام المحفوظة',
            style: TextStyle(
              color: AppColors.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          ...(([...objects]..sort(
                (a, b) =>
                b.record.lastSeenAt.compareTo(a.record.lastSeenAt),
          ))
              .take(6)
              .map(
                (o) => _LogRow(
              title: toArabicLabel(o.record.label),
              subtitle: [
                _directionText(o.angleAt(heading)),
                if (o.hasDistance)
                  'المسافة ${o.record.distance!.toStringAsFixed(1)} متر',
              ].join(' • '),
              time: _ago(o.record.lastSeenAt),
              lost: o.isLost,
            ),
          )),
        ],
      ],
    );
  }
}

// =====================================================================
// نموذج نقطة على الخريطة
// =====================================================================

class _MapObject {
  const _MapObject({
    required this.record,
    required this.status,
    required this.bearing,
    required this.fallbackAngle,
    required this.plotDistance,
    required this.hasDistance,
  });

  final ObjectMemoryRecord record;
  final ObjectStatus status;

  /// الاتجاه المطلق المحفوظ (راديان) — null للسجلات القديمة.
  final double? bearing;

  /// زاوية تقريبية (نسبةً للأمام) تُستخدم فقط عند غياب [bearing].
  final double fallbackAngle;

  /// المسافة المستخدمة للرسم (متر).
  final double plotDistance;

  /// هل المسافة مقاسة فعلًا أم افتراضية للرسم فقط.
  final bool hasDistance;

  String get id => record.id;
  bool get isLost => status != ObjectStatus.active;

  /// الزاوية على الشاشة (0 = للأعلى/أمامك، موجب = يمين) بالنسبة لاتجاه
  /// الهاتف الحالي [heading].
  double angleAt(double heading) =>
      bearing != null ? bearing! - heading : fallbackAngle;
}

// =====================================================================
// الرادار
// =====================================================================

class _ChipSpec {
  _ChipSpec({
    required this.object,
    required this.point,
    required this.rect,
    required this.text,
    required this.isTarget,
    required this.shifted,
  });

  final _MapObject object;
  final Offset point;
  final Rect rect;
  final String text;
  final bool isTarget;
  final bool shifted;
}

class _RadarView extends StatelessWidget {
  const _RadarView({
    required this.size,
    required this.objects,
    required this.targetId,
    required this.heading,
    required this.zoom,
    required this.pan,
    required this.baseRange,
    required this.fov,
    required this.labelOf,
    required this.directionOf,
    required this.onSelect,
  });

  final double size;
  final List<_MapObject> objects;
  final String? targetId;
  final double heading;
  final double zoom;
  final Offset pan;
  final double baseRange;
  final double fov;
  final String Function(_MapObject) labelOf;
  final String Function(_MapObject) directionOf;
  final void Function(String id) onSelect;

  @override
  Widget build(BuildContext context) {
    final center = Offset(size / 2, size / 2) + pan;
    final plotRadius = size / 2 - 44;
    final visibleRange = baseRange / zoom;

    Offset pointOf(_MapObject o) {
      final rel = o.angleAt(heading);
      final r = plotRadius * (o.plotDistance / visibleRange);
      return center + Offset(math.sin(rel), -math.cos(rel)) * r;
    }

    // الأجسام داخل حدود المربع فقط.
    final bounds = Rect.fromLTWH(-10, -10, size + 20, size + 20);
    final visible = <_MapObject, Offset>{};
    for (final o in objects) {
      final p = pointOf(o);
      if (bounds.contains(p)) visible[o] = p;
    }

    // ترتيب وضع الأسماء: الهدف أولًا ثم الأقرب، مع فك التراكب رأسيًا.
    final order = visible.keys.toList()
      ..sort((a, b) {
        final ta = a.id == targetId ? 0 : 1;
        final tb = b.id == targetId ? 0 : 1;
        if (ta != tb) return ta.compareTo(tb);
        return a.plotDistance.compareTo(b.plotDistance);
      });

    final placed = <Rect>[];
    final chips = <_ChipSpec>[];

    for (final o in order) {
      final p = visible[o]!;
      final isTarget = o.id == targetId;
      final text = labelOf(o) + (o.isLost ? ' (خارج الرؤية)' : '');
      final w = 26.0 + text.length * (isTarget ? 7.4 : 6.4);
      final h = isTarget ? 30.0 : 26.0;

      var rect = Rect.fromLTWH(p.dx - w / 2, p.dy - 14 - h, w, h);
      var shifted = false;

      for (var k = 0; k < 6; k++) {
        final candidate = rect.shift(Offset(0, -(h + 4) * k));
        if (!placed.any((r) => r.overlaps(candidate.inflate(1)))) {
          rect = candidate;
          shifted = k > 0;
          break;
        }
        rect = candidate;
        shifted = true;
      }

      placed.add(rect);
      chips.add(
        _ChipSpec(
          object: o,
          point: p,
          rect: rect,
          text: text,
          isTarget: isTarget,
          shifted: shifted,
        ),
      );
    }

    // الهدف يُرسم أخيرًا فوق الباقي.
    final drawOrder = [...chips].reversed.toList();

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _RadarPainter(
                center: center,
                ringRadius: size / 2 - 8,
                visibleRange: visibleRange,
                fov: fov,
              ),
            ),
          ),

          // خطوط توصل الاسم المُزاح بنقطته
          Positioned.fill(
            child: CustomPaint(
              painter: _LinesPainter(
                [
                  for (final c in chips)
                    if (c.shifted) (c.point, c.rect.bottomCenter),
                ],
              ),
            ),
          ),

          // المستخدم (سهم الملاحة — الأمام دائمًا للأعلى)
          Positioned(
            left: center.dx - 18,
            top: center.dy - 18,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.secondary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.secondary.withValues(alpha: 0.5),
                    blurRadius: 16,
                  ),
                ],
              ),
              child: const Icon(
                Icons.navigation,
                size: 22,
                color: AppColors.onPrimary,
              ),
            ),
          ),
          Positioned(
            left: center.dx - 30,
            top: center.dy + 22,
            width: 60,
            child: const Text(
              'موقعك',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.onSurface,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

          // النقاط
          for (final c in drawOrder) _dot(c),

          // الأسماء
          for (final c in drawOrder) _chip(c),
        ],
      ),
    );
  }

  Widget _chip(_ChipSpec c) {
    final color =
    c.object.isLost ? AppColors.tertiary : AppColors.primary;

    return Positioned(
      left: c.rect.center.dx,
      top: c.rect.top,
      child: FractionalTranslation(
        translation: const Offset(-0.5, 0),
        child: IgnorePointer(
          child: Container(
            height: c.rect.height,
            padding: EdgeInsets.symmetric(horizontal: c.isTarget ? 12 : 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surfaceLowest.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: c.isTarget
                    ? AppColors.secondary
                    : color.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (c.isTarget) ...[
                  const Icon(
                    Icons.navigation,
                    size: 14,
                    color: AppColors.secondary,
                  ),
                  const SizedBox(width: 4),
                ],
                Text(
                  c.text,
                  maxLines: 1,
                  style: TextStyle(
                    color: AppColors.onSurface,
                    fontSize: c.isTarget ? 13 : 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dot(_ChipSpec c) {
    final o = c.object;
    final color = o.isLost ? AppColors.tertiary : AppColors.primary;
    final dotSize = c.isTarget ? 20.0 : 14.0;

    return Positioned(
      left: c.point.dx - 22,
      top: c.point.dy - 22,
      width: 44,
      height: 44,
      child: Semantics(
        button: true,
        label: '${labelOf(o)}، ${directionOf(o)}',
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onSelect(o.id),
          child: Center(
            child: Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: c.isTarget
                    ? Border.all(color: AppColors.secondary, width: 3)
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.6),
                    blurRadius: 12,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.center,
    required this.ringRadius,
    required this.visibleRange,
    required this.fov,
  });

  final Offset center;
  final double ringRadius;
  final double visibleRange;
  final double fov;

  @override
  void paint(Canvas canvas, Size size) {
    final c = center;
    final radius = ringRadius;

    // مجال رؤية الكاميرا (مخروط للأمام)
    final wedge = Path()
      ..moveTo(c.dx, c.dy)
      ..arcTo(
        Rect.fromCircle(center: c, radius: radius),
        -math.pi / 2 - fov / 2,
        fov,
        false,
      )
      ..close();
    canvas.drawPath(
      wedge,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.secondary.withValues(alpha: 0.30),
            AppColors.secondary.withValues(alpha: 0.02),
          ],
        ).createShader(Rect.fromCircle(center: c, radius: radius)),
    );

    // الحلقات
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.14);

    for (final f in const [0.25, 0.5, 0.75, 1.0]) {
      canvas.drawCircle(c, radius * f, ringPaint);

      final tp = TextPainter(
        text: TextSpan(
          text: '${(visibleRange * f).toStringAsFixed(1)}م',
          style: const TextStyle(
            color: AppColors.onSurfaceVariant,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(c.dx + 4, c.dy - radius * f - tp.height - 1));
    }

    // خطوط التقاطع المتقطعة
    final dashPaint = Paint()
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.18);
    _dashed(canvas, Offset(c.dx, c.dy - radius), Offset(c.dx, c.dy + radius),
        dashPaint);
    _dashed(canvas, Offset(c.dx - radius, c.dy), Offset(c.dx + radius, c.dy),
        dashPaint);
  }

  void _dashed(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 6.0;
    const gap = 6.0;
    final total = (b - a).distance;
    if (total == 0) return;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      canvas.drawLine(a + dir * d, a + dir * math.min(d + dash, total), paint);
      d += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) =>
      old.center != center ||
          old.ringRadius != ringRadius ||
          old.visibleRange != visibleRange ||
          old.fov != fov;
}

class _LinesPainter extends CustomPainter {
  _LinesPainter(this.lines);

  final List<(Offset, Offset)> lines;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 1
      ..color = Colors.white.withValues(alpha: 0.35);
    for (final l in lines) {
      canvas.drawLine(l.$1, l.$2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LinesPainter old) => true;
}

// =====================================================================
// عناصر صغيرة
// =====================================================================

class _LiveToggle extends StatelessWidget {
  const _LiveToggle({
    required this.live,
    required this.busy,
    required this.onTap,
  });

  final bool live;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = live ? AppColors.onPrimary : AppColors.onSurface;

    return Semantics(
      button: true,
      toggled: live,
      label: live ? 'الكشف اللحظي يعمل، اضغط للإيقاف' : 'تشغيل الكشف اللحظي',
      excludeSemantics: true,
      child: Material(
        color: live ? AppColors.primary : AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: busy ? null : onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: live ? Colors.transparent : AppColors.glassBorder,
              ),
            ),
            child: Row(
              children: [
                busy
                    ? SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: fg,
                  ),
                )
                    : Icon(
                  live ? Icons.sensors : Icons.sensors_off,
                  size: 30,
                  color: live ? AppColors.onPrimary : AppColors.primary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        live ? 'الكشف اللحظي: يعمل' : 'الكشف اللحظي: متوقف',
                        style: TextStyle(
                          color: fg,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        live
                            ? 'الأجسام الجديدة تُضاف للخريطة فورًا'
                            : 'الخريطة من الأجسام المحفوظة سابقًا فقط',
                        style: TextStyle(
                          color: fg.withValues(alpha: 0.8),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  live ? Icons.toggle_on : Icons.toggle_off,
                  size: 44,
                  color: fg,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child, this.highlighted = false});

  final Widget child;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: highlighted
              ? AppColors.primary.withValues(alpha: 0.35)
              : AppColors.glassBorder,
        ),
      ),
      child: child,
    );
  }
}

class _EmptyMap extends StatelessWidget {
  const _EmptyMap();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48, horizontal: 12),
      child: Center(
        child: Text(
          'لا توجد أجسام محفوظة بعد.\nشغّل «الكشف اللحظي» وجّه الكاميرا حولك، وسأرسمها هنا باتجاهاتها.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.onSurfaceVariant,
            fontSize: 15,
            height: 1.7,
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  Widget _item(Color color, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(
        text,
        style: const TextStyle(
          color: AppColors.onSurfaceVariant,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _item(AppColors.primary, 'مرصود حديثًا'),
          _item(AppColors.tertiary, 'محفوظ سابقًا'),
          _item(AppColors.secondary, 'الهدف / موقعك'),
        ],
      ),
    );
  }
}

class _WideButton extends StatelessWidget {
  const _WideButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? AppColors.onPrimary : AppColors.secondary;

    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: filled ? AppColors.primary : AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: filled ? Colors.transparent : AppColors.glassBorder,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: fg),
                const SizedBox(width: 6),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      style: TextStyle(
                        color: fg,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.unit,
    required this.color,
  });

  final String title;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              title,
              style: const TextStyle(
                color: AppColors.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 30,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              unit,
              style: const TextStyle(
                color: AppColors.onSurface,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({
    required this.title,
    required this.subtitle,
    required this.time,
    required this.lost,
  });

  final String title;
  final String subtitle;
  final String time;
  final bool lost;

  @override
  Widget build(BuildContext context) {
    final color = lost ? AppColors.tertiary : AppColors.primary;

    return Container(
      constraints: const BoxConstraints(minHeight: 64),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              lost ? Icons.history : Icons.place_outlined,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppColors.onSurfaceVariant,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Text(
            time,
            style: const TextStyle(
              color: AppColors.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}