import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

typedef DownloadRootLoader = Future<Directory> Function();

/// Provides the private application directory used by downloaded media.
///
/// The loader is injectable so storage and scheduler tests can use a temporary
/// directory without touching the device's application-support directory.
class DownloadDirectoryProvider {
  DownloadDirectoryProvider({DownloadRootLoader? rootLoader})
      : _rootLoader = rootLoader ?? _defaultRootLoader;

  DownloadDirectoryProvider.fromDirectory(Directory directory)
      : _rootLoader = (() => Future<Directory>.value(directory));

  final DownloadRootLoader _rootLoader;

  Future<Directory> get root async {
    final directory = await _rootLoader();
    await directory.create(recursive: true);
    return directory;
  }

  Future<Directory> taskDirectory(String taskId) async {
    _validateTaskId(taskId);
    final directory = Directory(path.join((await root).path, taskId));
    await directory.create(recursive: true);
    return directory;
  }

  Future<void> deleteTaskDirectory(String taskId) async {
    _validateTaskId(taskId);
    final directory = Directory(path.join((await root).path, taskId));
    if (await directory.exists()) {
      try {
        await directory.delete(recursive: true);
      } on FileSystemException {
        if (await directory.exists()) rethrow;
      }
    }
  }

  static Future<Directory> _defaultRootLoader() async {
    final support = await getApplicationSupportDirectory();
    return Directory(path.join(support.path, 'Cineo', 'downloads'));
  }

  static void _validateTaskId(String taskId) {
    if (taskId.isEmpty ||
        taskId == '.' ||
        taskId == '..' ||
        taskId.contains('/') ||
        taskId.contains('\\')) {
      throw ArgumentError.value(
          taskId, 'taskId', 'must be a safe path segment');
    }
  }
}

Future<Directory> defaultDownloadDirectoryProvider() async {
  return DownloadDirectoryProvider().root;
}
