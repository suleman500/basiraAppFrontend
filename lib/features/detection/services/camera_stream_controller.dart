import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// يغلّف الـ`CameraController` الخام من حزمة `camera` — التهيئة،
/// التبديل بين كاميرتين، وتشغيل/إيقاف البث بأمان (قفل تزامن يمنع
/// استدعاءين متزامنين لـstartImageStream/stopImageStream، اللي كان
/// سبب تعليق الكاميرا قبل ما نضيف هالحماية).
///
/// ⚠️ عمدًا **ما بيعرف شي عن `_isRunning`** ولا "متى" لازم نفتح
/// كاميرا — هذا قرار منطق الشاشة (صوت/دفعة قصيرة/توجيه)، مش شغلة
/// هالكلاس. هالكلاس بس مسؤول عن "كيف" ننفّذ التشغيل/الإيقاف بأمان،
/// بغض النظر عن "ليش" — نفس مبدأ الفصل اللي استخدمناه بباقي
/// الكنترولرز (ProximityAnnouncer، HandGestureController...).
class CameraStreamController {
  CameraController? _controller;
  bool _busy = false;
  int _cameraIndex = 0;

  CameraController? get controller => _controller;
  int get cameraIndex => _cameraIndex;

  /// true لو فيه عملية تشغيل/إيقاف بث شغّالة حاليًا — أي طرف بالشاشة
  /// بدّه يتصرّف بناءً عليه (مثلًا يرفض يبدأ عملية جديدة) لازم يتحقق
  /// من هالقيمة قبل ما يستدعي tryStartStream/tryStopStream.
  bool get isBusy => _busy;

  /// ينشئ CameraController جديد لكاميرا [index] من [cameras]، يهيّئه
  /// (تركيز وتعريض تلقائيين)، ويقفل القديم (لو موجود) بعد ما الجديد
  /// يصير جاهز — بدون أي فجوة زمنية تفقد فيها الشاشة كاميرا شغالة.
  Future<void> initialize(List<CameraDescription> cameras, int index) async {
    final oldController = _controller;

    final controller = CameraController(
      cameras[index],
      ResolutionPreset.medium,
      enableAudio: false,
    );

    _controller = controller;
    _cameraIndex = index;

    await controller.initialize();

    try {
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);
    } catch (e) {
      debugPrint('Camera settings error: $e');
    }

    await oldController?.dispose();
  }

  /// يشغّل بث الكاميرا بأمان — يرفض العمل لو فيه عملية تانية عالبث
  /// شغّالة أصلًا ([isBusy]). التحقق والتعيين هون متزامنين (sync،
  /// بدون await بينهم)، فما فيه فرصة لاستدعاءين "يشوفوا" القفل فاضي
  /// بنفس اللحظة — أول وحدة بتاخده، والتانية بترجع false فورًا.
  Future<bool> tryStartStream(void Function(CameraImage) onFrame) async {
    if (_busy) {
      debugPrint('⚠️ تجاهلت طلب تشغيل الكاميرا — عملية تانية شغّالة عليها');
      return false;
    }

    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return false;

    _busy = true;
    try {
      await controller.startImageStream(onFrame);
      return true;
    } catch (e) {
      debugPrint('⚠️ فشل تشغيل بث الكاميرا: $e');
      return false;
    } finally {
      _busy = false;
    }
  }

  /// يوقف بث الكاميرا بأمان — نفس مبدأ [tryStartStream] بالضبط.
  Future<void> tryStopStream() async {
    if (_busy) {
      debugPrint('⚠️ تجاهلت طلب إيقاف الكاميرا — عملية تانية شغّالة عليها');
      return;
    }

    final controller = _controller;
    if (controller == null) return;

    _busy = true;
    try {
      await controller.stopImageStream();
    } catch (e) {
      debugPrint('⚠️ خطأ أثناء إيقاف بث الكاميرا: $e');
    } finally {
      _busy = false;
    }
  }

  /// يقفل الكاميرا نهائيًا — يُستدعى من dispose() بالشاشة. ما منستنى
  /// (await) نتيجتها هناك عمدًا (نفس السلوك الأصلي)، لأنه State.
  /// dispose() لازم يضل synchronous.
  Future<void> dispose() async {
    await _controller?.dispose();
    _controller = null;
  }
}