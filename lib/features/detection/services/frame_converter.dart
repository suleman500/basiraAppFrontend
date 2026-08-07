import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// بيانات إطار كاميرا خام، مُجهَّزة بشكل قابل للنقل بأمان بين الـ Isolates
/// (كلها أنواع بسيطة: Uint8List و int، بدون أي كائنات معقّدة).
class FrameConversionJob {
  final Uint8List yBytes;
  final Uint8List uBytes;
  final Uint8List vBytes;
  final int width; // عرض إطار الكاميرا الخام (قبل الدوران)
  final int height; // ارتفاع إطار الكاميرا الخام (قبل الدوران)
  final int yRowStride;
  final int uvRowStride;
  final int uvPixelStride;
  final int sensorOrientation;
  final int targetSize; // حجم إدخال الموديل (مربّع، مثل 320)

  FrameConversionJob({
    required this.yBytes,
    required this.uBytes,
    required this.vBytes,
    required this.width,
    required this.height,
    required this.yRowStride,
    required this.uvRowStride,
    required this.uvPixelStride,
    required this.sensorOrientation,
    required this.targetSize,
  });
}

/// نتيجة التحويل: صورة RGB مربّعة جاهزة تمامًا لتُطعَم للموديل مباشرة،
/// بصيغة بايتات مسطّحة (أسرع بكثير من الوصول بكسل-بكسل عبر getPixel).
class ConvertedFrame {
  final Uint8List rgbBytes; // طولها targetSize * targetSize * 3
  final int size; // = targetSize

  ConvertedFrame(this.rgbBytes, this.size);
}

/// دالة على المستوى الأعلى (top-level) — شرط أساسي حتى يقدر compute()
/// يشغّلها بخيط Isolate منفصل تمامًا عن واجهة المستخدم.
///
/// الفكرة الأساسية للتسريع: بدل ما نحوّل كل بكسل بالصورة الخام (قد تصل
/// 345 ألف بكسل) ثم نصغّرها لاحقًا لحجم الموديل (320×320 = 102 ألف بكسل)،
/// نأخذ عيّنات (نتخطى بكسلات) أثناء القراءة من بيانات الكاميرا الخام
/// نفسها، فنحوّل فقط تقريبًا العدد اللي بنحتاجه فعليًا — توفير كبير
/// بالحسابات. الدوران والتصغير النهائي للمربّع يتما على الصورة الصغيرة
/// الناتجة (رخيصان جدًا على صورة صغيرة، بعكس صورة كاملة الحجم).
ConvertedFrame convertCameraFrame(FrameConversionJob job) {
  final targetSize = job.targetSize;

  // نحسب "نسبة تخطي" (stride) عيّنات القراءة، بحيث نقرأ فقط تقريبًا
  // الكمية اللي هنحتاجها، مو كل بكسل بالصورة الخام كاملة الحجم.
  final smallerDimension =
  job.width < job.height ? job.width : job.height;
  final approxTargetBeforeSquare = (targetSize * 1.3).round();
  int stride = (smallerDimension / approxTargetBeforeSquare).floor();
  if (stride < 1) stride = 1;
  if (stride > 4) stride = 4;

  final sampledWidth = (job.width / stride).floor();
  final sampledHeight = (job.height / stride).floor();

  final sampled = img.Image(width: sampledWidth, height: sampledHeight);

  for (int y = 0; y < sampledHeight; y++) {
    final srcY = y * stride;
    for (int x = 0; x < sampledWidth; x++) {
      final srcX = x * stride;
      final yValue = job.yBytes[srcY * job.yRowStride + srcX];
      final uvIndex =
          (srcY ~/ 2) * job.uvRowStride + (srcX ~/ 2) * job.uvPixelStride;
      final uValue = job.uBytes[uvIndex];
      final vValue = job.vBytes[uvIndex];

      final r = (yValue + 1.402 * (vValue - 128)).round().clamp(0, 255);
      final g = (yValue -
          0.344136 * (uValue - 128) -
          0.714136 * (vValue - 128))
          .round()
          .clamp(0, 255);
      final b = (yValue + 1.772 * (uValue - 128)).round().clamp(0, 255);
      sampled.setPixelRgba(x, y, r, g, b, 255);
    }
  }

  // الدوران والتصغير النهائي يشتغلون على الصورة الصغيرة (سريع جدًا)،
  // بنفس دوال مكتبة image المُختبَرة سابقًا (بدون إعادة اختراع رياضيات
  // الدوران يدويًا، تفاديًا لأي خطأ بالاتجاه).
  var processed = sampled;
  if (job.sensorOrientation == 90) {
    processed = img.copyRotate(processed, angle: 90);
  } else if (job.sensorOrientation == 270) {
    processed = img.copyRotate(processed, angle: -90);
  }

  if (processed.width != targetSize || processed.height != targetSize) {
    processed = img.copyResize(
      processed,
      width: targetSize,
      height: targetSize,
    );
  }

  // استخراج البايتات كمصفوفة مسطّحة دفعة واحدة — أسرع بكثير من قراءة
  // كل بكسل لحاله عبر getPixel (اللي ينشئ كائن Pixel بكل استدعاء).
  final rgbBytes = processed.getBytes(order: img.ChannelOrder.rgb);

  return ConvertedFrame(rgbBytes, targetSize);
}