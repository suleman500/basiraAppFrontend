import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../core/constants.dart';
import 'frame_converter.dart';

class ObjectMemoryMatch {
  final String id;
  final bool isNew;

  const ObjectMemoryMatch({
    required this.id,
    required this.isNew,
  });
}

class _MemoryEntry {
  final String id;
  final String label;
  final List<double> fingerprint;
  int seenCount;
  int lastSeen;

  _MemoryEntry({
    required this.id,
    required this.label,
    required this.fingerprint,
    required this.seenCount,
    required this.lastSeen,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'fingerprint': fingerprint,
      'seenCount': seenCount,
      'lastSeen': lastSeen,
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
    );
  }
}

class ObjectMemoryService {
  static const int _gridSize = 6;

  final List<_MemoryEntry> _entries = [];

  late File _memoryFile;
  bool _initialized = false;

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

  /// يبحث عن الجسم في الذاكرة أو ينشئ سجلًا جديدًا.
  Future<ObjectMemoryMatch> remember({
    required String label,
    required List<double> fingerprint,
  }) async {
    if (!_initialized) {
      await init();
    }

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

      final distance = _fingerprintDistance(
        entry.fingerprint,
        fingerprint,
      );

      if (distance < bestDistance) {
        bestDistance = distance;
        bestIndex = i;
      }
    }

    // الجسم موجود سابقًا.
    if (bestIndex >= 0 &&
        bestDistance <=
            AppConstants.memoryMatchThreshold) {
      final entry = _entries[bestIndex];

      entry.seenCount++;
      entry.lastSeen =
          DateTime.now().millisecondsSinceEpoch;

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
        lastSeen:
        DateTime.now().millisecondsSinceEpoch,
      ),
    );

    // ⚡ إصلاح أداء مهم: كنا ننتظر (await) كتابة الملف على القرص هون
    // قبل ما نكمل — يعني كل مرة يُعتبر الجسم "جديد" (شائع جدًا لجسم
    // بإيد المستخدم بيتحرك، لأن بصمته اللونية تتغيّر بسبب زاوية
    // الإمساك/الإضاءة/تغطية جزء منه)، التطبيق يتوقف مؤقتًا لحد ما
    // تخلص الكتابة الفعلية على القرص (flush: true تخليها أبطأ خيار).
    // هلق الكتابة تصير "بالخلفية" (fire-and-forget) — معالجة الإطار
    // التالي تكمل فورًا، بدون انتظار.
    unawaited(_save());

    debugPrint(
      'New object saved: $id ($label)',
    );

    return ObjectMemoryMatch(
      id: id,
      isNew: true,
    );
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

  Future<void> clear() async {
    _entries.clear();

    if (await _memoryFile.exists()) {
      await _memoryFile.delete();
    }

    debugPrint('Object memory cleared');
  }
}