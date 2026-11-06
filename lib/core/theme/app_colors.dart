import 'package:flutter/material.dart';

/// ألوان تصميم Stitch (Lumina Vision Assistant) — مصدرها ملف DESIGN.md.
/// استخدمها في كل الشاشات حتى تبقى الهوية موحّدة.
class AppColors {
  AppColors._();

  static const background = Color(0xFF101417);
  static const surfaceLowest = Color(0xFF0B0F12);
  static const surfaceLow = Color(0xFF181C1F);
  static const surface = Color(0xFF1C2023);
  static const surfaceHigh = Color(0xFF262A2E);
  static const surfaceHighest = Color(0xFF313539);

  static const onSurface = Color(0xFFE0E3E7);
  static const onSurfaceVariant = Color(0xFFB9CBBD);
  static const outlineVariant = Color(0xFF3B4A40);

  static const primary = Color(0xFF00F5A0); // أخضر زمردي
  static const onPrimary = Color(0xFF0B0F12);
  static const secondary = Color(0xFF00D2FF); // سماوي
  static const tertiary = Color(0xFFFFB800); // كهرماني (تنبيه)
  static const error = Color(0xFFFFB4AB);

  static const glassBorder = Color(0x1FFFFFFF); // أبيض 12%
}