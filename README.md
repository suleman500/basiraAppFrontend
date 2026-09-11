# Basira current voice fix

هذه الحزمة مبنية على الملفات التي أُرسلت مع آخر سجل Gradle، وليست على النسخة
القديمة من الحزمة السابقة.

## استبدال الملفات

| الملف داخل الحزمة | مسار Flutter |
|---|---|
| `detection_screen.dart` | `lib/features/detection/presentation/detection_screen.dart` |
| `speech_service.dart` | `lib/features/detection/services/speech_service.dart` |
| `AndroidManifest.xml` | `android/app/src/main/AndroidManifest.xml` |

## التعديلات

- معالجة حالة `notListening` و`done` التي يرسلها Android قبل رفع الإصبع.
- استخدام `cancel()` بدل استدعاء `stop()` على جلسة منتهية.
- إضافة فترة تعافٍ قبل تشغيل جلسة STT جديدة لتقليل `error_busy`.
- إعادة فتح جلسة التعرف تلقائيًا إذا أرسل Android `done` بينما الإصبع ما زال
  مضغوطًا، مع جمع النص بين الجلسات.
- إضافة استدعاء `RecognitionService` داخل `<queries>` في Manifest.
- عرض النص الجزئي أثناء الكلام والنص النهائي بعد رفع الإصبع.
- النص يظهر أسفل `DetectionChipsBar`، خارج مساحة الكاميرا والمربعات الكبيرة.
- إبقاء آخر عبارة منطوقة ظاهرة حتى تنفيذ الأمر التالي.

## طريقة الاختبار

1. استبدل الملفات الثلاثة في مشروع Flutter.
2. نفّذ:

```bash
flutter clean
flutter pub get
flutter run --release
```

3. اضغط مطولًا على زر المايك.
4. راقب ظهور `استمع...` ثم النص العربي أسفل مربعات الكشف.
5. قل: `أين الكرسي؟`.
6. ارفع الإصبع وانتظر تنفيذ الأمر.
7. كرر الأمر بعد انتهاء الإجابة الصوتية.

في السجل الجديد يجب أن تظهر رسائل مثل:

```text
🎤 المايك: pointer down
SpeechService status: listening
SpeechService: إعادة فتح جلسة أثناء الضغط: true
🎤 المايك: pointer up
```

خطأ `midas_small.tflite` منفصل عن الصوت؛ يعني أن ملف نموذج العمق غير موجود،
ولا يمنع عرض النص أو تنفيذ أوامر Object Memory.