import 'dart:convert';

import 'package:duck_music/core/api/api_client.dart';
import 'package:duck_music/core/api/image_host_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('uploads a remote image url and returns the hosted direct link',
      () async {
    late http.Request captured;
    final api = ImageHostApi(
      client: MockClient((request) async {
        captured = request;
        return _response({
          'code': 0,
          'purl': 'https://i.ibb.co/qLvbHvL8/image.jpg',
          'host': 'ImgBB',
          'delete_url': 'https://ibb.co/xxx/delete',
          'source': '【巡回寺API】',
        });
      }),
    );

    final upload = await api.upload('https://images.example.test/sunset.png');

    expect(captured.method, 'POST');
    expect(captured.url.host, 'api.xunhuisi.store');
    expect(captured.url.path, '/API/Tuchuang/Tc.php');
    expect(captured.bodyFields['photo'], 'https://images.example.test/sunset.png');
    expect(captured.bodyFields['type'], 'json');
    expect(upload.url, 'https://i.ibb.co/qLvbHvL8/image.jpg');
    expect(upload.host, 'ImgBB');
    expect(upload.deleteUrl, 'https://ibb.co/xxx/delete');
  });

  test('sends generated base64 results as a data uri', () async {
    late http.Request captured;
    final api = ImageHostApi(
      client: MockClient((request) async {
        captured = request;
        return _response({'code': 0, 'purl': 'https://i.ibb.co/a/b.png'});
      }),
    );

    await api.uploadBytes(bytes: const [1, 2, 3], contentType: 'image/png');

    expect(
      captured.bodyFields['photo'],
      'data:image/png;base64,${base64Encode(const [1, 2, 3])}',
    );
  });

  test('retries base64 without the data uri prefix when the host rejects it',
      () async {
    final sent = <String>[];
    final api = ImageHostApi(
      client: MockClient((request) async {
        final photo = request.bodyFields['photo']!;
        sent.add(photo);
        if (photo.startsWith('data:')) {
          return _response({'code': -1, 'msg': '请提供图片参数 photo'});
        }
        return _response({'code': 0, 'purl': 'https://i.ibb.co/a/b.png'});
      }),
    );

    final upload =
        await api.uploadBytes(bytes: const [1, 2, 3], contentType: 'image/png');

    final encoded = base64Encode(const [1, 2, 3]);
    expect(sent, ['data:image/png;base64,$encoded', encoded]);
    expect(upload.url, 'https://i.ibb.co/a/b.png');
  });

  test('does not retry a data uri when the upload fails on the network',
      () async {
    var attempts = 0;
    final api = ImageHostApi(
      client: MockClient((_) async {
        attempts++;
        throw http.ClientException('connection reset');
      }),
    );

    await expectLater(
      api.uploadBytes(bytes: const [1, 2, 3]),
      throwsA(isA<ApiException>()),
    );
    expect(attempts, 1);
  });

  test('never retries a plain url source', () async {
    var attempts = 0;
    final api = ImageHostApi(
      client: MockClient((_) async {
        attempts++;
        return _response({'code': -1, 'msg': '图片地址无法访问'});
      }),
    );

    await expectLater(
      api.upload('https://images.example.test/broken.png'),
      throwsA(isA<ApiException>()),
    );
    expect(attempts, 1);
  });

  test('surfaces the image host error message', () async {
    final api = ImageHostApi(
      client: MockClient((_) async {
        return _response({
          'code': -1,
          'msg': '请提供图片参数 photo',
          'source': '【巡回寺API】',
        });
      }),
    );

    await expectLater(
      api.upload('https://images.example.test/broken.png'),
      throwsA(isA<ApiException>().having(
        (e) => e.message,
        'message',
        '请提供图片参数 photo',
      )),
    );
  });

  test('rejects a success payload without a direct link', () async {
    final api = ImageHostApi(
      client: MockClient((_) async => _response({'code': 0, 'purl': ''})),
    );

    await expectLater(
      api.upload('https://images.example.test/sunset.png'),
      throwsA(isA<ApiException>()),
    );
  });

  test('rejects empty sources before hitting the network', () async {
    var called = false;
    final api = ImageHostApi(
      client: MockClient((_) async {
        called = true;
        return _response({'code': 0, 'purl': 'https://i.ibb.co/a/b.png'});
      }),
    );

    expect(() => api.upload('   '), throwsA(isA<ApiException>()));
    expect(() => api.uploadBytes(bytes: const []), throwsA(isA<ApiException>()));
    expect(called, isFalse);
  });
}

http.Response _response(Map<String, dynamic> body) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
