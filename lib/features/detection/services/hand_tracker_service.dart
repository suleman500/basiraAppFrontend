import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// نقطة واحدة من نقاط اليد الـ21 (بمعمارية MediaPipe Hand Landmarker):
/// 0=معصم، 1-4=إبهام، 5-8=سبّابة، 9-12=وسطى، 13-16=بنصر، 17-20=خنصر.
/// x/y نسبية (0..1) بالنسبة لحجم الإطار المُدخل — لازم تحويلها لمقياس
/// بكسلات الكاميرا الفعلي قبل مقارنتها بصناديق YOLOX (نفس أسلوب
/// scaleX/scaleY المستخدم بـ detector_service.dart).
class HandLandmark {
  final double x;
  final double y;
  final double z;

  const HandLandmark({
    required this.x,
    required this.y,
    required this.z,
  });
}

/// خدمة تتبّع اليد — تستخدم MediaPipe Hand Landmarker عبر كود Kotlin
/// أصلي (نفس أسلوب NativeDetectorService بالضبط، قناة منفصلة).
///
/// مرحلة 1 فقط: تحميل + تشغيل + رجوع نقاط اليد الخام. منطق "اللمس +
/// الأخضر + التوجيه" يُبنى فوق هاي البيانات بـ detection_screen.dart.
class HandTrackerService {
  static const MethodChannel _channel =
  MethodChannel('basira/hand_tracker');

  bool _modelLoaded = false;

  bool get isReady => _modelLoaded;

  Future<void> load() async {
    if (isReady) return;

    final success = await _channel.invokeMethod<bool>('loadModel');

    if (success != true) {
      throw Exception('فشل تحميل موديل تتبّع اليد');
    }

    _modelLoaded = true;
    debugPrint('Hand Tracker: تم التحميل بنجاح');
  }

  /// يرجّع قائمة الـ21 نقطة لليد المكتشفة (لو موجودة)، أو قائمة فاضية
  /// لو ما في يد ظاهرة بالإطار الحالي.
  Future<List<HandLandmark>> detect(
      Uint8List rgbBytes, {
        required int width,
        required int height,
      }) async {
    if (!isReady) return [];

    final flatValues = await _channel.invokeListMethod<double>(
      'detectHand',
      {
        'input': rgbBytes,
        'width': width,
        'height': height,
      },
    );

    if (flatValues == null || flatValues.isEmpty) return [];

    final landmarks = <HandLandmark>[];

    for (int i = 0; i < flatValues.length; i += 3) {
      landmarks.add(
        HandLandmark(
          x: flatValues[i],
          y: flatValues[i + 1],
          z: flatValues[i + 2],
        ),
      );
    }

    return landmarks;
  }

  void dispose() {
    // ما في موارد Dart-side لازم نحررها — الموديل محفوظ Native.
  }
}