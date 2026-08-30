import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/models/download_models.dart';
import 'download_directory.dart';

abstract interface class DownloadTaskPersistence {
  Future<Directory> rootDirectory();
  Future<Directory> taskDirectory(String taskId);
  Future<void> deleteTaskDirectory(String taskId);
  Future<List<DownloadTask>> load();
  Future<void> save(Iterable<DownloadTask> tasks);
  Future<void> saveCheckpoint({
    required String taskId,
    required Set<int> completedSegments,
  });
  Future<Set<int>> loadCheckpoint(String taskId);
  Future<void> deleteCheckpoint(String taskId);
}

class DownloadTaskStore implements DownloadTaskPersistence {
  DownloadTaskStore({DownloadDirectoryProvider? directoryProvider})
      : _directoryProvider = directoryProvider ?? DownloadDirectoryProvider();

  final DownloadDirectoryProvider _directoryProvider;
  Future<void> _writeQueue = Future<void>.value();

  @override
  Future<Directory> rootDirectory() async {
    return _directoryProvider.root;
  }

  @override
  Future<Directory> taskDirectory(String taskId) async {
    return _directoryProvider.taskDirectory(taskId);
  }

  @override
  Future<void> deleteTaskDirectory(String taskId) async {
    await _directoryProvider.deleteTaskDirectory(taskId);
  }

  @override
  Future<List<DownloadTask>> load() async {
    final file = await _tasksFile();
    if (!await file.exists()) return const <DownloadTask>[];
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return const <DownloadTask>[];
      return decoded
          .whereType<Map>()
          .map((value) =>
              DownloadTask.fromJson(Map<String, dynamic>.from(value)))
          .toList();
    } on FormatException {
      return const <DownloadTask>[];
    } on IOException {
      return const <DownloadTask>[];
    }
  }

  @override
  Future<void> save(Iterable<DownloadTask> tasks) {
    final snapshot = tasks.map((task) => task.toJson()).toList();
    _writeQueue = _writeQueue.then((_) async {
      final file = await _tasksFile();
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(jsonEncode(snapshot), flush: true);
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
    });
    return _writeQueue;
  }

  Future<File> checkpointFile(String taskId) async {
    return File('${(await taskDirectory(taskId)).path}/checkpoint.json');
  }

  @override
  Future<void> saveCheckpoint({
    required String taskId,
    required Set<int> completedSegments,
  }) async {
    final file = await checkpointFile(taskId);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({'completed_segments': completedSegments.toList()..sort()}),
      flush: true,
    );
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }

  @override
  Future<void> deleteCheckpoint(String taskId) async {
    final file = await checkpointFile(taskId);
    if (await file.exists()) await file.delete();
  }

  @override
  Future<Set<int>> loadCheckpoint(String taskId) async {
    final file = await checkpointFile(taskId);
    if (!await file.exists()) return <int>{};
    try {
      final decoded = jsonDecode(await file.readAsString());
      final values = decoded is Map ? decoded['completed_segments'] : null;
      if (values is! List) return <int>{};
      return values.whereType<num>().map((value) => value.toInt()).toSet();
    } on FormatException {
      return <int>{};
    } on IOException {
      return <int>{};
    }
  }

  Future<File> _tasksFile() async {
    final root = await rootDirectory();
    return File('${root.path}/tasks.json');
  }
}
