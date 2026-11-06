import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

import '../../../core/constants.dart';

/// خدمة قراءة الجيروسكوب — تُستخدم لأمرين:
///
/// 1) معرفة "لأي جهة التفت المستخدم" لما يفقد الهدف أثناء وضع التوجيه
///    (`cumulativeYaw` + `resetYaw`) — كما كانت سابقًا بدون أي تغيير.
///
/// 2) **اتجاه الكاميرا المطلق** (`heading`) لرسم خريطة الأجسام: كل جسم
///    يُحفظ باتجاهه الحقيقي (أمام/جانب/خلف) بدل اعتباره دائمًا "أمامك".
///    الاتجاه يُحسب بدمج الجيروسكوب (سلس وسريع) مع البوصلة
///    (مغناطيسية + تسارع، تمنع الانجراف وتعطي مرجعًا ثابتًا بين
///    الجلسات). لو ما توفرت البوصلة يعمل بالجيروسكوب وحده (يبدأ من 0).
class GyroscopeService {
  StreamSubscription<GyroscopeEvent>? _subscription;
  StreamSubscription<AccelerometerEvent>? _accelSubscription;
  StreamSubscription<MagnetometerEvent>? _magSubscription;

  DateTime? _lastEventTime;
  DateTime? _startedAt;
  double _cumulativeYaw = 0.0;
  double _instantaneousMagnitude = 0.0;

  // ---- اتجاه الكاميرا المطلق ----
  double? _heading; // راديان [0, 2π) — يزداد باتجاه عقارب الساعة
  bool _hasCompass = false;
  List<double>? _accel; // بعد فلتر تمرير منخفض
  List<double>? _mag;

  /// وزن تصحيح البوصلة لكل قراءة — صغير حتى يبقى الجيروسكوب هو الأساس
  /// وتزيل البوصلة الانجراف ببطء فقط.
  static const double _compassGain = 0.02;

  /// إجمالي الدوران (راديان) منذ آخر استدعاء لـ resetYaw(). موجب أو
  /// سالب حسب الاتجاه (راجع AppConstants.gyroYawPositiveMeansTurnedLeft
  /// لتفسير الإشارة — يحتاج تأكيد فعلي بالاختبار على جهازك).
  double get cumulativeYaw => _cumulativeYaw;

  /// سرعة الدوران اللحظية (rad/s) — مجموع القيم المطلقة بالثلاث محاور.
  double get instantaneousMagnitude => _instantaneousMagnitude;

  /// اتجاه الكاميرا الحالي بالراديان (0 = شمال، يزداد مع الدوران يمينًا).
  /// لا يتأثر بـ resetYaw().
  double get heading => _heading ?? 0.0;

  /// هل توفّرت قراءة اتجاه صالحة؟ (قبلها heading = 0 افتراضي).
  bool get hasHeading => _heading != null;

  /// هل البوصلة تعمل؟ (false = جيروسكوب فقط، والاتجاه نسبي لبداية التشغيل).
  bool get hasCompass => _hasCompass;

  bool get isListening => _subscription != null;

  void start() {
    if (_subscription != null) return;

    _startedAt = DateTime.now();

    _subscription = gyroscopeEventStream().listen(
      _onEvent,
      onError: (_) {},
    );

    // البوصلة اختيارية: لو الجهاز ما يدعمها نكمل بالجيروسكوب وحده.
    try {
      _accelSubscription = accelerometerEventStream().listen(
        _onAccel,
        onError: (_) {},
      );
      _magSubscription = magnetometerEventStream().listen(
        _onMag,
        onError: (_) {},
      );
    } catch (_) {}
  }

  void _onEvent(GyroscopeEvent event) {
    final now = DateTime.now();

    _instantaneousMagnitude =
        event.x.abs() + event.y.abs() + event.z.abs();

    if (_lastEventTime != null) {
      final dtSeconds =
          now.difference(_lastEventTime!).inMicroseconds / 1e6;

      // محور Y هو محور "الالتفاف يمين/يسار" (yaw) للهاتف بوضع عمودي
      // والكاميرا الخلفية تصوّر للأمام. ⚠️ الاتجاه (موجب = يسار أم
      // يمين) يحتاج تأكيد فعلي بالاختبار — لو طلعت رسائل detection_
      // screen.dart معكوسة (يقول "ارجع يمين" وانت فعليًا لازم ترجع
      // يسار)، اقلب AppConstants.gyroYawPositiveMeansTurnedLeft بدل ما
      // تعدّل هذا الملف.
      final dYaw = event.y * dtSeconds;
      _cumulativeYaw += dYaw;

      // الاتجاه المطلق يزداد مع الدوران يمينًا.
      if (_heading == null &&
          !_hasCompass &&
          _startedAt != null &&
          now.difference(_startedAt!) > const Duration(seconds: 2)) {
        // ما في بوصلة بعد مرور ثانيتين: نبدأ بالجيروسكوب وحده من 0.
        _heading = 0.0;
      }

      if (_heading != null) {
        final delta = AppConstants.gyroYawPositiveMeansTurnedLeft
            ? -dYaw
            : dYaw;
        _heading = _wrap2Pi(_heading! + delta);
      }
    }

    _lastEventTime = now;
  }

  void _onAccel(AccelerometerEvent e) {
    _accel = _lowPass(_accel, [e.x, e.y, e.z], 0.15);
  }

  void _onMag(MagnetometerEvent e) {
    _mag = _lowPass(_mag, [e.x, e.y, e.z], 0.15);
    _updateFromCompass();
  }

  /// يحسب اتجاه الكاميرا الخلفية (محور -Z للجهاز) بالنسبة للشمال
  /// المغناطيسي بتعويض ميلان الهاتف، ثم يصحّح به الاتجاه المدمج.
  void _updateFromCompass() {
    final a = _accel;
    final m = _mag;
    if (a == null || m == null) return;

    final up = _normalize(a);
    if (up == null) return;

    // east = m × up ، north = up × east (نفس تعريف Android)
    final east = _normalize(_cross(m, up));
    if (east == null) return;
    final north = _cross(up, east);

    // اتجاه الكاميرا الخلفية بإحداثيات الجهاز = (0, 0, -1)
    final forwardEast = -east[2];
    final forwardNorth = -north[2];

    // لو الكاميرا موجهة لأعلى/لأسفل تقريبًا، الاتجاه الأفقي غير موثوق.
    final horizontal =
    math.sqrt(forwardEast * forwardEast + forwardNorth * forwardNorth);
    if (horizontal < 0.3) return;

    final compass = _wrap2Pi(math.atan2(forwardEast, forwardNorth));
    _hasCompass = true;

    if (_heading == null) {
      _heading = compass;
    } else {
      final diff = _wrapPi(compass - _heading!);
      _heading = _wrap2Pi(_heading! + diff * _compassGain);
    }
  }

  // ---- رياضيات مساعدة ----

  List<double> _lowPass(List<double>? previous, List<double> input, double a) {
    if (previous == null) return input;
    return [
      previous[0] + a * (input[0] - previous[0]),
      previous[1] + a * (input[1] - previous[1]),
      previous[2] + a * (input[2] - previous[2]),
    ];
  }

  List<double> _cross(List<double> a, List<double> b) => [
    a[1] * b[2] - a[2] * b[1],
    a[2] * b[0] - a[0] * b[2],
    a[0] * b[1] - a[1] * b[0],
  ];

  List<double>? _normalize(List<double> v) {
    final n = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
    if (n < 1e-6) return null;
    return [v[0] / n, v[1] / n, v[2] / n];
  }

  double _wrap2Pi(double x) {
    const twoPi = 2 * math.pi;
    var v = x % twoPi;
    if (v < 0) v += twoPi;
    return v;
  }

  double _wrapPi(double x) {
    var v = _wrap2Pi(x);
    if (v > math.pi) v -= 2 * math.pi;
    return v;
  }

  /// يصفّر عدّاد الدوران التراكمي — استدعيه كل مرة يُرى فيها الهدف
  /// فعليًا، حتى يبقى العدّاد يقيس "الدوران منذ آخر مرة شفناه" بس.
  /// (لا يؤثر على [heading].)
  void resetYaw() {
    _cumulativeYaw = 0.0;
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _accelSubscription?.cancel();
    _accelSubscription = null;
    _magSubscription?.cancel();
    _magSubscription = null;
    _lastEventTime = null;
  }
}