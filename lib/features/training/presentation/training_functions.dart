String sanitizeLabel(String input) {
  var cleaned = input.trim();
  cleaned = cleaned.replaceAll(RegExp(r'\s+'), ' ');
  cleaned = cleaned.replaceAll(RegExp(r'[^a-zA-Z\u0600-\u06FF\s]'), '');
  return cleaned;
}
