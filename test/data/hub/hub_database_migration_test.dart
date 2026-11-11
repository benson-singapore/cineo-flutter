import 'dart:io';
import 'package:cineo_flutter/core/models/media.dart';
import 'package:cineo_flutter/data/repositories/local_media_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  test('upgrades version 14 and preserves existing favorites', () async {
    final directory = await Directory.systemTemp.createTemp('hub-migration-');
    final path = '${directory.path}/cineo.db';
    var repository = LocalMediaRepository(databasePath: path);
    const media = MediaItem(
        id: 'legacy:1',
        title: 'Keep me',
        description: '',
        year: 2025,
        kind: MediaKind.movie,
        posterUrl: '',
        backdropUrl: '',
        genres: [],
        rating: 0,
        duration: Duration(minutes: 90));
    await repository.setFavorite(media, true);
    await repository.close();
    final oldDb = await databaseFactory.openDatabase(path);
    await oldDb.execute('PRAGMA user_version = 14');
    await oldDb.close();
    repository = LocalMediaRepository(databasePath: path);
    expect((await repository.favorites()).single.title, 'Keep me');
    final db = await repository.hubDatabase;
    expect(
        await db
            .rawQuery("SELECT name FROM sqlite_master WHERE name LIKE 'hub_%'"),
        hasLength(2));
    await repository.close();
    await directory.delete(recursive: true);
  });
}
