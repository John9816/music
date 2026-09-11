import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'api_client.dart';

/// 图床返回的一条上传结果。
class ImageHostUpload {
  const ImageHostUpload({
    required this.url,
    this.host,
    this.deleteUrl,
  });

  /// 图床直链，可长期外链引用。
  final String url;

  /// 实际落地的图床名称，例如 ImgBB。
  final String? host;

  /// 图床给出的删除地址，仅作展示/留存用。
  final String? deleteUrl;

  factory ImageHostUpload.fromJson(Map<String, dynamic> json) {
    return ImageHostUpload(
      url: json['purl']?.toString().trim() ?? '',
      host: json['host']?.toString(),
      deleteUrl: json['delete_url']?.toString(),
    );
  }
}

/// 巡回寺图床上传客户端（/API/Tuchuang/Tc.php）。
///
/// 不走 [ApiClient]：这个接口在另一个域名上，响应也不是 {code, message, data}
/// 外壳——成功时 code=0，直链直接放在顶层 purl 字段。上传统一用官方上传页同款的
/// form-urlencoded POST，photo 既接受远程直链也接受 data:image/...;base64 串。
class ImageHostApi {
  ImageHostApi({
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  /// 上传远程直链或 data:image/...;base64 源，返回图床直链。
  Future<ImageHostUpload> upload(String source) {
    final value = source.trim();
    if (value.isEmpty) throw ApiException('请提供要上传的图片');
    return _postImage(value);
  }

  /// 上传本地图片字节，内部转成 data URI 走同一个通道。
  Future<ImageHostUpload> uploadBytes({
    required List<int> bytes,
    String contentType = 'image/png',
  }) {
    if (bytes.isEmpty) throw ApiException('请提供要上传的图片');
    return _postImage('data:$contentType;base64,${base64Encode(bytes)}');
  }

  /// 接口文档只说 photo 收「Base64」，没写清楚带不带 data URI 前缀。带前缀是
  /// 官方上传页的形式，所以先按它发；万一服务端只认裸 base64，再补发一次去掉
  /// 前缀的。只在服务端明确拒绝（code != 0）时重试，网络错误直接抛。
  Future<ImageHostUpload> _postImage(String photo) async {
    if (!photo.startsWith('data:')) return _post(photo);
    try {
      return await _post(photo);
    } on ApiException catch (error) {
      // statusCode 非空 = 服务端应答了但拒绝了，才值得换个格式重试；
      // 超时/断网留空，直接抛，免得几 MB 的请求体白发两遍。
      if (error.statusCode == null) rethrow;
      final separator = photo.indexOf(',');
      if (separator <= 0 || separator == photo.length - 1) rethrow;
      return _post(photo.substring(separator + 1));
    }
  }

  Future<ImageHostUpload> _post(String photo) async {
    http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(AppConfig.imageHostUploadUrl),
            headers: const {
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: {'photo': photo, 'type': 'json'},
          )
          .timeout(timeout);
    } catch (e) {
      throw ApiException(_friendlyError(e));
    }

    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) throw const FormatException();
      json = Map<String, dynamic>.from(decoded);
    } catch (_) {
      throw ApiException(
        '图床响应异常（HTTP ${response.statusCode}）',
        statusCode: response.statusCode,
      );
    }

    final code = json['code'];
    if (code is num && code.toInt() != 0) {
      final message = json['msg']?.toString().trim();
      throw ApiException(
        message?.isNotEmpty == true ? message! : '图片上传失败（code=$code）',
        statusCode: response.statusCode,
      );
    }

    final upload = ImageHostUpload.fromJson(json);
    if (upload.url.isEmpty) {
      throw ApiException('图床未返回图片直链', statusCode: response.statusCode);
    }
    return upload;
  }

  String _friendlyError(Object e) {
    if (e is TimeoutException) return '图片上传超时，请稍后重试';
    if (e is SocketException) return '网络连接失败，图片上传中断';
    if (e is http.ClientException) return '图片上传失败，请检查网络';
    return '图片上传失败，请稍后重试';
  }
}
