import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const m3u8FilterUrlPlaceholder = r'${YOUR_M3U8_URL}';

class M3u8FilterConfig {
  const M3u8FilterConfig({
    required this.id,
    required this.name,
    required this.template,
    this.enabled = false,
  });

  final String id;
  final String name;
  final String template;
  final bool enabled;

  M3u8FilterConfig copyWith({
    String? name,
    String? template,
    bool? enabled,
  }) {
    return M3u8FilterConfig(
      id: id,
      name: name ?? this.name,
      template: template ?? this.template,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, Object> toJson() => <String, Object>{
        'id': id,
        'name': name,
        'template': template,
        'enabled': enabled,
      };

  static M3u8FilterConfig? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final name = value['name'];
    final template = value['template'];
    if (id is! String ||
        name is! String ||
        template is! String ||
        id.trim().isEmpty ||
        name.trim().isEmpty ||
        !isValidM3u8FilterTemplate(template)) {
      return null;
    }
    return M3u8FilterConfig(
      id: id,
      name: name,
      template: template,
      enabled: value['enabled'] == true,
    );
  }
}

bool isValidM3u8FilterTemplate(String template) {
  final value = template.trim();
  if (!value.contains(m3u8FilterUrlPlaceholder)) return false;
  final uri = Uri.tryParse(
    value.replaceAll(
        m3u8FilterUrlPlaceholder, 'https://example.com/video.m3u8'),
  );
  return uri != null &&
      (uri.scheme == 'http' || uri.scheme == 'https') &&
      uri.host.isNotEmpty;
}

String buildM3u8FilterUrl(String template, String m3u8Url) {
  if (!isValidM3u8FilterTemplate(template)) return m3u8Url;
  // The filter API expects the source URL as a raw query value. Encoding the
  // whole URL makes this service return 502 instead of an HLS playlist.
  return template.trim().replaceAll(m3u8FilterUrlPlaceholder, m3u8Url);
}

class M3u8FilterSettings extends ChangeNotifier {
  static const storageKey = 'm3u8_filter_configs';

  bool _initialized = false;
  List<M3u8FilterConfig> _configs = const <M3u8FilterConfig>[];

  bool get initialized => _initialized;
  List<M3u8FilterConfig> get configs => List.unmodifiable(_configs);
  M3u8FilterConfig? get activeConfig => _firstEnabled(_configs);

  Future<void> initialize() async {
    if (_initialized) return;
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(storageKey);
    if (encoded != null) {
      try {
        final decoded = jsonDecode(encoded);
        if (decoded is List) {
          _configs = _normalize(
            decoded
                .map(M3u8FilterConfig.fromJson)
                .whereType<M3u8FilterConfig>(),
          );
        }
      } on FormatException {
        _configs = const <M3u8FilterConfig>[];
      }
    }
    _initialized = true;
    notifyListeners();
  }

  Future<M3u8FilterConfig> addConfig({
    required String name,
    required String template,
    bool enabled = false,
  }) async {
    _validate(name, template);
    final config = M3u8FilterConfig(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name.trim(),
      template: template.trim(),
      enabled: enabled,
    );
    final existing = enabled
        ? _configs.map((item) => item.copyWith(enabled: false))
        : _configs;
    _configs = _normalize(<M3u8FilterConfig>[...existing, config]);
    await _persistAndNotify();
    return _configs.firstWhere((item) => item.id == config.id);
  }

  Future<void> updateConfig({
    required String id,
    required String name,
    required String template,
  }) async {
    _validate(name, template);
    final index = _configs.indexWhere((config) => config.id == id);
    if (index < 0) return;
    final current = _configs[index];
    final updated = current.copyWith(
      name: name.trim(),
      template: template.trim(),
    );
    _configs = <M3u8FilterConfig>[..._configs]..[index] = updated;
    await _persistAndNotify();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    if (!_configs.any((config) => config.id == id)) return;
    _configs = _configs
        .map(
          (config) => config.copyWith(
            enabled: enabled && config.id == id,
          ),
        )
        .toList(growable: false);
    await _persistAndNotify();
  }

  Future<void> deleteConfig(String id) async {
    _configs =
        _configs.where((config) => config.id != id).toList(growable: false);
    await _persistAndNotify();
  }

  Future<void> _persistAndNotify() async {
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      storageKey,
      jsonEncode(_configs.map((config) => config.toJson()).toList()),
    );
  }

  static List<M3u8FilterConfig> _normalize(
    Iterable<M3u8FilterConfig> configs,
  ) {
    var foundEnabled = false;
    return configs.map((config) {
      if (!config.enabled || foundEnabled) {
        return config.copyWith(enabled: false);
      }
      foundEnabled = true;
      return config;
    }).toList(growable: false);
  }

  static M3u8FilterConfig? _firstEnabled(
    Iterable<M3u8FilterConfig> configs,
  ) {
    for (final config in configs) {
      if (config.enabled) return config;
    }
    return null;
  }

  static void _validate(String name, String template) {
    if (name.trim().isEmpty) {
      throw ArgumentError('请输入配置名称');
    }
    if (!isValidM3u8FilterTemplate(template)) {
      throw ArgumentError('请输入包含 $m3u8FilterUrlPlaceholder 的有效代理地址');
    }
  }
}
