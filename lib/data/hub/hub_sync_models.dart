import '../../core/models/media_source.dart';
import 'hub_sync_keys.dart';

class SyncEnvelope {
  const SyncEnvelope({
    required this.entity,
    required this.key,
    required this.updatedAt,
    required this.deleted,
    required this.payload,
    this.deviceId = '',
  });

  final String entity;
  final String key;
  final int updatedAt;
  final bool deleted;
  final Map<String, Object?>? payload;
  final String deviceId;

  SyncEnvelope copyWith({
    int? updatedAt,
    bool? deleted,
    Map<String, Object?>? payload,
    String? deviceId,
  }) =>
      SyncEnvelope(
        entity: entity,
        key: key,
        updatedAt: updatedAt ?? this.updatedAt,
        deleted: deleted ?? this.deleted,
        payload: payload,
        deviceId: deviceId ?? this.deviceId,
      );

  Map<String, Object?> toJson() => {
        'entity': entity,
        'key': key,
        'updated_at': updatedAt,
        'deleted': deleted,
        'payload': payload,
      };

  factory SyncEnvelope.fromJson(Map<String, Object?> json) => SyncEnvelope(
        entity: json['entity']! as String,
        key: json['key']! as String,
        updatedAt: (json['updated_at']! as num).toInt(),
        deleted: json['deleted']! as bool,
        payload: (json['payload'] as Map?)?.cast<String, Object?>(),
        deviceId: json['device_id'] as String? ?? '',
      );
}

class HubSitePayload {
  const HubSitePayload({
    required this.key,
    required this.rawPayload,
    required this.siteType,
    required this.isKnownType,
  });

  final String key;
  final Map<String, Object?> rawPayload;
  final String siteType;
  final bool isKnownType;
}

SyncEnvelope? siteEnvelope(MediaSource source, {required int updatedAt}) {
  if (source.type == MediaSourceType.demo) return null;
  final type = switch (source.type) {
    MediaSourceType.macCmsApi => 'maccms',
    MediaSourceType.jsonApi => 'json',
    MediaSourceType.direct => 'direct',
    MediaSourceType.demo => throw StateError('Filtered above'),
  };
  return SyncEnvelope(
    entity: 'site',
    key: hubSourceKey(source.baseUrl),
    updatedAt: updatedAt,
    deleted: false,
    payload: {
      'name': source.name,
      'api': source.baseUrl,
      'detail_url': source.detailUrl,
      'enabled': source.enabled,
      'is_adult': source.isAdult,
      'is_default': source.isDefault,
      'site_type': type,
      'cover_mode': source.coverMode == MediaCoverMode.landscape
          ? 'landscape'
          : 'portrait',
      'cache_ttl_seconds': source.cacheTtlSeconds,
    },
  );
}

HubSitePayload decodeSitePayload(String key, Map<String, Object?> payload) {
  final type = payload['site_type'] as String? ?? 'maccms';
  return HubSitePayload(
    key: key,
    rawPayload: Map.unmodifiable(payload),
    siteType: type,
    isKnownType: const {'maccms', 'json', 'direct'}.contains(type),
  );
}
