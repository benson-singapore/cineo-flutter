import 'dart:convert';

import '../../core/models/media_source.dart';

class SourceConfigImportIssue {
  const SourceConfigImportIssue({
    required this.message,
    this.sourceKey,
  });

  final String message;
  final String? sourceKey;

  @override
  String toString() {
    final prefix = sourceKey == null ? '' : '[$sourceKey] ';
    return '$prefix$message';
  }
}

class SourceConfigImportResult {
  const SourceConfigImportResult({
    required this.sources,
    required this.issues,
  });

  final List<MediaSource> sources;
  final List<SourceConfigImportIssue> issues;
}

/// Parses the api_site format used by MacCMS-compatible source lists.
///
/// This function only validates and converts local JSON. It deliberately does
/// not contact any configured endpoint.
SourceConfigImportResult parseMacCmsSourceConfig(
  String rawJson, {
  bool includeAdult = true,
  bool allowInsecureHttp = false,
}) {
  final issues = <SourceConfigImportIssue>[];
  final sources = <MediaSource>[];

  dynamic decoded;
  try {
    decoded = jsonDecode(rawJson);
  } on FormatException catch (error) {
    issues.add(SourceConfigImportIssue(message: 'JSON 格式无效：${error.message}'));
    return SourceConfigImportResult(sources: sources, issues: issues);
  }

  if (decoded is! Map) {
    issues.add(const SourceConfigImportIssue(message: '配置根节点必须是对象。'));
    return SourceConfigImportResult(sources: sources, issues: issues);
  }

  final apiSite = decoded['api_site'];
  if (apiSite is! Map) {
    issues.add(const SourceConfigImportIssue(
      message: '配置必须包含对象类型的 api_site 字段。',
    ));
    return SourceConfigImportResult(sources: sources, issues: issues);
  }

  final cacheTtlSeconds = _readCacheTime(decoded, issues);
  for (final entry in apiSite.entries) {
    final sourceKey = entry.key is String ? entry.key as String : null;
    if (sourceKey == null || sourceKey.trim().isEmpty) {
      issues.add(const SourceConfigImportIssue(message: '资源站键名必须是非空字符串。'));
      continue;
    }

    final value = entry.value;
    if (value is! Map) {
      issues.add(SourceConfigImportIssue(
        sourceKey: sourceKey,
        message: '资源站配置必须是对象。',
      ));
      continue;
    }

    final api = _requiredNonEmptyString(value['api']);
    if (api == null) {
      issues.add(SourceConfigImportIssue(
        sourceKey: sourceKey,
        message: 'api 必须是非空字符串。',
      ));
      continue;
    }

    final name = _requiredNonEmptyString(value['name']);
    if (name == null) {
      issues.add(SourceConfigImportIssue(
        sourceKey: sourceKey,
        message: 'name 必须是非空字符串。',
      ));
      continue;
    }

    final apiUri = Uri.tryParse(api);
    if (!_isHttpUri(apiUri)) {
      issues.add(SourceConfigImportIssue(
        sourceKey: sourceKey,
        message: 'api 必须是包含主机名的 http 或 https URL。',
      ));
      continue;
    }
    if (!allowInsecureHttp && apiUri!.scheme.toLowerCase() == 'http') {
      issues.add(SourceConfigImportIssue(
        sourceKey: sourceKey,
        message: '默认跳过非 HTTPS 资源站；确认授权后可选择允许 HTTP。',
      ));
      continue;
    }

    final isAdult = _readAdultFlag(value['is_adult'], sourceKey, issues);
    if (isAdult == null) continue;
    if (isAdult && !includeAdult) {
      issues.add(SourceConfigImportIssue(
        sourceKey: sourceKey,
        message: '已跳过成人资源站。',
      ));
      continue;
    }

    final detail = value['detail'];
    String? detailUrl;
    if (detail != null) {
      detailUrl = _requiredNonEmptyString(detail);
      if (detailUrl == null) {
        issues.add(SourceConfigImportIssue(
          sourceKey: sourceKey,
          message: 'detail 必须是非空字符串（如果提供）。',
        ));
        continue;
      }
      final detailUri = Uri.tryParse(detailUrl);
      if (!_isHttpUri(detailUri) ||
          (!allowInsecureHttp && detailUri!.scheme.toLowerCase() == 'http')) {
        issues.add(SourceConfigImportIssue(
          sourceKey: sourceKey,
          message: 'detail 必须是允许的 http 或 https URL。',
        ));
        continue;
      }
    }

    sources.add(
      MediaSource(
        id: sourceKey,
        externalId: sourceKey,
        name: name,
        type: MediaSourceType.macCmsApi,
        baseUrl: api,
        detailUrl: detailUrl,
        isAdult: isAdult,
        cacheTtlSeconds: cacheTtlSeconds,
      ),
    );
  }

  return SourceConfigImportResult(sources: sources, issues: issues);
}

int? _readCacheTime(
  Map<dynamic, dynamic> config,
  List<SourceConfigImportIssue> issues,
) {
  final value = config['cache_time'];
  if (value == null) return null;
  if (value is int && value > 0) return value;
  issues.add(const SourceConfigImportIssue(
    message: 'cache_time 必须是正整数；已忽略该缓存时间。',
  ));
  return null;
}

String? _requiredNonEmptyString(dynamic value) {
  if (value is! String) return null;
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

bool? _readAdultFlag(
  dynamic value,
  String sourceKey,
  List<SourceConfigImportIssue> issues,
) {
  if (value == null) return false;
  if (value is bool) return value;
  issues.add(SourceConfigImportIssue(
    sourceKey: sourceKey,
    message: 'is_adult 必须是布尔值。',
  ));
  return null;
}

bool _isHttpUri(Uri? uri) {
  if (uri == null || uri.host.isEmpty) return false;
  final scheme = uri.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https';
}
