import 'hub_sync_models.dart';

const progressPushIntervals = [5, 10, 15, 30, 60];

int normalizeProgressPushInterval(int? seconds) =>
    progressPushIntervals.contains(seconds) ? seconds! : 10;

bool shouldPushProgress({
  required int? lastValue,
  required int currentValue,
  required Duration elapsed,
  required int intervalSeconds,
}) =>
    lastValue != null &&
    lastValue != currentValue &&
    elapsed >=
        Duration(seconds: normalizeProgressPushInterval(intervalSeconds));

Map<String, bool> coalesceFavoriteChanges(Iterable<(String, bool)> changes) =>
    Map.fromEntries(changes.map((change) => MapEntry(change.$1, change.$2)));

bool canPushOutbox({
  required bool rebuiltThisSync,
  required bool resyncPending,
}) =>
    !rebuiltThisSync && !resyncPending;

int compareSyncEnvelope(SyncEnvelope left, SyncEnvelope right) {
  final time = left.updatedAt.compareTo(right.updatedAt);
  if (time != 0) return time;
  final deleted = (left.deleted ? 1 : 0).compareTo(right.deleted ? 1 : 0);
  if (deleted != 0) return deleted;
  return left.deviceId.compareTo(right.deviceId);
}

List<SyncEnvelope> coalesceOutbox(
  Iterable<SyncEnvelope> existing,
  SyncEnvelope incoming,
) {
  final remaining = existing
      .where(
          (item) => item.entity != incoming.entity || item.key != incoming.key)
      .toList();
  remaining.add(incoming);
  return remaining;
}

Duration retryDelay({required int attempt, int? retryAfterSeconds}) {
  final exponent = attempt.clamp(0, 16);
  final backoffSeconds = (1 << exponent).clamp(1, 300);
  final seconds = retryAfterSeconds == null
      ? backoffSeconds
      : retryAfterSeconds.clamp(backoffSeconds, 86400);
  return Duration(seconds: seconds);
}
