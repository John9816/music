import 'dart:convert';

import 'package:duck_music/core/api/ai_draw_api.dart';
import 'package:duck_music/core/api/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('loads the available image models from the backend', () async {
    final client = ApiClient.forTesting(MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/user/image/models');
      expect(request.headers['authorization'], 'Bearer test-token');
      return _response({
        'code': 0,
        'data': [
          {
            'id': 'gpt-image-2',
            'object': 'model',
            'ownedBy': '内置令牌',
          },
        ],
      });
    }))
      ..bearerToken = 'test-token';

    final models = await AiDrawApi(client: client).models();

    expect(models, hasLength(1));
    expect(models.single.id, 'gpt-image-2');
    expect(models.single.ownedBy, '内置令牌');
  });

  test('submits an authenticated task and polls until it completes', () async {
    final requests = <http.Request>[];
    var statusRequestCount = 0;
    final client = ApiClient.forTesting(MockClient((request) async {
      requests.add(request);
      if (request.method == 'POST') {
        expect(jsonDecode(request.body), {'prompt': 'a sunset lake'});
        return _response({
          'code': 0,
          'data': {'id': 42, 'status': 'PENDING'},
        });
      }

      statusRequestCount++;
      if (statusRequestCount == 1) {
        return _response({
          'code': 0,
          'data': {'id': 42, 'status': 'PROCESSING'},
        });
      }
      return _response({
        'code': 0,
        'data': {
          'id': 42,
          'status': 'COMPLETED',
          'result': {
            'data': [
              {'url': 'https://images.example.test/sunset.png'},
            ],
          },
        },
      });
    }))
      ..bearerToken = 'test-token';

    final api = AiDrawApi(
      client: client,
      pollInterval: Duration.zero,
      pollTimeout: const Duration(seconds: 1),
    );

    expect(await api.generate('a sunset lake'),
        'https://images.example.test/sunset.png');
    expect(requests, hasLength(3));
    expect(requests.first.url.path, '/api/user/image/generate');
    expect(requests.first.headers['authorization'], 'Bearer test-token');
    expect(requests[1].url.path, '/api/user/image/generate/42');
    expect(requests[2].url.path, '/api/user/image/generate/42');
  });

  test('reports the backend failure message when a task fails', () async {
    final client = ApiClient.forTesting(MockClient((request) async {
      if (request.method == 'POST') {
        return _response({
          'code': 0,
          'data': {'id': 7, 'status': 'PENDING'},
        });
      }
      return _response({
        'code': 0,
        'data': {
          'id': 7,
          'status': 'FAILED',
          'errorMessage': '上游图片服务额度不足',
        },
      });
    }));

    final api = AiDrawApi(
      client: client,
      pollInterval: Duration.zero,
      pollTimeout: const Duration(seconds: 1),
    );

    await expectLater(
      api.generate('test'),
      throwsA(isA<ApiException>().having(
        (error) => error.message,
        'message',
        '上游图片服务额度不足',
      )),
    );
  });

  test('converts a completed base64 result to an image data URL', () async {
    final client = ApiClient.forTesting(MockClient((request) async {
      if (request.method == 'POST') {
        return _response({
          'code': 0,
          'data': {'id': 9, 'status': 'PENDING'},
        });
      }
      return _response({
        'code': 0,
        'data': {
          'id': 9,
          'status': 'COMPLETED',
          'result': {
            'data': [
              {'b64Json': 'aGVsbG8='},
            ],
          },
        },
      });
    }));

    final api = AiDrawApi(
      client: client,
      pollInterval: Duration.zero,
      pollTimeout: const Duration(seconds: 1),
    );

    expect(await api.generate('test'), 'data:image/png;base64,aGVsbG8=');
  });

  test('uploads an image to the edit endpoint and polls its task', () async {
    final requests = <http.BaseRequest>[];
    final client = ApiClient.forTesting(MockClient((request) async {
      requests.add(request);
      if (request.method == 'POST') {
        expect(request.url.path, '/api/user/image/edit');
        expect(request.headers['authorization'], 'Bearer test-token');
        expect(
            request.headers['content-type'], contains('multipart/form-data'));
        return _response({
          'code': 0,
          'data': {'id': 12, 'status': 'PENDING'},
        });
      }
      return _response({
        'code': 0,
        'data': {
          'id': 12,
          'status': 'COMPLETED',
          'result': {
            'data': [
              {'url': 'https://images.example.test/edited.png'},
            ],
          },
        },
      });
    }))
      ..bearerToken = 'test-token';

    final api = AiDrawApi(
      client: client,
      pollInterval: Duration.zero,
      pollTimeout: const Duration(seconds: 1),
    );

    expect(
      await api.edit(
        bytes: const [1, 2, 3],
        filename: 'source.png',
        prompt: 'remove the background',
        model: 'gpt-image-2',
      ),
      'https://images.example.test/edited.png',
    );
    expect(requests, hasLength(2));
    expect(requests.last.url.path, '/api/user/image/generate/12');
  });

  test('loads resumable tasks with paging and failure details', () async {
    final client = ApiClient.forTesting(MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/user/image/tasks');
      expect(request.url.queryParameters, {'page': '0', 'size': '20'});
      return _response({
        'code': 0,
        'data': {
          'items': [
            {
              'id': 42,
              'prompt': 'a futuristic city skyline',
              'size': '1792x1024',
              'n': 2,
              'model': 'gpt-image-2',
              'status': 'FAILED',
              'errorMessage': 'Upstream returned no image URL',
              'createdAt': '2026-05-17 10:00:00',
            },
          ],
          'total': 1,
          'page': 0,
          'size': 20,
        },
      });
    }));

    final page = await AiDrawApi(client: client).tasks();

    expect(page.total, 1);
    expect(page.items.single.id, 42);
    expect(page.items.single.prompt, 'a futuristic city skyline');
    expect(page.items.single.count, 2);
    expect(page.items.single.isFailed, isTrue);
  });

  test('queries one resumable task by id', () async {
    final client = ApiClient.forTesting(MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/user/image/generate/42');
      return _response({
        'code': 0,
        'data': {
          'id': 42,
          'status': 'COMPLETED',
          'result': {
            'data': [
              {'url': 'https://images.example.test/restored.png'},
            ],
          },
        },
      });
    }));

    final task = await AiDrawApi(client: client).task(42);

    expect(task.status, 'COMPLETED');
    expect(task.imageSource, 'https://images.example.test/restored.png');
  });

  test('loads image history and parses sharing state', () async {
    final client = ApiClient.forTesting(MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/user/image/history');
      expect(request.url.queryParameters, {'page': '1', 'size': '12'});
      return _response({
        'code': 0,
        'data': {
          'items': [
            {
              'id': 1001,
              'prompt': 'a futuristic city skyline',
              'imageUrl': 'https://images.example.test/city.png',
              'model': 'gpt-image-2',
              'size': '1792x1024',
              'isShared': true,
              'createdAt': '2026-05-17 10:00:25',
            },
          ],
          'total': 21,
          'page': 1,
          'size': 12,
        },
      });
    }));

    final page = await AiDrawApi(client: client).history(page: 1, size: 12);

    expect(page.total, 21);
    expect(page.hasMore, isFalse);
    expect(page.items.single.id, 1001);
    expect(page.items.single.imageUrl, 'https://images.example.test/city.png');
    expect(page.items.single.isShared, isTrue);
  });

  test('loads the public shared image plaza', () async {
    final client = ApiClient.forTesting(MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.url.path, '/api/public/image/shared');
      expect(request.url.queryParameters, {'page': '2', 'size': '16'});
      return _response({
        'code': 0,
        'data': {
          'items': [
            {
              'id': 88,
              'prompt': 'album cover in the rain',
              'imageUrl': 'https://images.example.test/shared.png',
              'model': 'gpt-image-2',
              'size': '1024x1024',
              'isShared': true,
            },
          ],
          'total': 33,
          'page': 2,
          'size': 16,
        },
      });
    }));

    final page = await AiDrawApi(client: client).shared(page: 2, size: 16);

    expect(page.total, 33);
    expect(page.items.single.id, 88);
    expect(page.items.single.isShared, isTrue);
  });

  test('shares, deletes, and retries image records using documented paths',
      () async {
    final requests = <http.Request>[];
    final client = ApiClient.forTesting(MockClient((request) async {
      requests.add(request);
      if (request.method == 'POST') {
        return _response({
          'code': 0,
          'data': {'id': 42, 'status': 'PENDING'},
        });
      }
      return _response({'code': 0, 'data': {}});
    }));
    final api = AiDrawApi(client: client);

    await api.setShared(1001, true);
    await api.deleteHistory(1001);
    final task = await api.retry(42);

    expect(requests[0].method, 'PATCH');
    expect(requests[0].url.path, '/api/user/image/history/1001/share');
    expect(requests[0].url.queryParameters, {'shared': 'true'});
    expect(requests[1].method, 'DELETE');
    expect(requests[1].url.path, '/api/user/image/history/1001');
    expect(requests[2].method, 'POST');
    expect(requests[2].url.path, '/api/user/image/history/42/retry');
    expect(task.id, 42);
  });
}

http.Response _response(Map<String, dynamic> body) {
  return http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );
}
