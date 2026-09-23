import 'dart:math' as math;

import 'package:flutter/material.dart' show Offset, Rect;

import '../../../core/constants.dart';
import '../models/detected_object.dart';
import '../services/hand_tracker_service.dart' show HandLandmark;

/// نتيجة معالجة إطار وحدة من نقاط اليد — بيانات جاهزة للعرض
/// (touchedObjectKey/isFist/displayHandPoints)، بالإضافة لـ
/// [justSelectedObject] اللي بيكون non-null **فقط باللحظة اللي صار
/// فيها "تحديد" فعلي بقبضة يد** (تريغر لمرة وحدة، مو حالة مستمرة).
/// الشاشة هي اللي تقرر شو تسوي بـ[justSelectedObject] (نطق + بدء
/// توجيه) — هالكلاس بس بيبلّغ "صار تحديد"، ما بيتخذ أي قرار تنفيذي.
class HandFrameResult {
  final String? touchedObjectKey;
  final bool isFist;
  final List<HandLandmark> displayHandPoints;
  final DetectedObject? justSelectedObject;

  const HandFrameResult({
    required this.touchedObjectKey,
    required this.isFist,
    required this.displayHandPoints,
    this.justSelectedObject,
  });
}

/// يحوّل نقاط يد خام (من HandTrackerService) لقرارات: هل صارت قبضة؟
/// هل فيه جسم ملموس بسبّابة الإصبع؟ هل صار "تحديد" (قبضة على جسم
/// ملموس، بعد فترة تهدئة)؟ مستقل عن أي حالة واجهة — بيحتفظ بس
/// بذاكرة داخلية بسيطة لازمة لمنطقه (آخر تحديد، آخر حالة قبضة).
///
/// ⚠️ معطّل حاليًا بالكامل (AppConstants.handTrackingEnabled = false)
/// — نُقل هون كخطوة تنظيم منخفضة الخطر (الكود ميت فعليًا بالتطبيق
/// الشغال)، تمهيدًا لأي تفعيل مستقبلي.
class HandGestureController {
  DateTime? _lastTouchTriggerAt;
  bool _wasFistLastFrame = false;

  /// يعالج إطار وحدة كامل: يشيل كشوفات "شخص" الوهمية من [results]
  /// (تعديل بالمكان — removeWhere)، يحدد الجسم الملموس، ويقرر لو
  /// صار "تحديد" فعلي هالإطار بالذات.
  HandFrameResult process({
    required List<HandLandmark> handLandmarks,
    required List<DetectedObject> results,
    required int fullWidth,
    required int fullHeight,
  }) {
    _removeHandMisdetectedPersons(
      handLandmarks: handLandmarks,
      results: results,
      fullWidth: fullWidth,
      fullHeight: fullHeight,
    );

    final touchedObject = _findTouchedObject(
      handLandmarks: handLandmarks,
      results: results,
      fullWidth: fullWidth,
      fullHeight: fullHeight,
    );

    final isFistNow = _isFistGesture(handLandmarks);

    DetectedObject? justSelected;

    if (touchedObject != null && isFistNow && !_wasFistLastFrame) {
      final now = DateTime.now();
      final cooldownElapsed = _lastTouchTriggerAt == null ||
          now.difference(_lastTouchTriggerAt!) >
              Duration(seconds: AppConstants.touchSelectionCooldownSeconds);

      if (cooldownElapsed) {
        _lastTouchTriggerAt = now;
        justSelected = touchedObject;
      }
    }

    _wasFistLastFrame = isFistNow;

    final displayPoints = handLandmarks
        .map(
          (p) => HandLandmark(
        x: p.x * fullWidth,
        y: p.y * fullHeight,
        z: p.z,
      ),
    )
        .toList();

    return HandFrameResult(
      touchedObjectKey: touchedObject?.trackingKey,
      isFist: isFistNow,
      displayHandPoints: displayPoints,
      justSelectedObject: justSelected,
    );
  }

  /// يصفّر الذاكرة الداخلية (آخر تحديد، آخر حالة قبضة) — يُستدعى لما
  /// الكشف يتوقف يدويًا، حتى ما يضل "تهدئة" وهمية من جلسة سابقة.
  void reset() {
    _lastTouchTriggerAt = null;
    _wasFistLastFrame = false;
  }

  /// اليد نفسها أحيانًا تنصنّف غلط كـ"شخص" من موديل الكشف — نشيل أي
  /// صندوق "person" متداخل بشكل كبير مع صندوق محيط نقاط اليد.
  void _removeHandMisdetectedPersons({
    required List<HandLandmark> handLandmarks,
    required List<DetectedObject> results,
    required int fullWidth,
    required int fullHeight,
  }) {
    if (handLandmarks.isEmpty) return;

    double minX = 1.0, minY = 1.0, maxX = 0.0, maxY = 0.0;

    for (final point in handLandmarks) {
      if (point.x < minX) minX = point.x;
      if (point.y < minY) minY = point.y;
      if (point.x > maxX) maxX = point.x;
      if (point.y > maxY) maxY = point.y;
    }

    final handBox = Rect.fromLTRB(
      minX * fullWidth,
      minY * fullHeight,
      maxX * fullWidth,
      maxY * fullHeight,
    );

    results.removeWhere((obj) {
      if (obj.label != 'person') return false;

      final intersection = obj.box.intersect(handBox);
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

  /// الجسم اللي طرف السبّابة (نقطة رقم 8) واقف فوقه حاليًا، لو فيه.
  DetectedObject? _findTouchedObject({
    required List<HandLandmark> handLandmarks,
    required List<DetectedObject> results,
    required int fullWidth,
    required int fullHeight,
  }) {
    if (handLandmarks.length <= 8) return null;

    final indexFingertip = handLandmarks[8];
    final fingertipPoint = Offset(
      indexFingertip.x * fullWidth,
      indexFingertip.y * fullHeight,
    );

    const touchTolerance = 10.0;

    for (final obj in results) {
      final tolerantBox = obj.box.inflate(touchTolerance);
      if (tolerantBox.contains(fingertipPoint)) {
        return obj;
      }
    }

    return null;
  }

  /// يقارن بعد أطراف الأصابع عن الرسغ بحجم الكف — قبضة مقفولة يعني
  /// الأصابع قريبة من الرسغ نسبيًا (ratio واطي).
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
}