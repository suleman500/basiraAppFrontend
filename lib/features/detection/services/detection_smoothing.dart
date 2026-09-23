import 'dart:math' as math;
import 'dart:ui' show Rect;

import '../models/detected_object.dart';

/// منطق "تتبّع الهوية" بين إطار وتالي — يقرر أي جسم بالإطار الجديد
/// (incoming) هو "نفس" أي جسم بالإطار القديم (previousDetections)،
/// وينعّم المسافة بينهم بدل قفزة مفاجئة بالرقم. مستقل تمامًا عن أي
/// حالة واجهة (State/setState/BuildContext/الكاميرا) — دالة رياضية
/// خالصة: نفس المدخلات = نفس المخرجات دايمًا، سهلة الاختبار لحالها.
///
/// [previousDetections] هو آخر نتيجة كانت معروضة (عادةً _detections
/// بالشاشة وقت الاستدعاء)، و[incoming] هي نتيجة الكشف الخام الجديدة
/// من هالإطار.
List<DetectedObject> smoothDetections(
    List<DetectedObject> previousDetections,
    List<DetectedObject> incoming,
    ) {
  if (previousDetections.isEmpty) {
    return incoming;
  }

  final usedOldIndexes = <int>{};
  final smoothed = <DetectedObject>[];

  for (final current in incoming) {
    int? bestIndex;
    double bestScore = 0.0;

    for (int i = 0; i < previousDetections.length; i++) {
      if (usedOldIndexes.contains(i)) {
        continue;
      }

      final previous = previousDetections[i];

      if (previous.label != current.label) {
        continue;
      }

      final overlap = boxIou(previous.box, current.box);

      final centerDistance = boxCenterDistance(previous.box, current.box);

      final allowedDistance = math.max(50.0, previous.box.longestSide * 0.8);

      final isSameObject = overlap > 0.05 || centerDistance < allowedDistance;

      if (!isSameObject) {
        continue;
      }

      final score = overlap +
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

    final previous = previousDetections[bestIndex];

    final smoothedDistance = smoothDistance(
      previous.distance,
      current.distance,
    );

    smoothed.add(
      DetectedObject(
        label: current.label,
        confidence: current.confidence,
        box: current.box,
        distance: smoothedDistance,
        memoryId: current.memoryId ?? previous.memoryId,
      ),
    );
  }

  return smoothed;
}

/// نسبة تداخل مربعين (Intersection over Union) — 0 يعني صفر تداخل،
/// 1 يعني نفس المربع تمامًا.
double boxIou(Rect first, Rect second) {
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

/// المسافة الإقليدية بين مركزي مربعين (بالبكسل).
double boxCenterDistance(Rect first, Rect second) {
  final dx = first.center.dx - second.center.dx;
  final dy = first.center.dy - second.center.dy;

  return math.sqrt(dx * dx + dy * dy);
}

/// ينعّم قيمة مسافة قديمة/جديدة بدل قفزة مفاجئة بالرقم المعلَن
/// صوتيًا. يتجاهل القيم غير الصالحة (<= 0) من أي الطرفين بدل ما
/// يلوّث المتوسط برقم فاسد.
double smoothDistance(double oldDistance, double newDistance) {
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

/// ⚠️ غير مستخدَمة حاليًا بأي مكان بالكود — تحريك الصناديق بالـTicker
/// (_onBoxAnimationTick بـdetection_screen.dart) بيستخدم Rect.lerp()
/// الجاهزة من Flutter نفسها، مو هاي. أُبقيت هون (بدل الحذف) لأنها
/// منطقيًا نفس فئة "دوال Rect المساعدة"، واحتمال تنفع لاستخدام
/// مستقبلي مشابه. احذفها بأمان لو تأكدت إنه ما رح تحتاجها.
Rect lerpRect(Rect oldRect, Rect newRect, double amount) {
  return Rect.fromLTRB(
    oldRect.left + (newRect.left - oldRect.left) * amount,
    oldRect.top + (newRect.top - oldRect.top) * amount,
    oldRect.right + (newRect.right - oldRect.right) * amount,
    oldRect.bottom + (newRect.bottom - oldRect.bottom) * amount,
  );
}