import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker, TickerProvider;

import '../../../core/constants.dart';
import '../models/detected_object.dart';
import '../services/hand_tracker_service.dart' show HandLandmark;

/// يحرّك صناديق الكشف ونقاط اليد بسلاسة (60fps) نحو آخر هدف من
/// الموديل، بدل ما تقفز فجأة كل ما توصل نتيجة كشف جديدة — نفس
/// تقنية "النقطة المضيئة" اللي بتقارب هدفها تدريجيًا.
///
/// ⚠️ الملف الوحيد اللي محتاج TickerProvider (وبالتالي
/// SingleTickerProviderStateMixin بالشاشة) — باقي منطق الكاميرا/
/// الصوت ما إله علاقة بالأنيميشن إطلاقًا. الشاشة بتزوّد هالكلاس
/// بدالتين (getters) بترجع "الهدف الحالي" كل تيك — مو Stream ولا
/// ChangeNotifier، لأنه أبسط حل ممكن لمشكلة "اقرأ آخر قيمة لحظة
/// التيك" بدون أي طبقة وسيطة إضافية.
class BoxAnimationController {
  BoxAnimationController({
    required TickerProvider vsync,
    required List<DetectedObject> Function() targetDetections,
    required List<HandLandmark> Function() targetHandPoints,
  })  : _targetDetections = targetDetections,
        _targetHandPoints = targetHandPoints {
    _ticker = vsync.createTicker(_onTick)..start();
  }

  final List<DetectedObject> Function() _targetDetections;
  final List<HandLandmark> Function() _targetHandPoints;

  late final Ticker _ticker;
  Duration? _lastTickElapsed;

  final ValueNotifier<List<DetectedObject>> animatedDetections =
  ValueNotifier<List<DetectedObject>>([]);

  final ValueNotifier<List<HandLandmark>> animatedHandPoints =
  ValueNotifier<List<HandLandmark>>([]);

  void _onTick(Duration elapsed) {
    final previousElapsed = _lastTickElapsed;
    _lastTickElapsed = elapsed;

    if (previousElapsed == null) return;

    final dtSeconds = (elapsed - previousElapsed).inMicroseconds / 1e6;

    if (dtSeconds <= 0) return;

    final targets = _targetDetections();
    final previousAnimated = animatedDetections.value;

    if (targets.isNotEmpty || previousAnimated.isNotEmpty) {
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

        final animatedBox =
        Rect.lerp(previous.box, target.box, convergence)!;

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

      final boxesConverged = !anyStillMoving &&
          previousAnimated.length == nextAnimated.length;

      if (!boxesConverged) {
        animatedDetections.value = nextAnimated;
      }

      _tickHandPoints(convergence);
    }
  }

  void _tickHandPoints(double convergence) {
    final handTargets = _targetHandPoints();
    final previousHandPoints = animatedHandPoints.value;

    if (handTargets.isEmpty && previousHandPoints.isEmpty) {
      return;
    }

    if (handTargets.length != previousHandPoints.length) {
      animatedHandPoints.value = handTargets;
      return;
    }

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

    animatedHandPoints.value = nextHandPoints;
  }

  /// يصفّر كل شي فورًا (بدون أنيميشن انتقالية) — يُستدعى لما الكشف
  /// يتوقف يدويًا (_toggleDetection) حتى ما تضل صناديق قديمة ظاهرة
  /// على شاشة سوداء.
  void reset() {
    animatedDetections.value = [];
    animatedHandPoints.value = [];
    _lastTickElapsed = null;
  }

  void dispose() {
    _ticker.dispose();
    animatedDetections.dispose();
    animatedHandPoints.dispose();
  }
}