import 'package:flutter_test/flutter_test.dart';
import 'package:cineo_flutter/core/models/media_source.dart';
import 'package:cineo_flutter/data/hub/hub_sync_keys.dart';
import 'package:cineo_flutter/data/hub/hub_sync_models.dart';
import 'package:cineo_flutter/data/hub/hub_sync_policy.dart';

void main() {
  test('site mapping omits demo and local-only fields', () {
    const source = MediaSource(
      id: 'local-id',
      name: 'Site',
      type: MediaSourceType.macCmsApi,
      baseUrl: 'https://example.test/vod?key=secret',
      isFavorite: true,
      lastError: 'local error',
      lastLatencyMs: 4,
    );
    final envelope = siteEnvelope(source, updatedAt: 7)!;
    expect(envelope.key, isNot('local-id'));
    expect(
        envelope.payload!.keys,
        containsAll([
          'name',
          'api',
          'detail_url',
          'enabled',
          'is_adult',
          'is_default',
          'site_type',
          'cover_mode',
          'cache_ttl_seconds',
        ]));
    expect(envelope.payload!.keys, isNot(contains('last_error')));
    expect(siteEnvelope(source.copyWith(), updatedAt: 8), isNotNull);
    expect(siteEnvelope(source.copyWith(), updatedAt: 8)!.payload!['api'],
        contains('key=secret'));
    expect(
        siteEnvelope(
            const MediaSource(
                id: 'd',
                name: 'Demo',
                type: MediaSourceType.demo,
                baseUrl: 'demo://'),
            updatedAt: 1),
        isNull);
  });

  test('unknown site type is preserved but is not usable', () {
    final decoded = decodeSitePayload('key', {
      'name': 'Future',
      'api': 'https://example.test',
      'site_type': 'future',
      'extension': {'x': 1},
    });
    expect(decoded.rawPayload['extension'], {'x': 1});
    expect(decoded.isKnownType, isFalse);
  });

  test('outbox coalesces same entity and key', () {
    const old = SyncEnvelope(
        entity: 'favorite',
        key: 'k',
        updatedAt: 1,
        deleted: false,
        payload: {'title': 'old'});
    final newer = old.copyWith(updatedAt: 2, deleted: true, payload: null);
    expect(coalesceOutbox([old], newer), [newer]);
  });

  test('LWW ties prefer deleted then lexically larger device id', () {
    const live = SyncEnvelope(
        entity: 'site',
        key: 'k',
        updatedAt: 3,
        deleted: false,
        payload: {},
        deviceId: 'z');
    final tombstone =
        live.copyWith(deleted: true, payload: null, deviceId: 'a');
    expect(compareSyncEnvelope(tombstone, live), greaterThan(0));
    expect(compareSyncEnvelope(live, live.copyWith(deviceId: 'a')),
        greaterThan(0));
  });

  test('blocks outbox replay while a rebuild needs user resolution', () {
    expect(canPushOutbox(rebuiltThisSync: true, resyncPending: false), isFalse);
    expect(canPushOutbox(rebuiltThisSync: false, resyncPending: true), isFalse);
    expect(canPushOutbox(rebuiltThisSync: false, resyncPending: false), isTrue);
  });

  test('media keys use Android compatible percent encoding', () {
    expect(syncEncode('a !*()~'), 'a%20%21*%28%29%7E');
  });

  test('backoff is capped and honors Retry-After', () {
    expect(retryDelay(attempt: 20, retryAfterSeconds: 420),
        const Duration(seconds: 420));
    expect(retryDelay(attempt: 12), const Duration(minutes: 5));
  });
}
