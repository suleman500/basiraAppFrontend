import '../../voice/data/labels_ar.dart';
import '../../voice/services/voice_announcer.dart';
import '../models/detected_object.dart';
import '../services/depth_service.dart';
import '../services/object_memory_service.dart';
import '../../../core/constants.dart';

/// يحوّل نتائج موديل العمق (خرائط عمق خام، تحليل مساحة فاضية) لجمل
/// عربية مسموعة، وينطقها مباشرة. مستقل عن أي حالة واجهة (State/
/// setState/BuildContext) — الخدمات الثلاثة اللي يحتاجها (صوت، عمق،
/// ذاكرة) تُحقَن عبر الـconstructor، فسهل تستبدلها باختبار وهمي
/// (mock) مستقبلًا لو حبيت تكتب unit tests.
///
/// ⚠️ [announceProximity] وحدها بترجع قيمة (خريطة label → فئة قرب)
/// بدل ما تحدّث الحالة مباشرة — لأنه تحديث `_proximityLabels`
/// (لرسم الألوان عالصناديق) قرار عرض/واجهة، مسؤولية الشاشة تحدّثه
/// بـsetState بنفسها، مو هالكلاس.
class ProximityAnnouncer {
  final VoiceAnnouncer voice;
  final DepthService depth;
  final ObjectMemoryService memory;

  const ProximityAnnouncer({
    required this.voice,
    required this.depth,
    required this.memory,
  });

  /// يحلل قرب كل جسم من [objects] بالاعتماد على [depthMap]، ينطق
  /// أقرب جسم (وثاني أقرب لو موجود)، ويرجّع خريطة (label → فئة قرب:
  /// "قريب جدًا"/"قريب"/"متوسط"/"بعيد") لتلوين الصناديق.
  ///
  /// يرجّع null بالحالتين اللي ما في داعي لتحديث التلوين القديم
  /// (لا أجسام أصلًا، أو ما قدرنا نقيس مسافة أي وحدة منها) — الشاشة
  /// يجب ما تلمس _proximityLabels القديمة بهالحالتين، تمامًا متل
  /// السلوك الأصلي قبل الفصل.
  Future<Map<String, String>?> announceProximity(
      List<DetectedObject> objects,
      DepthMap depthMap, {
        required int fullWidth,
        required int fullHeight,
      }) async {
    if (objects.isEmpty) {
      voice.speakNow('ما في أشياء واضحة أمامك الآن');
      return null;
    }

    final withDepth = <MapEntry<DetectedObject, double>>[];

    for (final obj in objects) {
      final rawValue = depth.distanceAt(
        map: depthMap,
        box: obj.box,
        fullWidth: fullWidth,
        fullHeight: fullHeight,
      );

      if (rawValue != null) {
        withDepth.add(MapEntry(obj, rawValue));
      }
    }

    if (withDepth.isEmpty) {
      voice.speakNow('تعذّر تقدير المسافة لهذي الأشياء');
      return null;
    }

    withDepth.sort((a, b) {
      final cmp = AppConstants.depthHigherValueMeansCloser
          ? b.value.compareTo(a.value)
          : a.value.compareTo(b.value);
      return cmp;
    });

    final values = withDepth.map((e) => e.value).toList();
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final maxValue = values.reduce((a, b) => a > b ? a : b);

    final newLabels = <String, String>{};

    for (final entry in withDepth) {
      final category = _proximityCategory(
        value: entry.value,
        minValue: minValue,
        maxValue: maxValue,
        higherIsCloser: AppConstants.depthHigherValueMeansCloser,
      );
      newLabels[entry.key.label] = category;
    }

    final nearestLabel = toArabicLabel(withDepth.first.key.label);

    if (withDepth.length == 1) {
      voice.speakNow('$nearestLabel هو الأقرب إليك');
    } else {
      final secondLabel = toArabicLabel(withDepth[1].key.label);
      voice.speakNow('الأقرب إليك هو $nearestLabel، وبعده $secondLabel');
    }

    return newLabels;
  }

  /// يترجم نتيجة تحليل المساحة الفاضية لجملة عربية واحدة، وينطقها.
  /// يستخدم memory.activeRecords (مو الكشوفات الخام) لتسمية أقرب
  /// جسم بكل اتجاه — نفس مصدر البيانات اللي WhatsAroundCommand
  /// يستخدمه، لاتساق كامل مع بقية التطبيق.
  void announceFreeSpace(FreeSpaceResult result) {
    final nearby = memory.activeRecords;

    String? describeClosestInDirection(HorizontalPosition position) {
      final candidates = nearby
          .where((r) => r.horizontalPosition == position && r.distance != null)
          .toList();

      if (candidates.isEmpty) return null;

      candidates.sort((a, b) => AppConstants.depthHigherValueMeansCloser
          ? b.distance!.compareTo(a.distance!)
          : a.distance!.compareTo(b.distance!));

      final closest = candidates.first;
      final steps = depth.estimateSteps(closest.distance!);
      return '${toArabicLabel(closest.label)} على بعد تقريبًا $steps خطوات';
    }

    if (result.center == PathOpenness.open) {
      final aheadInfo = describeClosestInDirection(HorizontalPosition.center);
      if (aheadInfo != null) {
        voice.speakNow(
            'المساحة فاضية، تقدر تمشي — بس فيه $aheadInfo قدامك بعيد');
      } else {
        voice.speakNow('المساحة فاضية، تقدر تمشي');
      }
      return;
    }

    final centerInfo = describeClosestInDirection(HorizontalPosition.center);
    final obstacleDesc = centerInfo != null ? '، $centerInfo' : '';

    if (result.left == PathOpenness.open) {
      voice.speakNow('ما في مساحة للمشي قدامك$obstacleDesc، بس يسارك فاضي');
    } else if (result.right == PathOpenness.open) {
      voice.speakNow('ما في مساحة للمشي قدامك$obstacleDesc، بس يمينك فاضي');
    } else {
      voice.speakNow(
          'ما في مساحة للمشي$obstacleDesc، انتبه في عائق حواليك بكل الاتجاهات');
    }
  }

  String _proximityCategory({
    required double value,
    required double minValue,
    required double maxValue,
    required bool higherIsCloser,
  }) {
    if ((maxValue - minValue).abs() < 1e-6) {
      return 'متوسط';
    }

    var normalized = (value - minValue) / (maxValue - minValue);

    if (!higherIsCloser) {
      normalized = 1.0 - normalized;
    }

    if (normalized >= 0.75) return 'قريب جدًا';
    if (normalized >= 0.45) return 'قريب';
    if (normalized >= 0.2) return 'متوسط';
    return 'بعيد';
  }
}