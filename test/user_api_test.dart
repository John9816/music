import 'dart:convert';

import 'package:duck_music/core/api/api_client.dart';
import 'package:duck_music/core/api/user_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('deletes a playlist and a playlist item through the user API', () async {
    final requests = <http.Request>[];
    final client = ApiClient.forTesting(
      MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({'code': 0, 'data': null}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    final api = UserApi(client: client);

    await api.deleteUserPlaylist('42', 'token');
    await api.deleteUserPlaylistSong('42', '9', 'token');

    expect(requests.map((request) => request.method), ['DELETE', 'DELETE']);
    expect(
      requests.map((request) => request.url.path),
      [
        '/api/user/music/playlists/42',
        '/api/user/music/playlists/42/items/9',
      ],
    );
    expect(
      requests.map((request) => request.headers['authorization']),
      ['Bearer token', 'Bearer token'],
    );
  });
}
