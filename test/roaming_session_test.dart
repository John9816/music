import 'dart:async';
import 'dart:convert';
import 'package:duck_music/core/api/api_client.dart';
import 'package:duck_music/core/api/qishui_feed_api.dart';
import 'package:duck_music/core/player/roaming_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> page(int seq, List<String> ids) => {
      'sessionId': 'private-session',
      'modeId': 'drive',
      'sequence': seq,
      'nextSequence': seq + 1,
      'hasMore': true,
      'expiresAt':
          DateTime.now().add(const Duration(minutes: 30)).toIso8601String(),
      'list': [
        for (final id in ids)
          {'id': id, 'name': id, 'source': 'qishui', 'artist': 'test'}
      ],
    };
http.Response response(Map<String, dynamic> data) =>
    http.Response(jsonEncode({'code': 0, 'data': data}), 200);

void main() {
  test('stop while prior session closes cannot resurrect a pending start',
      () async {
    final closing = Completer<http.Response>();
    final closeRequested = Completer<void>();
    var starts = 0;
    final client = ApiClient.forTesting(MockClient((r) {
      if (r.method == 'DELETE') {
        closeRequested.complete();
        return closing.future;
      }
      starts++;
      return Future.value(response(page(0, ['a'])));
    }));
    final session = RoamingSession(
        api: QishuiFeedApi(client: client), identity: () => 'one');
    await session.start();
    final restarting = session.start();
    await closeRequested.future;
    await session.stop();
    closing.complete(response({}));
    await restarting;
    expect(session.active, isFalse);
    expect(starts, 1);
    session.dispose();
  });

  test('old next completion cannot unlock the next request of a new session',
      () async {
    final first = Completer<http.Response>();
    final second = Completer<http.Response>();
    var calls = 0;
    final client = ApiClient.forTesting(MockClient((r) {
      if (r.url.path.endsWith('/next')) {
        return ++calls == 1 ? first.future : second.future;
      }
      return Future.value(response(page(0, ['a'])));
    }));
    final session = RoamingSession(
        api: QishuiFeedApi(client: client), identity: () => 'one');
    await session.start();
    final old = session.next();
    await session.start();
    final current = session.next();
    first.complete(response(page(1, ['stale'])));
    await old;
    final duplicate = session.next();
    expect(identical(current, duplicate), isTrue);
    second.complete(response(page(1, ['b'])));
    await current;
    expect(calls, 2);
    expect(session.songs.map((s) => s.id), ['a', 'b']);
    session.dispose();
  });

  test(
      'next retries the same sequence, deduplicates and never auto-replays auth',
      () async {
    var nextCount = 0;
    final sequences = <String?>[];
    final client = ApiClient.forTesting(MockClient((r) async {
      if (r.url.path.endsWith('/next')) {
        sequences.add(r.url.queryParameters['sequence']);
        if (++nextCount == 1) return http.Response('failure', 503);
        return response(page(1, ['a', 'b']));
      }
      return response(page(0, ['a']));
    }));
    final session = RoamingSession(
        api: QishuiFeedApi(client: client), identity: () => 'one');
    await session.start(modeId: 'drive');
    expect(session.songs.map((s) => s.id), ['a']);
    expect(await session.next(), isEmpty);
    expect(session.error, isNotNull);
    expect((await session.next()).map((s) => s.id), ['b']);
    expect(sequences, ['1', '1']);
    expect(session.songs.map((s) => s.id), ['a', 'b']);
    session.dispose();
  });
  test(
      'changed account discards pending session without sending its ID as new account',
      () async {
    final pending = Completer<http.Response>();
    final requested = Completer<void>();
    var identity = 'one';
    var requests = 0;
    final client = ApiClient.forTesting(MockClient((r) {
      requests++;
      requested.complete();
      return pending.future;
    }));
    final session = RoamingSession(
        api: QishuiFeedApi(client: client), identity: () => identity);
    final start = session.start();
    await requested.future;
    identity = 'two';
    pending.complete(response(page(0, ['private-song'])));
    await start;
    expect(session.songs, isEmpty);
    expect(session.active, isFalse);
    await session.stop();
    expect(requests, 1);
    session.dispose();
  });
}
