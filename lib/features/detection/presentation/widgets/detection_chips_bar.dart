import 'package:flutter/material.dart';

import '../../models/detected_object.dart';

/// شريط أسفل الشاشة يعرض بطاقة صغيرة لكل جسم مكتشف حاليًا، مع اسمه
/// العربي ونسبة الثقة.
class DetectionChipsBar extends StatelessWidget {
  final List<DetectedObject> detections;
  final String Function(String englishLabel) labelTranslator;

  const DetectionChipsBar({
    super.key,
    required this.detections,
    required this.labelTranslator,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 44, maxHeight: 90),
      color: Colors.black87,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: detections.isEmpty
          ? const Center(
        child: Text(
          'لا توجد أشياء مكتشفة حاليًا',
          style: TextStyle(color: Colors.white54, fontSize: 12),
        ),
      )
          : SingleChildScrollView(
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          children: detections.map((obj) {
            final label = labelTranslator(obj.label);
            return Chip(
              label: Text(
                '$label (${(obj.confidence * 100).toStringAsFixed(0)}%)',
                style: const TextStyle(fontSize: 11),
              ),
              backgroundColor: Colors.teal.shade700,
              labelStyle: const TextStyle(color: Colors.white),
              visualDensity: VisualDensity.compact,
            );
          }).toList(),
        ),
      ),
    );
  }
}
