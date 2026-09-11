import 'package:arabic_search/arabic_search.dart';

/// أدوات معالجة النصوص العربية — مبنية على حزمة `arabic_search`.
///
/// تُستخدم في:
/// - SpeechService (تنظيف نص الكلام المُتعرَّف عليه قبل تمريره)
/// - VoiceCommandParser (مقارنة النص مع قوالب الأوامر الثابتة)
/// - أي مكان يقارن نصًا عربيًا بنص عربي آخر.
///
/// الحزمة تعالج تلقائيًا:
/// - إزالة التشكيل (الفتحة، الضمة، الكسرة، السكون، الشدة، التنوين...)
/// - توحيد الألف:  أ / إ / آ / ٱ → ا
/// - توحيد الياء:  ى → ي
/// - توحيد التاء المربوطة: ة → ه
/// - توحيد الهمزة: ؤ → و ، ئ → ي
/// - إزالة التطويل (الكشيدة ـ)
/// - تحويل الأرقام العربية إلى إنجليزية

/// تطبيع شامل لنص عربي — يُستخدم قبل أي مقارنة.
///
/// مثال:
///   normalizeArabic("الكَرًسٍيُ")  →  "الكرسي"
///   normalizeArabic("إِسْلَام ١٢٣")  →  "اسلام 123"
String normalizeArabic(String input) {
  if (input.isEmpty) return input;
  return ArabicText.searchKey(input);
}

/// إزالة التشكيل فقط (بدون توحيد أشكال الأحرف).
///
/// مفيدة إذا كنت تريد الحفاظ على شكل الألف/الياء/التاء الأصلي.
/// للحصول على تطبيع كامل استخدم [normalizeArabic].
String removeTashkeel(String input) {
  if (input.isEmpty) return input;
  // searchKey يقوم بتطبيع كامل، لذلك لإزالة التشكيل فقط
  // نستخدم تعبيرًا نمطيًا يدويًا هنا.
  final tashkeelPattern = RegExp(
    r'[\u064B-\u065F\u0670\u06D6-\u06DC\u06DF-\u06E8\u06EA-\u06ED\u0640]',
  );
  var result = input.replaceAll(tashkeelPattern, '');
  result = result.replaceAll(RegExp(r'\s+'), ' ').trim();
  return result;
}

/// هل النص [text] يحتوي على [query] بعد تطبيع الطرفين؟
bool containsArabic(String text, String query) {
  return ArabicText.containsNormalized(text, query);
}

/// هل كل كلمات [query] موجودة في [text] (بعد التطبيع)؟
bool containsAllArabicTokens(String text, String query) {
  return ArabicText.containsAllTokens(text, query);
}

/// هل أي كلمة من [query] موجودة في [text] (بعد التطبيع)؟
bool containsAnyArabicToken(String text, String query) {
  return ArabicText.containsAnyToken(text, query);
}

/// مقارنة تطابق تام بعد التطبيع — الأنسب لمطابقة أوامر صوتية ثابتة.
///
/// مثال:
///   arabicEquals("الكَرًسٍيُ", "الكرسي")  →  true
///   arabicEquals("إسلام", "اسلام")        →  true
bool arabicEquals(String a, String b) {
  return normalizeArabic(a) == normalizeArabic(b);
}

/// تحويل الأرقام العربية (٠١٢...) إلى إنجليزية (012...).
String toEnglishDigits(String input) => ArabicText.toEnglishDigits(input);

/// تحويل الأرقام الإنجليزية (012...) إلى عربية (٠١٢...).
String toArabicDigits(String input) => ArabicText.toArabicDigits(input);

