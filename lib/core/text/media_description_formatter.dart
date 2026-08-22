/// Converts provider-supplied HTML descriptions into safe, readable plain text.
///
/// This is intentionally a small formatter rather than an HTML renderer. The
/// description is never executed or inserted into a WebView.
String formatMediaDescription(String value) {
  if (value.trim().isEmpty) return '';

  var text = value
      // Comments and content from non-visible HTML elements are not part of a
      // media description and must be removed before stripping the remaining tags.
      .replaceAll(RegExp(r'<!--([\s\S]*?)-->'), '')
      .replaceAll(
          RegExp(r'<\s*(script|style)(?:\s[^>]*)?>[\s\S]*?<\s*/\s*\1\s*>',
              caseSensitive: false),
          '')
      // Treat common block elements as paragraph boundaries. A final cleanup
      // below makes repeated and leading/trailing breaks predictable.
      .replaceAll(
          RegExp(
              r'<\s*/?\s*(?:p|div|section|article|header|footer|li|h[1-6]|tr)\b[^>]*>',
              caseSensitive: false),
          '\n')
      .replaceAll(RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]*>', multiLine: true), ' ');

  text = _decodeEntities(text);
  final lines = text
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'[\t ]+'), ' ').trim())
      .toList();

  final output = <String>[];
  var blankLinePending = false;
  for (final line in lines) {
    if (line.isEmpty) {
      if (output.isNotEmpty) blankLinePending = true;
      continue;
    }
    if (blankLinePending) output.add('');
    output.add(line);
    blankLinePending = false;
  }
  return output.join('\n').trim();
}

String _decodeEntities(String value) {
  const named = <String, String>{
    'amp': '&',
    'apos': "'",
    'gt': '>',
    'lt': '<',
    'nbsp': ' ',
    'quot': '"',
    'ndash': '–',
    'mdash': '—',
    'hellip': '…',
    'middot': '·',
    'copy': '©',
    'reg': '®',
    'trade': '™',
  };
  final entityPattern =
      RegExp(r'&(#x[0-9a-f]+|#\d+|[a-z][a-z0-9]+);?', caseSensitive: false);
  return value.replaceAllMapped(entityPattern, (match) {
    final raw = match.group(1)!;
    if (raw.startsWith('#x') || raw.startsWith('#X')) {
      return _codePoint(raw.substring(2), 16) ?? match.group(0)!;
    }
    if (raw.startsWith('#')) {
      return _codePoint(raw.substring(1), 10) ?? match.group(0)!;
    }
    return named[raw.toLowerCase()] ?? match.group(0)!;
  });
}

String? _codePoint(String value, int radix) {
  final codePoint = int.tryParse(value, radix: radix);
  if (codePoint == null || codePoint < 0 || codePoint > 0x10ffff) return null;
  if (codePoint >= 0xd800 && codePoint <= 0xdfff) return null;
  return String.fromCharCode(codePoint);
}
