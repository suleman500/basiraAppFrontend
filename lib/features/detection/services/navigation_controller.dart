import '../../voice/data/labels_ar.dart';
import '../../voice/services/voice_announcer.dart';
import '../models/detected_object.dart';
import '../services/gyroscope_service.dart';
import '../../../core/constants.dart';

/// نتيجة معالجة إطار وحدة أثناء التوجيه — الشاشة تستخدمها بس عشان
/// تقرر "هل لازم أقفل الكاميرا؟" (لما تكون [arrived]). كل النطق
/// والقرارات الداخلية (فقدان، عائق، تقدّم) تصير جوا [NavigationController]
/// نفسه — الشاشة ما لازم تعرف تفاصيلها.
enum NavigationTick {
  /// ما في توجيه شغّال أصلًا — الشاشة ما لازم تستدعي handleFrame
  /// أصلًا بهالحالة عادةً (بتتحقق من isNavigating قبل)، موجودة هون
  /// للاكتمال بس.
  notNavigating,

  /// وصل الهدف — التوجيه خلص، الشاشة لازم تقفل الكاميرا لو هي
  /// فتحتها لأجل هالتوجيه.
  arrived,

  /// لسا ماشي — التوجيه مستمر (سواء طالع الهدف بالكادر أو مفقود
  /// مؤقتًا وبيحاول يرجع يلاقيه).
  progressing,
}

/// آلة حالة التوجيه — بدء، إلغاء، ومتابعة الهدف كل إطار لحد ما يوصل
/// أو يُلغى. مستقل عن حالة الكاميرا (فتح/قفل البث مو شغلته — راجع
/// NavigationTick.arrived أعلاه، الشاشة هي اللي بتقرر شو تسوي).
///
/// يحتاج [GyroscopeService] (لتخمين اتجاه المستخدم لما الهدف يضيع
/// من الكادر) و[VoiceAnnouncer] (لنطق كل التحديثات) عبر الحقن.
class NavigationController {
  final GyroscopeService gyro;
  final VoiceAnnouncer voice;

  NavigationController({required this.gyro, required this.voice});

  String? _targetLabel;
  String? _targetId;

  DateTime? _lastNavigationAnnounce;
  DateTime? _lastObstacleWarning;
  DateTime? _lastLostAnnounce;

  bool get isNavigating => _targetLabel != null;

  /// يبدأ توجيه جديد نحو [target] — يصفّر الجيروسكوب وينطق رسالة
  /// البداية. المستدعي (الشاشة) مسؤول عن setState بعدها لو محتاج
  /// يحدّث الواجهة (زر إلغاء التوجيه مثلًا).
  void start(DetectedObject target) {
    _targetLabel = target.label;
    _targetId = target.trackingKey;
    _lastNavigationAnnounce = null;
    _lastObstacleWarning = null;
    _lastLostAnnounce = null;

    gyro.resetYaw();

    voice.speakNow(
      'بدأنا التوجّه نحو ${toArabicLabel(target.label)}. امشِ للأمام ببطء',
    );
  }

  /// يلغي التوجيه الحالي **وينطق** "تم إلغاء التوجيه" — للاستخدام لما
  /// المستخدم يطلب الإلغاء صراحة ("وقف"). لا يعمل شي لو ما في توجيه
  /// شغّال أصلًا.
  void cancel() {
    if (!isNavigating) return;

    _clearTarget();
    voice.speakNow('تم إلغاء التوجيه');
  }

  /// يلغي التوجيه **بهدوء (بدون نطق)** — للاستخدام لما الشاشة نفسها
  /// بدّها تنطق رسالة مختلفة بنفسها (مثلًا "أوقفت التوجيه." وقت
  /// المقاطعة بأمر جديد)، أو وقت إيقاف الكشف يدويًا بالكامل.
  void cancelSilently() {
    _clearTarget();
  }

  void _clearTarget() {
    _targetLabel = null;
    _targetId = null;
    _lastNavigationAnnounce = null;
    _lastObstacleWarning = null;
    _lastLostAnnounce = null;
  }

  /// يعالج إطار وحدة: يدوّر على الهدف بـ[currentDetections]، ينطق
  /// تحديث مناسب (وصلت/فقدان مع تخمين اتجاه/تحذير عائق/استمر بالمشي)،
  /// ويرجّع [NavigationTick] يوصف شو صار — الشاشة بس بتحتاج تتحقق
  /// من [NavigationTick.arrived] لتقرر قفل الكاميرا.
  Future<NavigationTick> handleFrame(
      List<DetectedObject> currentDetections,
      int fullWidth,
      int fullHeight,
      ) async {
    final targetLabel = _targetLabel;
    if (targetLabel == null) return NavigationTick.notNavigating;

    final targetId = _targetId;

    DetectedObject? target;
    for (final obj in currentDetections) {
      if (obj.label != targetLabel) continue;
      if (targetId != null && obj.trackingKey == targetId) {
        target = obj;
        break;
      }
    }

    if (target == null) {
      final now = DateTime.now();

      final canAnnounce = _lastLostAnnounce == null ||
          now.difference(_lastLostAnnounce!) >
              Duration(
                seconds: AppConstants.navigationLostAnnounceCooldownSeconds,
              );

      if (canAnnounce) {
        _lastLostAnnounce = now;

        final yaw = gyro.cumulativeYaw;

        if (yaw.abs() < AppConstants.gyroMinYawToGuessDirection) {
          voice.speakNow(
            'فقدت ${toArabicLabel(targetLabel)} من مجال الرؤية، '
                'وجّه الكاميرا نحوه',
          );
        } else {
          final turnedLeft = AppConstants.gyroYawPositiveMeansTurnedLeft
              ? yaw > 0
              : yaw < 0;

          final direction = turnedLeft ? 'اليسار' : 'اليمين';
          final correction = turnedLeft ? 'يمين' : 'يسار';

          voice.speakNow(
            'التفتّ ل$direction، ارجع شوي لل$correction حتى نرجع '
                'نلاقي ${toArabicLabel(targetLabel)}',
          );
        }
      }

      return NavigationTick.progressing;
    }

    _lastLostAnnounce = null;

    gyro.resetYaw();

    final heightRatio = target.box.height / fullHeight;

    if (heightRatio >= AppConstants.navigationArrivalBoxHeightRatio) {
      voice.speakNow('وصلت! ${toArabicLabel(targetLabel)} أمامك مباشرة');

      _clearTarget();
      return NavigationTick.arrived;
    }

    final now = DateTime.now();

    for (final obj in currentDetections) {
      if (identical(obj, target)) continue;

      final areaRatio =
          (obj.box.width * obj.box.height) / (fullWidth * fullHeight);

      final centerOffset =
          (obj.box.center.dx - fullWidth / 2).abs() / fullWidth;

      final isObstacle =
          areaRatio >= AppConstants.navigationObstacleBoxAreaRatio &&
              centerOffset <= AppConstants.navigationObstacleCenterTolerance;

      if (!isObstacle) continue;

      final canWarn = _lastObstacleWarning == null ||
          now.difference(_lastObstacleWarning!) >
              Duration(seconds: AppConstants.navigationObstacleCooldownSeconds);

      if (canWarn) {
        _lastObstacleWarning = now;
        voice.speakNow('انتبه! ${toArabicLabel(obj.label)} أمامك مباشرة');
      }

      break;
    }

    final canAnnounceProgress = _lastNavigationAnnounce == null ||
        now.difference(_lastNavigationAnnounce!) >
            Duration(
              seconds: AppConstants.navigationProgressAnnounceCooldownSeconds,
            );

    if (canAnnounceProgress) {
      _lastNavigationAnnounce = now;
      voice.speakNow('استمر بالمشي');
    }

    return NavigationTick.progressing;
  }
}