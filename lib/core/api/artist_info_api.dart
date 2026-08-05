import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/artist_info.dart';
import 'api_client.dart';

/// 遇见 API 的歌手资料接口。
class ArtistInfoApi {
  ArtistInfoApi({http.Client? client}) : _client = client ?? http.Client();

  static const _endpoint = 'https://api.yujn.cn/api/geshou.php';
  static const _timeout = Duration(seconds: 10);

  final http.Client _client;

  Future<ArtistInfo> getArtistInfo(String artistName) async {
    final name = artistName.trim();
    if (name.isEmpty) throw ApiException('歌手名称不能为空');

    final uri = Uri.parse(_endpoint).replace(queryParameters: {
      'type': 'json',
      'msg': name,
    });

    try {
      final response = await _client.get(uri, headers: const {
        'User-Agent': 'DuckMusic-Flutter',
        'Accept': 'application/json',
      }).timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          '歌手信息加载失败（HTTP ${response.statusCode}）',
          statusCode: response.statusCode,
        );
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) throw const FormatException();
      final json = Map<String, dynamic>.from(decoded);
      if (json['code']?.toString() != '200') {
        throw ApiException(json['msg']?.toString() ?? '没有找到该歌手的信息');
      }
      final rawData = json['data'];
      if (rawData is! Map) throw const FormatException();

      final info = ArtistInfo.fromJson(
        Map<String, dynamic>.from(rawData),
        fallbackName: name,
      );
      if (info.profile.isEmpty && info.imageUrl == null) {
        throw ApiException('没有找到该歌手的信息');
      }
      return info;
    } on ApiException {
      rethrow;
    } on TimeoutException {
      throw ApiException('请求超时，请检查网络后重试');
    } on SocketException {
      throw ApiException('网络连接失败，请检查网络');
    } on http.ClientException {
      throw ApiException('网络请求失败，请检查网络');
    } on FormatException {
      throw ApiException('歌手信息服务响应异常');
    } catch (_) {
      throw ApiException('歌手信息加载失败，请稍后重试');
    }
  }
}
