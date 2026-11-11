import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Computes the Hub cross-device key for a source API URL.
String hubSourceKey(String rawUrl) {
  final raw = rawUrl.trim();
  final uri = Uri.tryParse(raw);
  if (uri == null ||
      !uri.hasScheme ||
      uri.host.isEmpty ||
      !{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
    throw const FormatException('Invalid source URL');
  }
  final scheme = uri.scheme.toLowerCase();
  final port = uri.hasPort &&
          !((scheme == 'http' && uri.port == 80) ||
              (scheme == 'https' && uri.port == 443))
      ? ':${uri.port}'
      : '';
  final host = uri.host.toLowerCase();
  final authorityHost = host.contains(':') ? '[$host]' : host;
  final authorityStart = raw.indexOf('://') + 3;
  final suffixStart = raw.indexOf(RegExp(r'[/#?]'), authorityStart);
  var suffix = suffixStart < 0 ? '' : raw.substring(suffixStart);
  final fragmentIndex = suffix.indexOf('#');
  if (fragmentIndex >= 0) suffix = suffix.substring(0, fragmentIndex);
  final queryIndex = suffix.indexOf('?');
  final rawPath = queryIndex < 0 ? suffix : suffix.substring(0, queryIndex);
  final rawQuery = queryIndex < 0 ? '' : suffix.substring(queryIndex + 1);
  final path = _normalizeDotSegments(rawPath).replaceFirst(RegExp(r'/+$'), '');
  final queryItems =
      rawQuery.split('&').where((item) => item.isNotEmpty).toList()..sort();
  final query = queryItems.isEmpty ? '' : '?${queryItems.join('&')}';
  final canonical = '$scheme://$authorityHost$port$path$query';
  return sha256.convert(utf8.encode(canonical)).toString();
}

String _normalizeDotSegments(String path) {
  if (path.isEmpty) return '';
  final output = <String>[];
  for (final segment in path.split('/')) {
    if (segment == '.') continue;
    if (segment == '..') {
      if (output.isNotEmpty) output.removeLast();
      continue;
    }
    output.add(segment);
  }
  var normalized = output.join('/');
  if (path.startsWith('/') && !normalized.startsWith('/')) {
    normalized = '/$normalized';
  }
  if (path.endsWith('/.') || path.endsWith('/..')) normalized += '/';
  return normalized;
}

String syncEncode(String value) {
  final bytes = utf8.encode(value);
  final output = StringBuffer();
  for (final byte in bytes) {
    final allowed = (byte >= 0x41 && byte <= 0x5a) ||
        (byte >= 0x61 && byte <= 0x7a) ||
        (byte >= 0x30 && byte <= 0x39) ||
        const [0x2d, 0x2e, 0x5f, 0x2a].contains(byte);
    if (allowed) {
      output.writeCharCode(byte);
    } else {
      output.write('%${byte.toRadixString(16).padLeft(2, '0').toUpperCase()}');
    }
  }
  return output.toString();
}

String hubMediaKey({
  required String sourceKey,
  required String vodId,
  String? lineName,
  int? episodeIndex,
}) {
  final parts = <String>[sourceKey, vodId];
  if (lineName != null && episodeIndex != null) {
    parts
      ..add(lineName)
      ..add('$episodeIndex');
  }
  return parts.map(syncEncode).join(':');
}
