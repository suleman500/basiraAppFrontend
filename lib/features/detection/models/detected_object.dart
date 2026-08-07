import 'package:flutter/material.dart';

/// يمثّل جسمًا واحدًا اكتُشف بالصورة. هذا الكلاس هو "اللغة المشتركة" بين
/// خدمة الكشف، شاشة العرض، ومنطق النطق الصوتي — أي جزء جديد نضيفه
/// مستقبلًا (زي LLM أو ميزة جديدة) يتعامل مع نفس الشكل بدون تعديل الباقي.
@immutable
class DetectedObject {
  /// اسم الفئة بالإنجليزي كما يرجعه الموديل (مثل "person", "car")
  final String label;

  /// نسبة الثقة من 0.0 إلى 1.0
  final double confidence;

  /// إحداثيات المربع، بنفس مقياس الصورة التي حُلّلت (قبل أي تحويل شاشة)
  final Rect box;
// عشان المسافه
  final double distance;

  const DetectedObject({
    required this.label,
    required this.confidence,
    required this.box,
    required this.distance
  });

  /// معرّف بسيط يُستخدم لتتبّع "هل هذا نفس الجسم اللي كان ظاهر قبل شوي"
  /// بمنطق النطق الصوتي (حاليًا بس اسم الفئة، ممكن نطوّره لاحقًا ليشمل
  /// الموقع التقريبي لو صار عنا أكثر من جسم من نفس النوع بنفس الوقت).
  String get trackingKey => label;

  @override
  String toString() =>
      'DetectedObject(label: $label, confidence: ${confidence.toStringAsFixed(2)}, box: $box)';
}
