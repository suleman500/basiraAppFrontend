# تراخيص الطرف الثالث (Third-Party Licenses)

هذا الملف يوثّق كل النماذج والمكتبات والبيانات الخارجية المستخدمة في مشروع "بصيرة"، مصدرها، وترخيصها.

> **منهج التحقق:** شُغّل `flutter pub deps --json` لتثبيت قائمة الإصدارات المحلولة، ثم فُحص ملف `LICENSE` في كل حزمة مباشرة/تطوير. الأمر نفسه لا يحتوي بيانات رخص. لم يوجد في مجلد أوزان STT ملف LICENSE أو README أو metadata يثبت المصدر والترخيص. بيانات MiDaS v2.1 Small وIntel ISL أدناه مأخوذة من NOTICE المرفق؛ metadata المحلية تؤكد بنية MiDaS وEfficientNet-Lite3 لكنها لا تثبت الإصدار أو مصدر checkpoint.

---

## بيانات ونماذج الصوت (Audio / TTS / STT)

### espeak-ng-data (‎`assets/models/tts-ar/espeak-ng-data/`)
- **المصدر:** مشروع [espeak-ng](https://github.com/espeak-ng/espeak-ng)
- **الترخيص:** GPL-3.0-or-later
- **الأثر على مشروعك:** بما أن هذا المكوّن GPL، فإن أبسط وأضمن طريق قانوني هو ترخيص مشروع "بصيرة" بالكامل تحت GPL-3.0-or-later (انظر ملف `LICENSE` في جذر المشروع).
- نص الترخيص الكامل: انظر `COPYING` في مستودع espeak-ng الرسمي.

### نماذج sherpa-ar-stt (‎`assets/models/sherpa-ar-stt/`)
- **المصدر/المعمارية:** يحدد `SpeechService` النموذج على أنه Moonshine، لكن مجلد الأصول يحوي فقط encoder وdecoder و`tokens.txt`؛ لا يسجل رابط checkpoint أو مصدر تنزيله.
- **الترخيص:** غير محسوم من الملفات المحلية. لم يوجد LICENSE أو README أو ملف metadata يحدد ترخيص الأوزان؛ لا يُستنتج ترخيصها من ترخيص مكتبة sherpa_onnx.

### مكتبة sherpa_onnx (حزمة pub.dev)
- **الإصدار المحلول:** 1.13.7
- **الترخيص:** Apache-2.0 (من `LICENSE` داخل الحزمة)

### مكتبات الصوت الأخرى
- `flutter_tts` 4.2.5: MIT.
- `record` 6.2.1: BSD-3-Clause.
- `audioplayers` 6.7.1: MIT.

---

## نماذج الرؤية الحاسوبية (Detection / Depth)

### model.tflite (YOLOX)
- **المصدر:** [Megvii-BaseDetection/YOLOX](https://github.com/Megvii-BaseDetection/YOLOX)
- **الترخيص:** Apache License 2.0
- **المتطلبات:** الإبقاء على إشعار حقوق النشر ونص الترخيص عند التوزيع؛ لا يلزم فتح كود تطبيقك بسبب هذا المكون وحده.

### midas_small.tflite (MiDaS)
- **المصدر الموثق في NOTICE المرفق:** [isl-org/MiDaS](https://github.com/isl-org/MiDaS)، إصدار MiDaS v2.1 Small محوّل إلى TFLite. تتضمن metadata المحلية أسماء `midas_net_custom` و`efficientnet-lite3`، لكنها لا تثبت الإصدار أو مصدر checkpoint بذاتها.
- **الترخيص حسب NOTICE المرفق:** MIT لأوزان MiDaS، وApache-2.0 للـbackbone EfficientNet-Lite3.
- **للمراجعة قبل التوزيع:** أرفق أو احتفظ بسجل مصدر checkpoint وخطوة التحويل وإشعارات الترخيص المصاحبة لهما؛ لم توجد ملفات LICENSE/README بجوار `midas_small.tflite`.

### hand_landmarker.task
- **المصدر:** MediaPipe (Google)
- **الترخيص حسب NOTICE المرفق:** Apache License 2.0. لا يوجد ملف LICENSE منفصل بجوار أصل النموذج.
- **الحالة:** غير مفعّل حاليًا في التطبيق (`handTrackingEnabled = false`).

---

## حزم Flutter/Dart (pub.dev)

نفّذ `flutter pub deps --json` للتحقق من شجرة الحزم والإصدارات المحلولة (173 حزمة إجمالًا في نتيجة الفحص). يعرض الأمر الاعتمادات والإصدارات، لا حقول الترخيص؛ الرخصة أدناه من ملف `LICENSE` في نسخة الحزمة المحلولة. الجدول يغطي كل إدخالات `dependencies` و`dev_dependencies` في `pubspec.yaml`، بما فيها حزمتا Flutter SDK.

| الحزمة | الإصدار المحلول | الترخيص المثبت من الحزمة |
|---|---:|---|
| `cupertino_icons` | 1.0.9 | MIT |
| `camera` | 0.12.0+2 | BSD-3-Clause |
| `image` | 4.3.0 | MIT؛ يوجد أيضًا `LICENSE-other.md` لإشعارات إضافية |
| `tflite_flutter` | 0.12.1 | Apache-2.0 |
| `flutter_tts` | 4.2.5 | MIT |
| `sherpa_onnx` | 1.13.7 | Apache-2.0 |
| `record` | 6.2.1 | BSD-3-Clause |
| `video_player` | 2.11.1 | BSD-3-Clause |
| `audioplayers` | 6.7.1 | MIT |
| `path_provider` | 2.1.6 | BSD-3-Clause |
| `path` | 1.9.1 | BSD-3-Clause |
| `freezed_annotation` | 3.1.0 | MIT |
| `json_annotation` | 4.12.0 | BSD-3-Clause |
| `flutter_bloc` | 9.1.1 | MIT |
| `equatable` | 2.1.0 | MIT |
| `dartz` | 0.10.1 | MIT |
| `image_picker` | 1.2.3 | BSD-3-Clause |
| `http` | 1.6.0 | BSD-3-Clause |
| `cached_network_image` | 3.4.1 | MIT |
| `dio` | 5.11.0 | MIT |
| `shared_preferences` | 2.5.5 | BSD-3-Clause |
| `uuid` | 4.6.0 | MIT |
| `sensors_plus` | 7.1.0 | BSD-3-Clause |
| `arabic_search` | 0.2.3 | MIT |
| `flutter_lints` (dev) | 6.0.0 | BSD-3-Clause |
| `build_runner` (dev) | 2.15.1 | BSD-3-Clause |
| `freezed` (dev) | 3.2.5 | MIT |
| `json_serializable` (dev) | 6.14.1 | BSD-3-Clause |
| `flutter` (SDK) | Flutter SDK | BSD-3-Clause |
| `flutter_test` (SDK, dev) | Flutter SDK | BSD-3-Clause |

---

## كيف تستخدم هذا الملف

1. أبقِ هذا الملف في جذر المشروع بجانب `LICENSE.txt` و`NOTICE`.
2. اربطه من `README.md` تحت قسم "Licenses" أو "Third-Party Notices".
3. حدّثه كلما أضفت نموذجًا أو حزمة جديدة.
4. احصل على مصدر التنزيل وشروط الترخيص الأصلية لأوزان STT وMiDaS وMediaPipe قبل توزيعها، ثم حدّث الإدخالات غير المحسومة أعلاه.