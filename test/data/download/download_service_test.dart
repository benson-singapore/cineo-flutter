import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cineo_flutter/core/models/download_models.dart';
import 'package:cineo_flutter/data/download/download_directory.dart';
import 'package:cineo_flutter/data/download/download_service.dart';
import 'package:cineo_flutter/data/download/download_settings_store.dart';
import 'package:cineo_flutter/data/download/hls_playlist.dart';
import 'package:cineo_flutter/data/download/download_storage.dart';

const _playlist = '''#EXTM3U
#EXT-X-TARGETDURATION:10
#EXTINF:10,
one.ts
#EXTINF:10,
two.ts
#EXT-X-ENDLIST
''';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('cineo-download-test-');
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('normalizes settings and suppresses duplicate tasks', () async {
    const settings = DownloadSettings(concurrency: 99);
    expect(settings.concurrency, DownloadSettings.maxConcurrency);
    expect(const DownloadSettings().concurrency, 5);
    expect(const DownloadSettings().allowBackground, isFalse);

    final service = createService(root, segmentFetcher: (_) async => <int>[1]);
    final request = requestFor('same');
    final first = await service.enqueue(request);
    final duplicate = await service.enqueue(request);

    expect(duplicate.id, first.id);
    expect(service.tasks, hasLength(1));
    await waitFor(() async =>
        (await service.task(first.id))?.status == DownloadTaskStatus.completed);
    await service.dispose();
  });

  test('keeps queued work under the configured concurrency', () async {
    final fetchStarted = <Uri>[];
    final firstRelease = Completer<List<int>>();
    var call = 0;
    final service = createService(
      root,
      settings: const DownloadSettings(concurrency: 1),
      segmentFetcher: (uri) {
        fetchStarted.add(uri);
        call++;
        return call == 1
            ? firstRelease.future
            : Future<List<int>>.value(<int>[call]);
      },
    );

    final first = await service.enqueue(requestFor('one'));
    final second = await service.enqueue(requestFor('two'));
    await waitFor(() async => fetchStarted.length == 1);
    expect((await service.task(second.id))?.status, DownloadTaskStatus.queued);

    firstRelease.complete(<int>[1]);
    await waitFor(() async => fetchStarted.length >= 3);
    await waitFor(() async =>
        (await service.task(first.id))?.status == DownloadTaskStatus.completed);
    await waitFor(() async =>
        (await service.task(second.id))?.status ==
        DownloadTaskStatus.completed);
    expect(fetchStarted, hasLength(4));
    await service.dispose();
  });

  test('pauses before writing a returned segment and resumes from checkpoint',
      () async {
    final release = Completer<List<int>>();
    var fetchCount = 0;
    final service = createService(
      root,
      segmentFetcher: (_) {
        fetchCount++;
        return release.future;
      },
    );
    final task = await service.enqueue(requestFor('pause'));
    await waitFor(() async => fetchCount == 1);

    await service.pause(task.id);
    release.complete(<int>[7, 8]);
    await waitFor(() async =>
        (await service.task(task.id))?.status == DownloadTaskStatus.paused);
    expect(fetchCount, 1);

    // The original fetcher is intentionally one-shot for this test. Releasing
    // the same future is enough to prove that pause did not write a part.
    await service.resume(task.id);
    await waitFor(() async => fetchCount >= 2);
    // The fetcher above returns the already completed future on the second
    // attempt, so completion is deterministic without another network call.
    await waitFor(() async =>
        (await service.task(task.id))?.status == DownloadTaskStatus.completed);
    expect(fetchCount, 3);
    await service.dispose();
  });

  test('retries failed segments and concatenates them in playlist order',
      () async {
    final calls = <String>[];
    final service = createService(
      root,
      maxSegmentRetries: 0,
      segmentFetcher: (uri) async {
        calls.add(uri.path);
        if (calls.length == 1) throw StateError('temporary failure');
        return calls.length == 2 ? <int>[1, 2] : <int>[3, 4];
      },
    );
    final task = await service.enqueue(requestFor('retry'));
    await waitFor(() async =>
        (await service.task(task.id))?.status == DownloadTaskStatus.failed);
    expect((await service.task(task.id))?.errorMessage, contains('片段下载失败'));

    await service.retry(task.id);
    await waitFor(() async =>
        (await service.task(task.id))?.status == DownloadTaskStatus.completed);
    final completed = await service.task(task.id);
    final playlist = await File(completed!.outputPath!).readAsString();
    expect(completed.outputPath, endsWith('index.m3u8'));
    expect(playlist, contains('#EXT-X-DISCONTINUITY'));
    expect(playlist, contains('segment_000000.ts'));
    expect(playlist, contains('segment_000001.ts'));
    expect(
      await File('${root.path}/${task.id}/segment_000000.ts').readAsBytes(),
      <int>[1, 2],
    );
    expect(
      await File('${root.path}/${task.id}/segment_000001.ts').readAsBytes(),
      <int>[3, 4],
    );
    expect(completed.totalBytes, 4);
    expect(completed.downloadedBytes, 4);
    expect(
      await service.completedPlaybackSourceForTask(task.id),
      startsWith('http://127.0.0.1:'),
    );
    await service.dispose();
  });

  test('cancel cleans partial files and cache stats track completed output',
      () async {
    final release = Completer<List<int>>();
    final service = createService(
      root,
      segmentFetcher: (_) => release.future,
    );
    final task = await service.enqueue(requestFor('cancel'));
    await waitFor(() async =>
        (await service.task(task.id))?.status ==
        DownloadTaskStatus.downloading);

    await service.cancel(task.id);
    release.complete(<int>[4]);
    await waitFor(() async =>
        (await service.task(task.id))?.status == DownloadTaskStatus.cancelled);
    await waitFor(
        () async => !(await Directory('${root.path}/${task.id}').exists()));

    final stats = await service.cacheStats();
    expect(stats.fileCount, 0);
    await service.dispose();
  });

  test('redownload removes a legacy final.ts and queues current HLS output',
      () async {
    final directoryProvider = DownloadDirectoryProvider.fromDirectory(root);
    final store = DownloadTaskStore(directoryProvider: directoryProvider);
    final now = DateTime.now().toUtc();
    final task = DownloadTask(
      taskId: 'legacy',
      taskKey: 'media-legacy|movie|https://example.test/legacy.m3u8',
      mediaId: 'media-legacy',
      sourceUrl: 'https://example.test/legacy.m3u8',
      status: DownloadTaskStatus.completed,
      totalBytes: 12,
      downloadedBytes: 12,
      outputPath: '${root.path}/legacy/final.ts',
      createdAt: now,
      updatedAt: now,
    );
    await store.save([task]);
    final legacyDirectory = await store.taskDirectory(task.id);
    await File('${legacyDirectory.path}/final.ts').writeAsBytes([1, 2, 3]);

    final service = DownloadService(
      taskStore: store,
      settingsStore: DownloadSettingsStore(
        preferencesProvider: () async {
          final preferences = await SharedPreferences.getInstance();
          await preferences.setString(
            DownloadSettingsStore.storageKey,
            jsonEncode(const DownloadSettings().toJson()),
          );
          return preferences;
        },
      ),
      playlistParser: HlsPlaylistParser(fetcher: (_) async => _playlist),
      segmentFetcher: (_) async => [4, 5],
    );

    await service.redownload(task.id);
    final reset = await service.task(task.id);
    expect(reset?.status,
        isIn([DownloadTaskStatus.queued, DownloadTaskStatus.downloading]));
    expect(reset?.outputPath, isNull);
    expect(reset?.downloadedBytes, 0);
    expect(await File('${root.path}/legacy/final.ts').exists(), isFalse);

    await waitFor(() async =>
        (await service.task(task.id))?.status == DownloadTaskStatus.completed);
    expect((await service.task(task.id))?.outputPath, endsWith('index.m3u8'));
    await service.dispose();
  });
}

DownloadService createService(
  Directory root, {
  required HlsSegmentFetcher segmentFetcher,
  DownloadSettings settings = const DownloadSettings(),
  int maxSegmentRetries = 2,
}) {
  final directoryProvider = DownloadDirectoryProvider.fromDirectory(root);
  final settingsStore = DownloadSettingsStore(
    preferencesProvider: () async {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        DownloadSettingsStore.storageKey,
        jsonEncode(settings.toJson()),
      );
      return preferences;
    },
  );
  return DownloadService(
    directoryProvider: directoryProvider,
    settingsStore: settingsStore,
    playlistParser: HlsPlaylistParser(fetcher: (_) async => _playlist),
    segmentFetcher: segmentFetcher,
    maxSegmentRetries: maxSegmentRetries,
  );
}

DownloadRequest requestFor(String id) => DownloadRequest(
      mediaId: 'media-$id',
      sourceUrl: 'https://example.test/$id/index.m3u8',
      taskId: id,
    );

Future<void> waitFor(Future<bool> Function() predicate) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (await predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Timed out waiting for download state');
}
