import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../core/constants.dart';
import 'frame_converter.dart';

/// حالة الجسم بالذاكرة — بالضبط 3 حالات، بدون أي تعقيد إضافي:
/// - active: نشوفه حاليًا (أو شفناه بآخر عدة ثوانٍ قريبة).
/// - lost: كان نشط، اختفى من الكاميرا لفترة، بس لسا "حديث" كفاية
///   نعتبره مرجع مفيد (نعرف آخر موقع/اتجاه معروف له).
/// - archived: اختفى لفترة طويلة، على الأغلب ما عاد بالمشهد إطلاقًا.
enum ObjectStatus { active, lost, archived }

/// الموقع الأفقي للجسم بالصورة (تقسيم الإطار لثلاث مناطق).
enum HorizontalPosition { left, center, right }

/// الموقع الرأسي للجسم بالصورة (تقسيم الإطار لثلاث مناطق).
enum VerticalPosition { top, middle, bottom }

/// سجل كامل لجسم محفوظ بالذاكرة — هذا الشكل العام اللي أي كود خارجي
/// (مدير الأوامر الصوتية مستقبلًا، مثلًا) بيتعامل معه، بدل ما يوصل
/// للتفاصيل الداخلية (_MemoryEntry) مباشرة.
class ObjectMemoryRecord {
  final String id;
  final String label;
  final double confidence;
  final HorizontalPosition horizontalPosition;
  final VerticalPosition verticalPosition;
  final double? distance;
  final DateTime lastSeenAt;
  final ObjectStatus status;

  const ObjectMemoryRecord({
    required this.id,
    required this.label,
    required this.confidence,
    required this.horizontalPosition,
    required this.verticalPosition,
    required this.distance,
    required this.lastSeenAt,
    required this.status,
  });

  /// وصف الاتجاه بالعربي بالنسبة للمستخدم (نفس صيغة السيناريو المتفق
  /// عليه: "أمامك على اليمين"). الموقع الرأسي (فوق/تحت) يُذكر بس لو
  /// كان واضح ومفيد (مو "بالنص" رأسيًا، وهو الغالب لمعظم الأجسام).
  String get arabicDirection {
    final horizontal = switch (horizontalPosition) {
      HorizontalPosition.left => 'على يسارك',
      HorizontalPosition.center => 'أمامك بالنص',
      HorizontalPosition.right => 'على يمينك',
    };

    if (horizontalPosition == HorizontalPosition.center) {
      return 'أمامك بالنص';
    }

    return 'أمامك $horizontal';
  }
}

class _MemoryEntry {
  final String id;
  final String label;
  final List<double> fingerprint;
  int seenCount;
  int lastSeen;

  double confidence;
  HorizontalPosition horizontalPosition;
  VerticalPosition verticalPosition;
  double? distance;
  ObjectStatus status;

  _MemoryEntry({
    required this.id,
    required this.label,
    required this.fingerprint,
    required this.seenCount,
    required this.lastSeen,
    this.confidence = 0.0,
    this.horizontalPosition = HorizontalPosition.center,
    this.verticalPosition = VerticalPosition.middle,
    this.distance,
    this.status = ObjectStatus.active,
  });

  ObjectMemoryRecord toRecord() {
    return ObjectMemoryRecord(
      id: id,
      label: label,
      confidence: confidence,
      horizontalPosition: horizontalPosition,
      verticalPosition: verticalPosition,
      distance: distance,
      lastSeenAt: DateTime.fromMillisecondsSinceEpoch(lastSeen),
      status: status,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'fingerprint': fingerprint,
      'seenCount': seenCount,
      'lastSeen': lastSeen,
      'confidence': confidence,
      'horizontalPosition': horizontalPosition.name,
      'verticalPosition': verticalPosition.name,
      'distance': distance,
      'status': status.name,
    };
  }

  factory _MemoryEntry.fromJson(
      Map<String, dynamic> json,
      ) {
    return _MemoryEntry(
      id: json['id'] as String,
      label: json['label'] as String,
      fingerprint: (json['fingerprint'] as List)
          .map((value) => (value as num).toDouble())
          .toList(),
      seenCount: (json['seenCount'] as num?)?.toInt() ?? 1,
      lastSeen: (json['lastSeen'] as num?)?.toInt() ?? 0,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
      horizontalPosition: HorizontalPosition.values.firstWhere(
            (v) => v.name == json['horizontalPosition'],
        orElse: () => HorizontalPosition.center,
      ),
      verticalPosition: VerticalPosition.values.firstWhere(
            (v) => v.name == json['verticalPosition'],
        orElse: () => VerticalPosition.middle,
      ),
      distance: (json['distance'] as num?)?.toDouble(),
      status: ObjectStatus.values.firstWhere(
            (v) => v.name == json['status'],
        orElse: () => ObjectStatus.active,
      ),
    );
  }
}

class ObjectMemoryMatch {
  final String id;
  final bool isNew;

  const ObjectMemoryMatch({
    required this.id,
    required this.isNew,
  });
}

class ObjectMemoryService {
  static const int _gridSize = 6;

  final List<_MemoryEntry> _entries = [];

  late File _memoryFile;
  bool _initialized = false;
  Timer? _saveTimer;

  int get count => _entries.length;

  Future<void> init() async {
    if (_initialized) return;

    final directory =
    await getApplicationDocumentsDirectory();

    _memoryFile = File(
      path.join(
        directory.path,
        'detected_objects_memory.json',
      ),
    );

    if (await _memoryFile.exists()) {
      try {
        final text = await _memoryFile.readAsString();

        final decoded = jsonDecode(text);

        if (decoded is List) {
          _entries
            ..clear()
            ..addAll(
              decoded
                  .whereType<Map>()
                  .map(
                    (item) => _MemoryEntry.fromJson(
                  Map<String, dynamic>.from(item),
                ),
              ),
            );
        }
      } catch (e) {
        debugPrint(
          'Could not load object memory: $e',
        );
      }
    }

    _initialized = true;

    debugPrint(
      'Object memory loaded: ${_entries.length}',
    );
  }

  /// يصنع بصمة صغيرة من منطقة الجسم.
  /// لا يتم حفظ الصورة، فقط أرقام RGB مختصرة.
  List<double> fingerprintFor({
    required ConvertedFrame frame,
    required Rect box,
    required int fullWidth,
    required int fullHeight,
  }) {
    final size = frame.size;
    final bytes = frame.rgbBytes;

    if (bytes.isEmpty || fullWidth <= 0 || fullHeight <= 0) {
      return [];
    }

    var left =
    (box.left / fullWidth * size).round();
    var top =
    (box.top / fullHeight * size).round();
    var right =
    (box.right / fullWidth * size).round();
    var bottom =
    (box.bottom / fullHeight * size).round();

    left = left.clamp(0, size - 1);
    top = top.clamp(0, size - 1);
    right = right.clamp(left + 1, size);
    bottom = bottom.clamp(top + 1, size);

    // نأخذ الجزء الداخلي من الجسم لتقليل تأثير الخلفية.
    final width = right - left;
    final height = bottom - top;

    final innerLeft =
    (left + width * 0.15).round();
    final innerTop =
    (top + height * 0.15).round();
    final innerRight =
    (right - width * 0.15).round();
    final innerBottom =
    (bottom - height * 0.15).round();

    final result = <double>[];

    for (int gy = 0; gy < _gridSize; gy++) {
      for (int gx = 0; gx < _gridSize; gx++) {
        final x = innerLeft +
            ((innerRight - innerLeft - 1) *
                gx /
                (_gridSize - 1))
                .round();

        final y = innerTop +
            ((innerBottom - innerTop - 1) *
                gy /
                (_gridSize - 1))
                .round();

        final index = (y * size + x) * 3;

        if (index < 0 || index + 2 >= bytes.length) {
          result.addAll([0.0, 0.0, 0.0]);
          continue;
        }

        result.add(bytes[index] / 255.0);
        result.add(bytes[index + 1] / 255.0);
        result.add(bytes[index + 2] / 255.0);
      }
    }

    return result;
  }

  /// يحسب الموقع الأفقي/الرأسي للجسم بتقسيم الإطار لثلاث مناطق بكل
  /// محور (تسعة مربعات إجمالًا، زي شبكة تيك تاك تو).
  ({HorizontalPosition horizontal, VerticalPosition vertical})
  _positionFor({
    required Rect box,
    required int fullWidth,
    required int fullHeight,
  }) {
    final centerX = box.center.dx;
    final centerY = box.center.dy;

    final horizontal = centerX < fullWidth / 3
        ? HorizontalPosition.left
        : (centerX > fullWidth * 2 / 3
        ? HorizontalPosition.right
        : HorizontalPosition.center);

    final vertical = centerY < fullHeight / 3
        ? VerticalPosition.top
        : (centerY > fullHeight * 2 / 3
        ? VerticalPosition.bottom
        : VerticalPosition.middle);

    return (horizontal: horizontal, vertical: vertical);
  }

  /// يبحث عن الجسم في الذاكرة أو ينشئ سجلًا جديدًا، ويحدّث كل الحقول
  /// الجديدة (الموقع، الثقة، المسافة، الحالة = active دائمًا هون لأن
  /// هذا الاستدعاء أصلًا معناه "شفنا الجسم هلق").
  Future<ObjectMemoryMatch> remember({
    required String label,
    required List<double> fingerprint,
    required Rect box,
    required int fullWidth,
    required int fullHeight,
    double confidence = 0.0,
    double? distance,
  }) async {
    if (!_initialized) {
      await init();
    }

    final position = _positionFor(
      box: box,
      fullWidth: fullWidth,
      fullHeight: fullHeight,
    );

    if (fingerprint.isEmpty) {
      return ObjectMemoryMatch(
        id: 'temporary_$label',
        isNew: false,
      );
    }

    int bestIndex = -1;
    double bestDistance = double.infinity;

    for (int i = 0; i < _entries.length; i++) {
      final entry = _entries[i];

      // لا نقارن كرسيًا بزجاجة مثلًا.
      if (entry.label != label) continue;

      final fingerprintDistance = _fingerprintDistance(
        entry.fingerprint,
        fingerprint,
      );

      if (fingerprintDistance < bestDistance) {
        bestDistance = fingerprintDistance;
        bestIndex = i;
      }
    }

    // الجسم موجود سابقًا — نحدّث كل حقوله.
    if (bestIndex >= 0 &&
        bestDistance <=
            AppConstants.memoryMatchThreshold) {
      final entry = _entries[bestIndex];

      entry.seenCount++;
      entry.lastSeen = DateTime.now().millisecondsSinceEpoch;
      entry.confidence = confidence;
      entry.horizontalPosition = position.horizontal;
      entry.verticalPosition = position.vertical;
      entry.distance = distance;
      entry.status = ObjectStatus.active;

      // تحديث السجل الموجود يجب أن يستمر على القرص أيضًا، وإلا ستبقى
      // استعلامات الصوت بعد إعادة فتح التطبيق على موقع قديم للجسم.
      _scheduleSave();

      return ObjectMemoryMatch(
        id: entry.id,
        isNew: false,
      );
    }

    // جسم جديد.
    final id =
        'object_${DateTime.now().microsecondsSinceEpoch}';

    _entries.add(
      _MemoryEntry(
        id: id,
        label: label,
        fingerprint: List<double>.from(fingerprint),
        seenCount: 1,
        lastSeen: DateTime.now().millisecondsSinceEpoch,
        confidence: confidence,
        horizontalPosition: position.horizontal,
        verticalPosition: position.vertical,
        distance: distance,
        status: ObjectStatus.active,
      ),
    );

    // ⚡ كتابة بالخلفية (fire-and-forget) — راجع تعليق الإصدار السابق
    // لتفاصيل ليش هذا مهم لتجنّب تجمّد المعالجة.
    unawaited(_save());

    debugPrint(
      'New object saved: $id ($label)',
    );

    return ObjectMemoryMatch(
      id: id,
      isNew: true,
    );
  }

  /// يفحص كل الأجسام النشطة (active) ويحوّل أي وحد ما شفناه من فترة
  /// لـ lost، وأي وحد lost من فترة أطول لـ archived. لازم يُستدعى
  /// دوريًا (مثلًا كل إطار معالَج بـ detection_screen.dart) حتى الحالة
  /// تبقى محدَّثة حتى لو الجسم مو موجود بالكادر الحالي إطلاقًا.
  void sweepStatuses() {
    final now = DateTime.now().millisecondsSinceEpoch;
    var changed = false;

    final lostAfterMs =
        AppConstants.objectLostAfterSeconds * 1000;
    final archivedAfterMs =
        AppConstants.objectArchivedAfterSeconds * 1000;

    for (final entry in _entries) {
      final elapsed = now - entry.lastSeen;

      if (entry.status == ObjectStatus.active &&
          elapsed > lostAfterMs) {
        entry.status = ObjectStatus.lost;
        changed = true;
      } else if (entry.status == ObjectStatus.lost &&
          elapsed > archivedAfterMs) {
        entry.status = ObjectStatus.archived;
        changed = true;
      }
    }

    // لا نكتب في كل إطار، فقط إذا حصل تغيير حالة فعلي.
    if (changed) {
      _scheduleSave();
    }
  }

  /// يرجّع أنسب سجل بذاكرة الأجسام لتسمية معيّنة — مفيد لاستعلامات
  /// صوتية مستقبلية ("وين الكرسي؟"). يفضّل active على lost على
  /// archived، وبين المتشابهين بالحالة يختار الأحدث ظهورًا.
  ObjectMemoryRecord? findMostRelevantByLabel(String label) {
    final matches = _entries.where((e) => e.label == label).toList();

    if (matches.isEmpty) return null;

    matches.sort((a, b) {
      final statusOrder = {
        ObjectStatus.active: 0,
        ObjectStatus.lost: 1,
        ObjectStatus.archived: 2,
      };

      final statusCompare =
      statusOrder[a.status]!.compareTo(statusOrder[b.status]!);

      if (statusCompare != 0) return statusCompare;

      return b.lastSeen.compareTo(a.lastSeen);
    });

    return matches.first.toRecord();
  }

  /// كل الأجسام النشطة حاليًا (active بس) — مفيد لاستعلام "شو قدامي؟".
  List<ObjectMemoryRecord> get activeRecords {
    return _entries
        .where((e) => e.status == ObjectStatus.active)
        .map((e) => e.toRecord())
        .toList();
  }

  double _fingerprintDistance(
      List<double> first,
      List<double> second,
      ) {
    if (first.length != second.length ||
        first.isEmpty) {
      return double.infinity;
    }

    double total = 0.0;

    for (int i = 0; i < first.length; i++) {
      total += (first[i] - second[i]).abs();
    }

    return total / first.length;
  }

  Future<void> _save() async {
    try {
      final json = _entries
          .map((entry) => entry.toJson())
          .toList();

      await _memoryFile.writeAsString(
        jsonEncode(json),
        flush: true,
      );
    } catch (e) {
      debugPrint(
        'Could not save object memory: $e',
      );
    }
  }

  /// يجمع تحديثات الإطارات السريعة في كتابة واحدة بدل الكتابة على القرص
  /// مع كل كشف. هذا يحافظ على آخر موقع مفيد للبحث الصوتي بدون إعادة
  /// مشكلة البطء التي كانت موجودة عند الحفظ المتزامن.
  void _scheduleSave() {
    if (_saveTimer != null) return;

    _saveTimer = Timer(const Duration(milliseconds: 700), () {
      _saveTimer = null;
      unawaited(_save());
    });
  }

  Future<void> clear() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    _entries.clear();

    if (await _memoryFile.exists()) {
      await _memoryFile.delete();
    }

    debugPrint('Object memory cleared');
  }
}
