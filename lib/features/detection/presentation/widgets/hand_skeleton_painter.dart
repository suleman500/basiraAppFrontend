import 'package:flutter/material.dart';

import '../../services/hand_tracker_service.dart';

/// روابط هيكل اليد القياسية (21 نقطة، نفس ترتيب MediaPipe Hand
/// Landmarker): كل زوج = عظمة/خط بين مفصلين.
const List<List<int>> handConnections = [
  // الإبهام
  [0, 1], [1, 2], [2, 3], [3, 4],
  // السبّابة
  [0, 5], [5, 6], [6, 7], [7, 8],
  // الوسطى
  [5, 9], [9, 10], [10, 11], [11, 12],
  // البنصر
  [9, 13], [13, 14], [14, 15], [15, 16],
  // الخنصر
  [13, 17], [17, 18], [18, 19], [19, 20],
  // قاعدة الكف
  [0, 17],
];

/// يرسم هيكل اليد (نقاط + خطوط) فوق الكاميرا. نقاط اليد نسبية (0..1)
/// بالنسبة لحجم إطار الكشف — نفس مقياس صناديق الأجسام بالضبط، فنستخدم
/// نفس أسلوب scaleX/scaleY.
class HandSkeletonPainter extends CustomPainter {
  final List<HandLandmark> landmarks;
  final int imageWidth;
  final int imageHeight;

  /// لون الهيكل يتغيّر حسب حالة اليد (قبضة أم مفتوحة) — إشارة بصرية
  /// إضافية عن حالة التفاعل الحالية.
  final bool isFist;

  HandSkeletonPainter({
    required this.landmarks,
    required this.imageWidth,
    required this.imageHeight,
    required this.isFist,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (landmarks.isEmpty || imageWidth == 0 || imageHeight == 0) return;

    // نقاط اليد محفوظة هون بمقياس بكسلات الكاميرا الفعلي (fullWidth/
    // fullHeight) — نفس مقياس imageWidth/imageHeight بالضبط، فنحتاج
    // بس نفس تحويل scaleX/scaleY المستخدم بصناديق الأجسام.
    final scaleX = size.width / imageWidth;
    final scaleY = size.height / imageHeight;

    final lineColor = isFist ? Colors.orangeAccent : Colors.cyanAccent;

    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final pointPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    Offset scaledPoint(int index) {
      final point = landmarks[index];
      return Offset(point.x * scaleX, point.y * scaleY);
    }

    // الخطوط (العظام) أول، بعدين النقاط فوقها.
    for (final connection in handConnections) {
      if (connection[0] >= landmarks.length ||
          connection[1] >= landmarks.length) {
        continue;
      }

      canvas.drawLine(
        scaledPoint(connection[0]),
        scaledPoint(connection[1]),
        linePaint,
      );
    }

    for (int i = 0; i < landmarks.length; i++) {
      canvas.drawCircle(scaledPoint(i), 5, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant HandSkeletonPainter oldDelegate) {
    return oldDelegate.landmarks != landmarks ||
        oldDelegate.isFist != isFist;
  }
}