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

const defaultMacCmsSourceConfigJson = r'''
{
  "cache_time": 7200,
  "api_site": {
    "dyttzy": {
      "api": "http://caiji.dyttzyapi.com/api.php/provide/vod",
      "name": "电影天堂资源",
      "detail": "http://caiji.dyttzyapi.com",
      "is_adult": false
    },
    "heimuer": {
      "api": "https://json.heimuer.xyz/api.php/provide/vod",
      "name": "黑木耳",
      "detail": "https://heimuer.tv",
      "is_adult": false
    },
    "ruyi": {
      "api": "https://cj.rycjapi.com/api.php/provide/vod",
      "name": "如意资源",
      "is_adult": false
    },
    "bfzy": {
      "api": "https://bfzyapi.com/api.php/provide/vod",
      "name": "暴风资源",
      "is_adult": false
    },
    "tyyszy": {
      "api": "https://tyyszy.com/api.php/provide/vod",
      "name": "天涯资源",
      "is_adult": false
    },
    "ffzy": {
      "api": "http://ffzy5.tv/api.php/provide/vod",
      "name": "非凡影视",
      "detail": "http://ffzy5.tv",
      "is_adult": false
    },
    "zy360": {
      "api": "https://360zy.com/api.php/provide/vod",
      "name": "360资源",
      "is_adult": false
    },
    "maotaizy": {
      "api": "https://caiji.maotaizy.cc/api.php/provide/vod",
      "name": "茅台资源",
      "is_adult": false
    },
    "wolong": {
      "api": "https://wolongzyw.com/api.php/provide/vod",
      "name": "卧龙资源",
      "is_adult": false
    },
    "jisu": {
      "api": "https://jszyapi.com/api.php/provide/vod",
      "name": "极速资源",
      "detail": "https://jszyapi.com",
      "is_adult": false
    },
    "dbzy": {
      "api": "https://dbzy.tv/api.php/provide/vod",
      "name": "豆瓣资源",
      "is_adult": false
    },
    "mozhua": {
      "api": "https://mozhuazy.com/api.php/provide/vod",
      "name": "魔爪资源",
      "is_adult": false
    },
    "mdzy": {
      "api": "https://www.mdzyapi.com/api.php/provide/vod",
      "name": "魔都资源",
      "is_adult": false
    },
    "zuid": {
      "api": "https://api.zuidapi.com/api.php/provide/vod",
      "name": "最大资源",
      "is_adult": false
    },
    "yinghua": {
      "api": "https://m3u8.apiyhzy.com/api.php/provide/vod",
      "name": "樱花资源",
      "is_adult": false
    },
    "wujin": {
      "api": "https://api.wujinapi.me/api.php/provide/vod",
      "name": "无尽资源",
      "is_adult": false
    },
    "wwzy": {
      "api": "https://wwzy.tv/api.php/provide/vod",
      "name": "旺旺短剧",
      "is_adult": false
    },
    "ikun": {
      "api": "https://ikunzyapi.com/api.php/provide/vod",
      "name": "iKun资源",
      "is_adult": false
    },
    "lzi": {
      "api": "https://cj.lziapi.com/api.php/provide/vod",
      "name": "量子资源站",
      "is_adult": false
    },
    "xiaomaomi": {
      "api": "https://zy.xmm.hk/api.php/provide/vod",
      "name": "小猫咪资源",
      "is_adult": false
    }
  }
}
''';

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
