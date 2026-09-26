# خارطة طريق مشروع بصيرة

## أ) نظرة عامة عن المشروع (Overview)

بصيرة تطبيق Flutter مبني بلغة Dart، يستهدف مساعدة المستخدم على وصف الأشياء أمامه صوتيًا وتقديم توجيه أساسي إليها. المسار الأساسي يعمل محليًا على الجهاز: كاميرا، كشف أشياء YOLOX، ذاكرة محلية، أوامر عربية منطوقة، ونطق صوتي. يتصل التطبيق أيضًا بخادم اختياري لصياغة الردود وبخادم لجمع صور التدريب.

نقطة الدخول هي `lib/main.dart`: تهيئة Flutter والكاميرات ثم عرض `BasiraHomeScreen`. التطبيق مدعوم ومختبَر على Android فقط؛ التكامل الأصلي المخصص للكشف وميزات الصوت المحلية مبنية ومختبرة على Android. مجلدات iOS وmacOS وLinux وWindows وWeb سقالات Flutter غير مكتملة التكامل.

التبعيات الأساسية: `camera` و`image` لمعالجة الكاميرا والصور، `tflite_flutter` للكشف والعمق البديل، `sherpa_onnx` و`record` للتعرف الصوتي والنطق المحلي، `flutter_tts` كبديل للنطق، `audioplayers` للصوت الناتج، `sensors_plus` للتوجيه، `image_picker` و`http` لتجميع الصور، و`path_provider` و`path` للتخزين المحلي. يستخدم `arabic_search` لتطبيع النص العربي، و`video_player` لفيديو الخلفية. قيد Dart في `pubspec.yaml` هو `^3.10.0`.

## طريقة التشغيل (How to Run)

### المتطلبات الأساسية (Prerequisites)

- Flutter SDK مع Dart بإصدار يطابق القيد `^3.10.0` في `pubspec.yaml`.
- لبناء Android: JDK 17 وAndroid SDK. ملفات Gradle تضبط Java/Kotlin على 17، وتحدد Android Gradle Plugin `9.0.1` وKotlin Gradle Plugin `2.3.20`، بينما يوفّر المشروع Gradle Wrapper بالإصدار `9.1.0`.
- يقرأ `android/settings.gradle.kts` مسار Flutter SDK من `android/local.properties`؛ يلزم أن يشير هذا الملف إلى SDK المثبت محليًا.
- ميزات الكشف والأوامر الصوتية تتطلب جهازًا/محاكيًا يدعم الكاميرا والميكروفون، مع منح الأذونات المطلوبة في Android Manifest.

### التثبيت (Installation)

الأمر الموثق لجلب تبعيات Flutter هو:

```sh
flutter pub get
```

يوثق `README.md` تسلسلًا لاختبار إصلاح الصوت يبدأ بـ`flutter clean` ثم `flutter pub get`؛ التنظيف خطوة لذلك التسلسل وليست موثقة كشرط متكرر لكل تثبيت.

### متغيرات البيئة (Environment Variables)

لم أجد ملف `.env` أو `.env.example`، ولا إعدادًا يقرأ متغيرات بيئة. إعدادات الخوادم معرفة كثوابت في `lib/core/constants.dart`: عنوان خدمة الذكاء الاصطناعي ومفتاحها، وعنوان خادم رفع بيانات التدريب. لم تُدرج أي قيمة سرية هنا؛ المفتاح مضبوط حاليًا داخل التطبيق وليس عبر متغير بيئة.

### أوامر التشغيل (Run Commands)

- **التطوير (Development):** لا يحدد `README.md` أو سكربت بالمشروع أمر تشغيل خاصًا بالتطوير؛ لذلك لم أضف أمرًا غير موثق.
- **وضع الإصدار (Release):** الأمر الوحيد لتشغيل التطبيق الذي وجدته موثقًا في `README.md` هو `flutter run --release` بعد `flutter clean` و`flutter pub get`. هذا يشغّل نسخة Release على هدف Flutter متصل، وليس أمرًا موثقًا لبناء/نشر حزمة إنتاج.

### المنفذ والخطوات الإضافية

- لا يعمل تطبيق Flutter نفسه كخادم HTTP، ولم أجد منفذًا محليًا افتراضيًا له محددًا في المشروع. الثوابت تشير إلى خدمة الذكاء الاصطناعي على المنفذ `3000` وخادم رفع التدريب على المنفذ `5000`؛ هذان منفذا خادمين خارجيين، ولا توجد في هذا المشروع أوامر لتشغيلهما.
- لا توجد إعدادات قاعدة بيانات أو migrations أو seed scripts. ذاكرة الأشياء تُحفظ محليًا في ملف JSON، كما أن ملفات النماذج والصوت مدرجة ضمن أصول Flutter في `pubspec.yaml`.

## ب) بنية الملفات (Project Structure)

```text
.
|-- lib/
|   |-- main.dart
|   |-- core/
|   |   |-- constants.dart
|   |   |-- secrets.example.dart
|   |   `-- utils/arabic_text_utils.dart
|   |-- dev_notes/
|   |   |-- APP_CONSTANTS_HISTORY.md
|   |   |-- DETECTION_SCREEN_NOTES.md
|   |   |-- DETECTOR_DEVELOPMENT_NOTES.md
|   |   `-- DEVELOPMENT_NOTES.md
|   `-- features/
|       |-- detection/
|       |   |-- models/detected_object.dart
|       |   |-- presentation/
|       |   |   |-- basira_home_screen.dart
|       |   |   |-- detection_screen.dart
|       |   |   `-- widgets/
|       |   |       |-- bounding_box_painter.dart
|       |   |       |-- detection_chips_bar.dart
|       |   |       `-- hand_skeleton_painter.dart
|       |   `-- services/
|       |       |-- ai_backend_client.dart
|       |       |-- ai_command_rewriter.dar.dart
|       |       |-- ai_intent_classifier.dart
|       |       |-- ai_response_composer.dart
|       |       |-- ai_response_speaker.dart
|       |       |-- box_animation_controller.dart
|       |       |-- camera_stream_controller.dart
|       |       |-- depth_service.dart
|       |       |-- detection_smoothing.dart
|       |       |-- detector_service.dart
|       |       |-- frame_converter.dart
|       |       |-- gyroscope_service.dart
|       |       |-- hand_gesture_controller.dart
|       |       |-- hand_tracker_service.dart
|       |       |-- native_detector_service.dart
|       |       |-- navigation_controller.dart
|       |       |-- object_memory_service.dart
|       |       |-- object_summary.dart
|       |       |-- proximity_service.dart
|       |       |-- speech_service.dart
|       |       `-- voice_command_parser.dart
|       |-- training/
|       |   |-- models/all_models_freezed.dart
|       |   |-- presentation/
|       |   |   |-- training_functions.dart
|       |   |   `-- training_screen.dart
|       |   `-- services/training_server.dart
|       `-- voice/
|           |-- data/labels_ar.dart
|           `-- services/
|               |-- flutter_tts_adapter.dart
|               |-- sherpa-tts-adapter.dart
|               |-- tts_adapter.dart
|               `-- voice_announcer.dart
|-- assets/
|   |-- labels/labels.txt
|   |-- models/
|   |   |-- model.tflite
|   |   |-- midas_small.tflite
|   |   |-- sherpa-ar-stt/ (encoder, decoder, tokens)
|   |   `-- tts-ar/ (ONNX, tokens, espeak-ng-data)
|   `-- stitch/basira_space_background.mp4
|-- android/
|   `-- app/src/main/ (manifest, Kotlin MainActivity, NativeDetector,
|                      HandTracker.kt, Android resources)
|-- ios/       (Flutter runner, iOS project, assets, test stub)
|-- macos/     (Flutter runner, Xcode project, assets, test stub)
|-- linux/     (CMake configuration and GTK runner)
|-- windows/   (CMake configuration and Win32 Flutter runner)
|-- web/       (index.html, manifest, icons)
|-- test/widget_test.dart
|-- pubspec.yaml
|-- pubspec.lock
|-- analysis_options.yaml
|-- README.md
|-- LICENSE.txt
|-- NOTICE
|-- tts_ar_assets.txt
`-- هيكل المشروع-بصيره.docx
```

مجلد `assets/models/tts-ar/espeak-ng-data/` يحتوي ملفات بيانات صوتية كثيرة متعددة اللغات، وقد أُدرجت مساراتها في `pubspec.yaml` كي ينسخها محرك TTS المحلي إلى تخزين التطبيق. ملفات النماذج والفيديو أصول ثنائية وليست شيفرة مصدرية. مجلدات `.git` و`build` ومخرجات البناء/الحزم المولدة لم تُعامل كشيفرة تطبيق.

## ج) شرح آلية العمل (Architecture / How it Works)

### بدء التطبيق والتنقل

1. `main()` في `lib/main.dart` يهيّئ Flutter ويكتشف الكاميرات، ثم يعرض `BasiraHomeScreen`.
2. `BasiraHomeScreen` يعرض خلفية فيديو وزري الكاميرا والتدريب. يفتح الزر الأول `DetectionScreen` والثاني `TrainingScreen`.

### الكشف عن الأشياء والذاكرة

1. تهيّئ `DetectionScreen` الكاميرا وخدمة الكشف والعمق والصوت والذاكرة والجيروسكوب. الإعداد الحالي يختار `NativeDetectorService`، الذي يرسل بايتات النموذج مرة واحدة عبر `MethodChannel` إلى `NativeDetector.kt`؛ ويشغّل Kotlin الاستدلال على خيط منفصل. `DetectorService` المبني على `tflite_flutter` بديل قابل للاختيار.
2. يعالج التطبيق كل إطار ثانٍ وفق `frameSkip`. يحوّل `frame_converter.dart` بيانات الكاميرا من YUV إلى RGB ويعيد تحجيمها عبر `compute`، ثم يفك `detector_service.dart` مخرجات YOLOX ويطبق NMS. تُنعّم النتائج وتُعرض بواسطة الرسامين وشريط التصنيفات.
3. ينشئ `object_memory_service.dart` بصمة RGB صغيرة للصندوق، ويطابقها مع أشياء من الفئة نفسها. يحفظ الموقع والثقة والمسافة والحالة في ملف JSON محلي، وينقل السجلات بين `active` و`lost` و`archived` مع مرور الوقت.
4. لا يعمل `DepthService` إلا لقياس صريح أو تحليل المساحة. نموذج MiDaS يعطي عمقًا نسبيًا لا قياسًا متريًا؛ معايرة عدد الخطوات الحالية تقديرية وتحتاج تحققًا ميدانيًا.
5. `NavigationController` يتابع الهدف إطارًا بإطار، ويستخدم حجم الصندوق لتقدير الوصول والجيروسكوب لتقديم توجيه عند فقد الهدف. تشغيل الكاميرا وإيقافها وإدارة تنافس البث مسؤولية `CameraStreamController` والشاشة.

### الأوامر الصوتية والرد

1. عند الضغط المطوّل على الميكروفون، يسجل `SpeechService` صوت PCM16 أحادي القناة بمعدل 16 kHz عبر `record`، ثم يمرره إلى `sherpa_onnx`. ولأن التعرف غير متدفق، يعيد فك الصوت المتراكم دوريًا لإظهار نص جزئي.
2. يطبّع `arabic_text_utils.dart` و`labels_ar.dart` النص والأسماء، ثم يحوّل `voice_command_parser.dart` العبارة إلى أمر بحث أو مسح أو توجيه أو استفسار مساحة أو إلغاء. ينفّذ `detection_screen.dart` الأمر: قد يجيب من الذاكرة، أو يشغّل مسح كاميرا قصيرًا، أو يبقي البث مستمرًا أثناء التوجيه.
3. عند تفعيل طبقة الخادم، يعيد `AiCommandRewriter` صياغة الأمر غير المفهوم، ويستطيع `AiResponseComposer` إرسال بيانات الأجسام وصياغة رد وصوت خارجي. عند فشل الشبكة يعود التطبيق إلى الرد المحلي. النطق المحلي يمر عبر `VoiceAnnouncer` وواجهة `TtsAdapter`؛ الإعداد الحالي يختار `SherpaTtsAdapter`، مع `FlutterTtsAdapter` كبديل.

### جمع بيانات التدريب

تتيح `TrainingScreen` اختيار الصور وتحرير مربع تصنيف لكل صورة ثم رفعها بواسطة `TrainingServer` إلى `/upload`. لا تستدعي الواجهة حاليًا مساري `/train` أو `/download_model`، ولا تنفذ تدريب نموذج على الجهاز.

## د) الملفات أو التبعيات المقترح مراجعتها

هذه قائمة مراجعة فقط؛ لم يُحذف أي ملف أو اعتماد. بعض العناصر ميزات معطلة أو احتياطية وليست مرشحة للحذف قبل تأكيد هدف المنتج.

| العنصر | سبب المراجعة | التوصية |
|---|---|---|
| `lib/features/detection/services/ai_intent_classifier.dart` | لا توجد مراجع أو إنشاء للكلاس؛ تعليقات `ai_command_rewriter.dar.dart` تصف إعادة الصياغة كبديل للتصنيف المنظم. | مراجعة عقد الخادم؛ حذف لاحقًا إن لم يعد مسار التصنيف مطلوبًا. |
| `lerpRect` داخل `lib/features/detection/services/detection_smoothing.dart` | لا توجد استدعاءات؛ تحريك الصناديق يستخدم `Rect.lerp`. بقية الملف مستخدمة. | حذف الدالة فقط بعد التأكد من عدم وجود استدعاء خارجي. |
| `android/app/src/main/assets/hand_landmarker.task` و`HandTracker.kt` | ملف النموذج غير مشار إليه في الشيفرة المقروءة، و`HandTracker.kt` فارغ؛ ميزة تتبع اليد معطلة (`handTrackingEnabled = false`). | إبقاؤهما فقط إن كانت ميزة اليد ضمن الخطة؛ وإلا مراجعة حذف الأصل والخدمة والرسام معًا. |
| اعتمادات مباشرة بلا استيرادات في `lib`: `cupertino_icons`, `freezed_annotation`, `json_annotation`, `flutter_bloc`, `equatable`, `dartz`, `cached_network_image`, `dio`, `shared_preferences`, `uuid` | لم يظهر لها استيراد في شيفرة التطبيق. كذلك لا تستخدم النماذج الحالية تعليقات/أجزاء توليد Freezed أو JSON. | التحقق من الاستخدامات خارج `lib` وسير التوليد المقصود، ثم إزالة غير اللازم من `pubspec.yaml` ومراجعة اعتمادات التطوير المرتبطة. |
| `AppConstants.trainEndpoint` و`downloadModelEndpoint` و`TrainingServer.checkHealth()` | لا توجد استدعاءات؛ مسار التدريب الحالي يرفع الصور فقط. | تنفيذ الوظيفة المقصودة أو حذف الواجهات غير المستخدمة بعد الاتفاق على نطاق التدريب. |
| `هيكل المشروع-بصيره.docx` | مخطط أقدم لا يغطي طبقات الصوت والذاكرة والذكاء الاصطناعي الحالية. | تحديثه أو وسمه بوضوح كمرجع تاريخي. |
| مفتاح API وعناوين HTTP في `lib/core/constants.dart` و`android/app/src/main/AndroidManifest.xml` | يوجد مفتاح ثابت داخل تطبيق العميل، والاتصال يستخدم HTTP مع السماح بحركة cleartext؛ يمكن استخراج المفتاح من التطبيق واعتراض الاتصال. | أولوية أمنية: تدوير المفتاح إن كان حقيقيًا، استخدام HTTPS، ونقل الأسرار إلى خادم وسيط أو إعداد بناء غير سري (مع العلم أن `dart-define` لا يجعل السر آمنًا داخل تطبيق موزع). |
| إعدادات iOS | `Info.plist` المقروء لا يتضمن أوصاف استخدام الكاميرا والميكروفون، رغم اعتماد التطبيق عليهما. | إضافة أوصاف الخصوصية والتحقق على جهاز iOS قبل إعلان دعمه. |

**عناصر لا تُعد ميتة:** `DetectorService` و`FlutterTtsAdapter` بديلان يختارهما إعداد ثابت، و`ai_response_speaker.dart` مستخدم لصوت الردود النصية. كما أن `hand_tracker_service.dart` و`hand_gesture_controller.dart` لا يعملان بالإعداد الحالي، لكنهما مرتبطان بمسار ميزة مستقبلية وليس من المناسب حذفهما منفردين دون قرار.

## هـ) مراحل التطوير المستقبلية (Roadmap)

1. **أولوية حرجة: تأمين الاتصال والأسرار.** تدوير أي مفتاح مكشوف، إزالة السر من الشيفرة الموزعة، نقل الاتصالات إلى HTTPS، والتحقق من صلاحيات الخادم وسياسة السجلات.
2. **أولوية عالية: تثبيت المسار الأساسي على Android.** اختبار الكاميرا والكشف الأصلي وSTT/TTS على أجهزة فعلية، توثيق النماذج وأحجامها وتراخيصها، وإضافة اختبارات وحدات لتطبيع الأوامر والذاكرة وفك نتائج الكشف.
3. **أولوية عالية: معايرة السلامة والتوجيه.** معايرة تقدير العمق واتجاه الجيروسكوب وعتبات العوائق في بيئات مضبوطة، وإظهار/نطق حالات عدم اليقين بدل تقديم العمق النسبي على أنه قياس دقيق.
4. **أولوية متوسطة: إكمال سير التدريب.** توثيق عقد الخادم، إضافة حالة صحة الاتصال وإدارة أخطاء/إعادة محاولة الرفع، ثم ربط التدريب وتنزيل النموذج أو توضيح أن التدريب يتم خارج التطبيق.
5. **أولوية متوسطة: تحديد مصفوفة المنصات.** إما استكمال أذونات وتكامل الكاميرا والصوت والنماذج على iOS والمنصات الأخرى، أو تحديد Android كمنصة مدعومة حاليًا وإخفاء/توثيق ميزات المنصات غير المكتملة.
6. **أولوية لاحقة: تنظيف التبعيات والتوثيق والأصول.** إزالة ما يثبت عدم استخدامه فقط، مراجعة ملفات اليد ومصادر النماذج، ومزامنة الوثائق وملفات الترخيص مع الأصول الفعلية.

### التحقق المنفذ أثناء المراجعة

- فحص تشخيصات Dart: لم تظهر أخطاء.
- `test/widget_test.dart`: نجح الاختبار الموجود (1/1)، ويغطي تدفق واجهة التدريب فقط.
- فحص الأصول: جميع المسارات المعلنة في `pubspec.yaml` موجودة وقت الفحص. حُذف ملف النموذج الإضافي غير المعلن `yolox_nano_416_float32.tflite` بعد التأكد من عدم وجود مراجع له في `lib/` أو `pubspec.yaml`.