import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cineo_flutter/core/models/download_models.dart';
import 'package:cineo_flutter/core/theme/cineo_theme.dart';
import 'package:cineo_flutter/data/download/download_service.dart';
import 'package:cineo_flutter/features/download/download_screen.dart';

class _FakeDownloadService extends DownloadService {
  _FakeDownloadService(List<DownloadTask> initialTasks)
      : _tasks = List<DownloadTask>.of(initialTasks),
        super();

  List<DownloadTask> _tasks;
  final _changes = StreamController<List<DownloadTask>>.broadcast();

  @override
  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  @override
  Stream<List<DownloadTask>> get changes => _changes.stream;

  @override
  Future<DownloadCacheStats> cacheStats() async => const DownloadCacheStats(
        totalBytes: 400,
        fileCount: 1,
        taskCount: 2,
      );

  @override
  Future<void> delete(String id) async {
    _tasks = _tasks.where((task) => task.id != id).toList();
    _changes.add(List.unmodifiable(_tasks));
  }

  @override
  Future<void> dispose() async {
    await _changes.close();
  }
}

void main() {
  testWidgets('groups task states and supports deleting a task',
      (tester) async {
    final now = DateTime(2026, 1, 1);
    final service = _FakeDownloadService([
      DownloadTask(
        taskId: 'task-1',
        taskKey: 'series-1|episode-1|https://example.test/episode-1.m3u8',
        mediaId: 'series-1',
        sourceUrl: 'https://example.test/episode-1.m3u8',
        title: '测试剧集',
        episodeId: 'episode-1',
        episodeNumber: 1,
        status: DownloadTaskStatus.completed,
        totalSegments: 4,
        completedSegments: 4,
        totalBytes: 400,
        downloadedBytes: 400,
        outputPath: '/cache/series-1/episode-1/index.m3u8',
        createdAt: now,
        updatedAt: now,
      ),
      DownloadTask(
        taskId: 'task-2',
        taskKey: 'series-1|episode-2|https://example.test/episode-2.m3u8',
        mediaId: 'series-1',
        sourceUrl: 'https://example.test/episode-2.m3u8',
        title: '测试剧集',
        episodeId: 'episode-2',
        episodeNumber: 2,
        status: DownloadTaskStatus.paused,
        totalSegments: 4,
        completedSegments: 1,
        totalBytes: 400,
        downloadedBytes: 100,
        createdAt: now,
        updatedAt: now,
      ),
    ]);
    addTearDown(service.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCineoTheme(),
        home: DownloadManagerScreen(service: service),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('缓存下载'), findsOneWidget);
    expect(find.text('测试剧集'), findsOneWidget);
    expect(find.text('1/2 集已缓存'), findsOneWidget);
    expect(find.text('2 集任务'), findsOneWidget);
    expect(find.textContaining('个文件'), findsNothing);

    await tester.tap(find.text('测试剧集'));
    await tester.pumpAndSettle();

    expect(find.text('1/2 集已缓存'), findsOneWidget);
    expect(find.text('已完成'), findsOneWidget);
    expect(find.text('总文件大小 400 B'), findsOneWidget);
    expect(find.text('播放进度 0%'), findsOneWidget);
    expect(find.text('已下载 400 B / 400 B'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('第 2 集'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.pumpAndSettle();

    expect(find.text('已暂停 · 25%'), findsOneWidget);
    expect(find.text('已下载 100 B / 400 B'), findsOneWidget);
    expect(find.byTooltip('继续'), findsOneWidget);
    expect(find.byTooltip('删除'), findsNWidgets(2));

    await tester.tap(find.byTooltip('删除').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(service.tasks, hasLength(1));
    expect(find.text('0/1 集已缓存'), findsOneWidget);
    expect(find.byTooltip('删除'), findsOneWidget);
  });

  testWidgets('completed episode card opens local playback callback',
      (tester) async {
    final now = DateTime(2026, 1, 1);
    final service = _FakeDownloadService([
      DownloadTask(
        taskId: 'task-completed',
        taskKey: 'movie-1|movie|https://example.test/movie.m3u8',
        mediaId: 'movie-1',
        sourceUrl: 'https://example.test/movie.m3u8',
        title: '已缓存视频',
        status: DownloadTaskStatus.completed,
        totalBytes: 400,
        downloadedBytes: 400,
        outputPath: '/cache/movie-1/index.m3u8',
        createdAt: now,
        updatedAt: now,
      ),
    ]);
    DownloadTask? played;
    addTearDown(service.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildCineoTheme(),
        home: DownloadManagerScreen(
          service: service,
          onPlayTask: (task) async => played = task,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('已缓存视频'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('电影'));
    await tester.pump();

    expect(played?.id, 'task-completed');
  });
}
