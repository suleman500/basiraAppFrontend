import 'package:flutter/material.dart';

import '../../models/detected_object.dart';

/// يرسم مربعًا وتسمية عربية فوق كل جسم مكتشف. يفترض إن box بكل عنصر
/// جاهز فعليًا بنفس مقياس الصورة الأصلية؛ التحويل لحجم الشاشة يصير هون
/// عبر scaleX/scaleY.
class BoundingBoxPainter extends CustomPainter {
  final List<DetectedObject> detections;
  final int imageWidth;
  final int imageHeight;
  final String Function(String englishLabel) labelTranslator;

  BoundingBoxPainter({
    required this.detections,
    required this.imageWidth,
    required this.imageHeight,
    required this.labelTranslator,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (detections.isEmpty || imageWidth == 0 || imageHeight == 0) return;

    final scaleX = size.width / imageWidth;
    final scaleY = size.height / imageHeight;

    final boxPaint = Paint()
      ..color = Colors.redAccent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    for (final obj in detections) {
      final rect = Rect.fromLTRB(
        obj.box.left * scaleX,
        obj.box.top * scaleY,
        obj.box.right * scaleX,
        obj.box.bottom * scaleY,

      );
      canvas.drawRect(rect, boxPaint);

      final label = labelTranslator(obj.label);
      final text = '${obj.label} ${obj.distance.toStringAsFixed(1)}m';
      final textPainter = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            backgroundColor: Colors.black54,
          ),
        ),
        textDirection: TextDirection.rtl,
      )..layout();

      final labelTop = (rect.top - textPainter.height).clamp(0, size.height);
      textPainter.paint(canvas, Offset(rect.left, labelTop.toDouble()));
    }
  }

  @override
  bool shouldRepaint(covariant BoundingBoxPainter oldDelegate) {
    return oldDelegate.detections != detections;
  }
}
