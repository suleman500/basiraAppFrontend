import 'dart:async';

import 'package:sensors_plus/sensors_plus.dart';

/// خدمة قراءة الجيروسكوب — تُستخدم حاليًا لمعرفة "لأي جهة التفت
/// المستخدم" لما يفقد الهدف أثناء وضع التوجيه، بدل رسالة عامة "فقدت
/// الهدف" غير مفيدة.
///
/// الفكرة: كل ما شاف الكشف الهدف بإطار، نصفّر عدّاد الدوران التراكمي
/// (`resetYaw`). لو اختفى الهدف بعدين، العدّاد يستمر يتراكم بمقدار
/// دوران الهاتف الفعلي — فلما نوصل لعتبة "فقدان مؤكد"، نعرف بالضبط
/// لأي جهة المستخدم لف، ونقوله يرجع للجهة المعاكسة.
class GyroscopeService {
  StreamSubscription<GyroscopeEvent>? _subscription;

  DateTime? _lastEventTime;
  double _cumulativeYaw = 0.0;
  double _instantaneousMagnitude = 0.0;

  /// إجمالي الدوران (راديان) منذ آخر استدعاء لـ resetYaw(). موجب أو
  /// سالب حسب الاتجاه (راجع AppConstants.gyroYawPositiveMeansTurnedLeft
  /// لتفسير الإشارة — يحتاج تأكيد فعلي بالاختبار على جهازك).
  double get cumulativeYaw => _cumulativeYaw;

  /// سرعة الدوران اللحظية (rad/s) — مجموع القيم المطلقة بالثلاث محاور.
  /// محجوزة لاستخدام مستقبلي (كشف الحركة السريعة لتجاهل إطارات مهزوزة
  /// قبل حتى تشغيل الموديل عليها)، غير مفعّلة بعد بمعالجة الإطارات.
  double get instantaneousMagnitude => _instantaneousMagnitude;

  bool get isListening => _subscription != null;

  void start() {
    if (_subscription != null) return;

    _subscription = gyroscopeEventStream().listen(_onEvent);
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
      _cumulativeYaw += event.y * dtSeconds;
    }

    _lastEventTime = now;
  }

  /// يصفّر عدّاد الدوران التراكمي — استدعيه كل مرة يُرى فيها الهدف
  /// فعليًا، حتى يبقى العدّاد يقيس "الدوران منذ آخر مرة شفناه" بس.
  void resetYaw() {
    _cumulativeYaw = 0.0;
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _lastEventTime = null;
  }
}