enum MediaSourceType { direct, macCmsApi, jsonApi, demo }

enum MediaCoverMode { portrait, landscape }

extension MediaCoverModeLayout on MediaCoverMode {
  double get posterAspectRatio =>
      this == MediaCoverMode.landscape ? 16 / 9 : 9 / 16;

  /// Includes the title/meta rows below a poster card.
  double get gridChildAspectRatio =>
      this == MediaCoverMode.landscape ? 1.18 : .47;
}

class MediaSource {
  const MediaSource({
    required this.id,
    required this.name,
    required this.type,
    required this.baseUrl,
    this.enabled = true,
    this.lastCheckedAt,
    this.lastError,
    this.externalId,
    this.detailUrl,
    this.isAdult = false,
    this.cacheTtlSeconds,
    this.isDefault = false,
    this.lastLatencyMs,
    this.isFavorite = false,
    this.coverMode = MediaCoverMode.portrait,
  });

  final String id;
  final String name;
  final MediaSourceType type;
  final String baseUrl;
  final bool enabled;
  final DateTime? lastCheckedAt;
  final String? lastError;
  final String? externalId;
  final String? detailUrl;
  final bool isAdult;
  final int? cacheTtlSeconds;
  final bool isDefault;
  final int? lastLatencyMs;
  final bool isFavorite;
  final MediaCoverMode coverMode;

  MediaSource copyWith({
    String? name,
    String? baseUrl,
    bool? enabled,
    DateTime? lastCheckedAt,
    String? lastError,
    String? externalId,
    String? detailUrl,
    bool? isAdult,
    int? cacheTtlSeconds,
    bool? isDefault,
    int? lastLatencyMs,
    bool? isFavorite,
    MediaCoverMode? coverMode,
    bool clearLastError = false,
  }) {
    return MediaSource(
      id: id,
      name: name ?? this.name,
      type: type,
      baseUrl: baseUrl ?? this.baseUrl,
      enabled: enabled ?? this.enabled,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      externalId: externalId ?? this.externalId,
      detailUrl: detailUrl ?? this.detailUrl,
      isAdult: isAdult ?? this.isAdult,
      cacheTtlSeconds: cacheTtlSeconds ?? this.cacheTtlSeconds,
      isDefault: isDefault ?? this.isDefault,
      lastLatencyMs: lastLatencyMs ?? this.lastLatencyMs,
      isFavorite: isFavorite ?? this.isFavorite,
      coverMode: coverMode ?? this.coverMode,
    );
  }
}
