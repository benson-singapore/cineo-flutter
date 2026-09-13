import 'dart:math' as math;

enum DownloadTaskStatus {
  queued,
  downloading,
  paused,
  completed,
  failed,
  cancelled,
}

extension DownloadTaskStatusCodec on DownloadTaskStatus {
  String get wireName => name;

  static DownloadTaskStatus fromWireName(String? value) {
    return DownloadTaskStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => DownloadTaskStatus.queued,
    );
  }
}

class DownloadSettings {
  const DownloadSettings({
    int concurrency = defaultConcurrency,
    this.allowBackground = false,
  }) : concurrency = concurrency < minConcurrency
            ? minConcurrency
            : concurrency > maxConcurrency
                ? maxConcurrency
                : concurrency;

  static const int defaultConcurrency = 5;
  static const int minConcurrency = 1;
  static const int maxConcurrency = 10;

  final int concurrency;
  final bool allowBackground;

  /// Alias used by presentation code that describes the setting as a toggle.
  bool get backgroundDownloads => allowBackground;

  int get maxConcurrentDownloads => concurrency;

  DownloadSettings normalized() => DownloadSettings(
        concurrency: concurrency,
        allowBackground: allowBackground,
      );

  DownloadSettings copyWith({int? concurrency, bool? allowBackground}) {
    return DownloadSettings(
      concurrency: concurrency ?? this.concurrency,
      allowBackground: allowBackground ?? this.allowBackground,
    );
  }

  Map<String, dynamic> toJson() => {
        'concurrency': concurrency,
        'allow_background': allowBackground,
      };

  factory DownloadSettings.fromJson(Map<String, dynamic> json) {
    final rawConcurrency = json['concurrency'];
    return DownloadSettings(
      concurrency:
          rawConcurrency is num ? rawConcurrency.toInt() : defaultConcurrency,
      allowBackground: json['allow_background'] == true,
    );
  }
}

class DownloadRequest {
  DownloadRequest({
    required this.mediaId,
    required this.sourceUrl,
    this.taskId,
    this.title,
    this.episodeId,
    this.seasonNumber,
    this.episodeNumber,
    this.episodeLabel,
    this.posterUrl,
    this.backdropUrl,
  }) {
    final uri = Uri.tryParse(sourceUrl);
    if (mediaId.trim().isEmpty) throw ArgumentError.value(mediaId, 'mediaId');
    if (uri == null || !{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
      throw ArgumentError.value(sourceUrl, 'sourceUrl', 'must be an HTTP URL');
    }
  }

  final String mediaId;
  final String sourceUrl;
  final String? taskId;
  final String? title;
  final String? episodeId;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? episodeLabel;
  final String? posterUrl;
  final String? backdropUrl;

  String get stableKey =>
      '${mediaId.trim()}|${episodeId ?? episodeNumber ?? 'movie'}|$sourceUrl';

  String get identity => stableKey;
}

class DownloadTask {
  const DownloadTask({
    required this.taskId,
    required this.taskKey,
    required this.mediaId,
    required this.sourceUrl,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.title,
    this.episodeId,
    this.seasonNumber,
    this.episodeNumber,
    this.episodeLabel,
    this.posterUrl,
    this.backdropUrl,
    this.totalSegments = 0,
    this.completedSegments = 0,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.outputPath,
    this.errorMessage,
  });

  final String taskId;
  final String taskKey;
  final String mediaId;
  final String sourceUrl;
  final String? title;
  final String? episodeId;
  final int? seasonNumber;
  final int? episodeNumber;
  final String? episodeLabel;
  final String? posterUrl;
  final String? backdropUrl;
  final DownloadTaskStatus status;
  final int totalSegments;
  final int completedSegments;
  final int totalBytes;
  final int downloadedBytes;
  final String? outputPath;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime updatedAt;

  String get id => taskId;

  bool get isFinished =>
      status == DownloadTaskStatus.completed ||
      status == DownloadTaskStatus.cancelled;

  double get progress {
    if (totalBytes > 0) return (downloadedBytes / totalBytes).clamp(0, 1);
    if (totalSegments > 0) {
      return (completedSegments / totalSegments).clamp(0, 1);
    }
    return status == DownloadTaskStatus.completed ? 1 : 0;
  }

  DownloadTask copyWith({
    DownloadTaskStatus? status,
    int? totalSegments,
    int? completedSegments,
    int? totalBytes,
    int? downloadedBytes,
    String? outputPath,
    String? errorMessage,
    bool clearOutputPath = false,
    bool clearErrorMessage = false,
    bool clearError = false,
    DateTime? updatedAt,
  }) {
    return DownloadTask(
      taskId: taskId,
      taskKey: taskKey,
      mediaId: mediaId,
      sourceUrl: sourceUrl,
      title: title,
      episodeId: episodeId,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      episodeLabel: episodeLabel,
      posterUrl: posterUrl,
      backdropUrl: backdropUrl,
      status: status ?? this.status,
      totalSegments: totalSegments ?? this.totalSegments,
      completedSegments: completedSegments ?? this.completedSegments,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      outputPath: clearOutputPath ? null : outputPath ?? this.outputPath,
      errorMessage: clearErrorMessage || clearError
          ? null
          : errorMessage ?? this.errorMessage,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
        'task_id': taskId,
        'task_key': taskKey,
        'media_id': mediaId,
        'source_url': sourceUrl,
        'title': title,
        'episode_id': episodeId,
        'season_number': seasonNumber,
        'episode_number': episodeNumber,
        'episode_label': episodeLabel,
        'poster_url': posterUrl,
        'backdrop_url': backdropUrl,
        'status': status.wireName,
        'total_segments': totalSegments,
        'completed_segments': completedSegments,
        'total_bytes': totalBytes,
        'downloaded_bytes': downloadedBytes,
        'output_path': outputPath,
        'error_message': errorMessage,
        'created_at': createdAt.toUtc().toIso8601String(),
        'updated_at': updatedAt.toUtc().toIso8601String(),
      };

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    DateTime readDate(String key) =>
        DateTime.tryParse('${json[key]}')?.toUtc() ?? DateTime.now().toUtc();
    int readInt(String key) =>
        json[key] is num ? (json[key] as num).toInt() : 0;
    return DownloadTask(
      taskId: '${json['task_id'] ?? ''}',
      taskKey: '${json['task_key'] ?? json['task_id'] ?? ''}',
      mediaId: '${json['media_id'] ?? ''}',
      sourceUrl: '${json['source_url'] ?? ''}',
      title: json['title'] as String?,
      episodeId: json['episode_id'] as String?,
      seasonNumber: json['season_number'] is num
          ? (json['season_number'] as num).toInt()
          : null,
      episodeNumber: json['episode_number'] is num
          ? (json['episode_number'] as num).toInt()
          : null,
      episodeLabel: json['episode_label'] as String?,
      posterUrl: json['poster_url'] as String?,
      backdropUrl: json['backdrop_url'] as String?,
      status: DownloadTaskStatusCodec.fromWireName(json['status'] as String?),
      totalSegments: readInt('total_segments'),
      completedSegments: readInt('completed_segments'),
      totalBytes: readInt('total_bytes'),
      downloadedBytes: readInt('downloaded_bytes'),
      outputPath: json['output_path'] as String?,
      errorMessage: json['error_message'] as String?,
      createdAt: readDate('created_at'),
      updatedAt: readDate('updated_at'),
    );
  }
}

class DownloadCacheStats {
  const DownloadCacheStats({
    required this.totalBytes,
    required this.fileCount,
    required this.taskCount,
  });

  final int totalBytes;
  final int fileCount;
  final int taskCount;

  double get totalMegabytes => totalBytes / math.pow(1024, 2);
}
