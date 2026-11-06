import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:projctlitudei/core/theme/app_colors.dart';

import '../../models/detected_object.dart';

/// يرسم مربعًا وتسمية عربية فوق كل جسم مكتشف (بأسلوب HUD).
/// يفترض إن box بكل عنصر جاهز فعليًا بنفس مقياس الصورة الأصلية؛
/// التحويل لحجم الشاشة يصير هون عبر scaleX/scaleY.
class BoundingBoxPainter extends CustomPainter {
  final List<DetectedObject> detections;
  final int imageWidth;
  final int imageHeight;
  final String Function(String englishLabel) labelTranslator;

  /// تصنيف القرب النسبي لكل جسم، يُحدَّث فقط بعد طلب قياس مسافة صريح.
  final Map<String, String> proximityLabels;

  /// trackingKey للجسم "الملموس" حاليًا (لو موجود) — يُرسَم بالسماوي.
  final String? touchedKey;

  BoundingBoxPainter({
    required this.detections,
    required this.imageWidth,
    required this.imageHeight,
    required this.labelTranslator,
    this.proximityLabels = const {},
    this.touchedKey,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty || imageWidth == 0 || imageHeight == 0) return;

    final scaleX = size.width / imageWidth;
    final scaleY = size.height / imageHeight;

    for (final obj in detections) {
      final isTouched = touchedKey != null && obj.trackingKey == touchedKey;
      final color = isTouched ? AppColors.secondary : AppColors.primary;

      final rect = Rect.fromLTRB(
        obj.box.left * scaleX,
        obj.box.top * scaleY,
        obj.box.right * scaleX,
        obj.box.bottom * scaleY,
      );
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));

      // توهج ناعم خلف الإطار
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = color.withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );

      // الإطار نفسه
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = isTouched ? 3.5 : 2,
      );

      final label = labelTranslator(obj.label);
      final proximity = proximityLabels[obj.label];
      final text = proximity != null ? '$label · $proximity' : label;

      final textPainter = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(
            color: AppColors.onPrimary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.rtl,
      )..layout();

      const padH = 8.0;
      const padV = 4.0;
      final labelHeight = textPainter.height + padV * 2;
      final maxTop = math.max(0.0, size.height - labelHeight);
      final labelTop = (rect.top - labelHeight).clamp(0.0, maxTop).toDouble();

      final labelRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          rect.left,
          labelTop,
          textPainter.width + padH * 2,
          labelHeight,
        ),
        const Radius.circular(8),
      );

      canvas.drawRRect(labelRect, Paint()..color = color);
      textPainter.paint(canvas, Offset(rect.left + padH, labelTop + padV));
    }
  }

  @override
  bool shouldRepaint(covariant BoundingBoxPainter oldDelegate) {
    return oldDelegate.detections != detections ||
        oldDelegate.proximityLabels != proximityLabels ||
        oldDelegate.touchedKey != touchedKey;
  }
}