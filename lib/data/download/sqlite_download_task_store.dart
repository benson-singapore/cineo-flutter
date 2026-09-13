import 'dart:io';

import '../../core/models/download_models.dart';
import '../repositories/local_media_repository.dart';
import 'download_storage.dart';

/// Bridges the download scheduler to the app's SQLite-backed local state.
/// The scheduler only sees [DownloadTaskPersistence], keeping UI and storage
/// concerns out of the HLS implementation.
class SqliteDownloadTaskStore implements DownloadTaskPersistence {
  SqliteDownloadTaskStore(this.repository);

  final LocalMediaRepository repository;
  final _knownTaskIds = <String>{};

  @override
  Future<Directory> rootDirectory() async {
    final task = await repository.downloadTaskDirectory('_root_probe');
    await task.delete(recursive: true);
    return task.parent;
  }

  @override
  Future<Directory> taskDirectory(String taskId) {
    return repository.downloadTaskDirectory(taskId);
  }

  @override
  Future<void> deleteTaskDirectory(String taskId) {
    return repository.clearDownloadFiles(taskId: taskId);
  }

  @override
  Future<List<DownloadTask>> load() async {
    final tasks = await repository.loadDownloadTasks();
    _knownTaskIds
      ..clear()
      ..addAll(tasks.map((task) => task.id));
    return tasks;
  }

  @override
  Future<void> save(Iterable<DownloadTask> tasks) async {
    final snapshot = tasks.toList(growable: false);
    final currentIds = snapshot.map((task) => task.id).toSet();
    for (final taskId in _knownTaskIds.difference(currentIds)) {
      await repository.deleteDownloadTask(taskId, deleteFiles: false);
    }
    for (final task in snapshot) {
      await repository.saveDownloadTask(task);
    }
    _knownTaskIds
      ..clear()
      ..addAll(currentIds);
  }

  @override
  Future<void> saveCheckpoint({
    required String taskId,
    required Set<int> completedSegments,
  }) {
    return repository.saveDownloadCheckpoint(
      taskId: taskId,
      completedSegments: completedSegments,
    );
  }

  @override
  Future<Set<int>> loadCheckpoint(String taskId) {
    return repository.loadDownloadCheckpoint(taskId);
  }

  @override
  Future<void> deleteCheckpoint(String taskId) {
    return repository.deleteDownloadCheckpoint(taskId);
  }
}
