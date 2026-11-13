import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taleemplus_app/data/local/offline_cache.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OfflineCache.instance.scope = 'user-1';
  });

  test('round-trips a GET payload and reports when it was saved', () async {
    final cache = OfflineCache.instance;
    await cache.write('/classes', [
      {'id': 'c1', 'className': '9th'}
    ]);
    final hit = await cache.read('/classes');
    expect(hit, isNotNull);
    expect((hit!.data as List).first['className'], '9th');
    expect(
        DateTime.now().difference(hit.savedAt).inSeconds, lessThanOrEqualTo(5));
  });

  test('is scoped per user and disabled without a scope', () async {
    final cache = OfflineCache.instance;
    await cache.write('/auth/me', {'id': 'user-1'});
    cache.scope = 'user-2';
    expect(await cache.read('/auth/me'), isNull);
    cache.scope = null;
    await cache.write('/auth/me', {'id': 'nobody'});
    expect(await cache.read('/auth/me'), isNull);
    cache.scope = 'user-1';
    expect((await cache.read('/auth/me'))!.data['id'], 'user-1');
  });

  test('evicts the oldest entries beyond the cap and clears on sign-out',
      () async {
    final cache = OfflineCache.instance;
    for (var i = 0; i < OfflineCache.maxEntries + 5; i++) {
      await cache.write('/items/$i', i);
    }
    expect(await cache.read('/items/0'), isNull);
    expect(await cache.read('/items/4'), isNull);
    expect((await cache.read('/items/5'))!.data, 5);
    expect((await cache.read('/items/${OfflineCache.maxEntries + 4}'))!.data,
        OfflineCache.maxEntries + 4);

    await cache.clear();
    expect(cache.scope, isNull);
    cache.scope = 'user-1';
    expect(await cache.read('/items/5'), isNull);
  });

  test('skips oversized and non-JSON payloads without throwing', () async {
    final cache = OfflineCache.instance;
    await cache.write('/big', 'x' * (OfflineCache.maxEntryBytes + 1));
    expect(await cache.read('/big'), isNull);
    await cache.write('/binary', Object());
    expect(await cache.read('/binary'), isNull);
  });
}
