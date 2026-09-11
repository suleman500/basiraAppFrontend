import '../models/detected_object.dart';
import '../../voice/data/labels_ar.dart';

/// بيانات جسم واحد بصيغة منظّمة وخام تمامًا — بدون أي نص جاهز للنطق
/// أو صياغة عربية جاهزة (زي "أمامك على يمينك"). الهدف: تغذية نموذج AI
/// خارجي لاحقًا يستقبل هالبيانات ويصوغ الجملة النهائية بنفسه، فمافي
/// داعي نصوغ نحن أي جملة هون — بس أرقام وأسماء خام.
class DetectedObjectSummary {
  /// اسم الجسم بالعربي (من labels_ar.dart).
  final String nameAr;

  /// اسم الجسم بالإنجليزي (زي ما يرجّعه الموديل، مفيد لو الـAI
  /// يحتاج مرجع ثابت بدل الاعتماد على الترجمة العربية فقط).
  final String nameEn;

  /// قيمة العمق الخام (نسبية من MiDaS، مو أمتار حقيقية) — null لو ما
  /// كان في قياس مسافة حديث متاح لهذا الجسم وقت الاستخراج.
  final double? distance;

  /// عرض صندوق الجسم بالبكسل (بمقياس إطار الكاميرا الفعلي).
  final double width;

  /// ارتفاع صندوق الجسم بالبكسل (بمقياس إطار الكاميرا الفعلي).
  final double height;

  /// عرض الصندوق كنسبة من عرض الصورة كاملة (0..1) — مؤشر حجم نسبي
  /// بغض النظر عن دقة الكاميرا، مفيد أكتر من البكسل الخام لأي AI.
  final double widthRatio;

  /// ارتفاع الصندوق كنسبة من ارتفاع الصورة كاملة (0..1).
  final double heightRatio;

  /// إحداثي مركز الصندوق أفقيًا كنسبة من عرض الصورة (0 = أقصى
  /// اليسار، 1 = أقصى اليمين، 0.5 = المنتصف تمامًا).
  final double centerXRatio;

  /// إحداثي مركز الصندوق عموديًا كنسبة من ارتفاع الصورة (0 = الأعلى،
  /// 1 = الأسفل).
  final double centerYRatio;

  /// ثقة الموديل بالكشف (0..1).
  final double confidence;

  const DetectedObjectSummary({
    required this.nameAr,
    required this.nameEn,
    required this.distance,
    required this.width,
    required this.height,
    required this.widthRatio,
    required this.heightRatio,
    required this.centerXRatio,
    required this.centerYRatio,
    required this.confidence,
  });

  /// تحويل لصيغة Map بسيطة (مفاتيح إنجليزية ثابتة) — جاهزة لتمريرها
  /// مباشرة كـJSON بجسم طلب لأي API خارجي (زي نموذج AI يصوغ الجملة).
  Map<String, dynamic> toJson() {
    return {
      'name_ar': nameAr,
      'name_en': nameEn,
      'distance': distance,
      'width': width,
      'height': height,
      'width_ratio': widthRatio,
      'height_ratio': heightRatio,
      'center_x_ratio': centerXRatio,
      'center_y_ratio': centerYRatio,
      'confidence': confidence,
    };
  }
}

/// يحوّل قائمة DetectedObject (خارجة من الموديل/الشاشة مباشرة) لقائمة
/// DetectedObjectSummary — بيانات خام منظّمة بس، بدون أي صياغة جملة.
///
/// [imageWidth] و[imageHeight] هما نفس fullWidth/fullHeight المستخدَمين
/// أصلًا بـdetection_screen.dart (أبعاد إطار الكاميرا الفعلي، مو حجم
/// إدخال الموديل) — ضروريان لحساب النسب (width_ratio، center_x_ratio...).
List<DetectedObjectSummary> buildObjectSummaries(
    List<DetectedObject> detections, {
      required int imageWidth,
      required int imageHeight,
    }) {
  if (imageWidth <= 0 || imageHeight <= 0) return const [];

  return detections.map((obj) {
    return DetectedObjectSummary(
      nameAr: toArabicLabel(obj.label),
      nameEn: obj.label,
      distance: obj.distance > 0 ? obj.distance : null,
      width: obj.box.width,
      height: obj.box.height,
      widthRatio: obj.box.width / imageWidth,
      heightRatio: obj.box.height / imageHeight,
      centerXRatio: obj.box.center.dx / imageWidth,
      centerYRatio: obj.box.center.dy / imageHeight,
      confidence: obj.confidence,
    );
  }).toList();
}


