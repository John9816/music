import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config/app_config.dart';

class ApiException implements Exception {
  ApiException(
    this.message, {
    this.unauthorized = false,
    this.statusCode,
  });

  final String message;
  final bool unauthorized;
  final int? statusCode;

  @override
  String toString() => message;
}

/// 统一 HTTP 客户端，对应 macOS 版 RetrofitClient：
/// 带浏览器 UA/Referer，解析 {code, message, data} 响应外壳。
/// 所有请求带超时 + 中文错误提示，避免网络异常时界面无限转圈。
class ApiClient {
  ApiClient._() : _client = http.Client();

  ApiClient.forTesting(this._client);

  static final ApiClient instance = ApiClient._();

  static const Duration timeout = Duration(seconds: 10);

  final http.Client _client;
  String? bearerToken;
  Future<void> Function()? onUnauthorized;

  Map<String, String> get _headers => {
        'User-Agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
        'Referer': 'https://y.qq.com',
        'Accept-Language': 'zh-CN',
        'Content-Type': 'application/json',
        if (bearerToken != null) 'Authorization': 'Bearer $bearerToken',
      };

  Map<String, String> _requestHeaders(Map<String, String>? headers) {
    final merged = {..._headers, ...?headers};
    final token = bearerToken;
    if (token != null && token.isNotEmpty) {
      merged['Authorization'] = 'Bearer $token';
    }
    return merged;
  }

  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? params,
    Map<String, String>? headers,
  }) {
    return _request(
      () {
        final uri = Uri.parse('${AppConfig.apiBaseUrl}$path')
            .replace(queryParameters: params);
        return _client.get(uri, headers: _requestHeaders(headers));
      },
      retry: true,
    );
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    Object? body,
    Map<String, String>? headers,
    bool retryUnauthorized = true,
  }) {
    return _request(
      () {
        final uri = Uri.parse('${AppConfig.apiBaseUrl}$path');
        return _client.post(
          uri,
          headers: _requestHeaders(headers),
          body: jsonEncode(body ?? const {}),
        );
      },
      retryUnauthorized: retryUnauthorized,
    );
  }

  Future<Map<String, dynamic>> putJson(
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) {
    return _request(() {
      final uri = Uri.parse('${AppConfig.apiBaseUrl}$path');
      return _client.put(
        uri,
        headers: _requestHeaders(headers),
        body: jsonEncode(body ?? const {}),
      );
    });
  }

  Future<Map<String, dynamic>> patchJson(
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) {
    return _request(() {
      final uri = Uri.parse('${AppConfig.apiBaseUrl}$path');
      return _client.patch(
        uri,
        headers: _requestHeaders(headers),
        body: jsonEncode(body ?? const {}),
      );
    });
  }

  /// Uploads one file using multipart/form-data. The multipart request owns
  /// its Content-Type header so the boundary is generated correctly.
  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required String fieldName,
    required List<int> bytes,
    required String filename,
    String? contentType,
    Map<String, String>? fields,
    List<http.MultipartFile> additionalFiles = const [],
    Map<String, String>? headers,
  }) {
    return _request(() async {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConfig.apiBaseUrl}$path'),
      );
      final requestHeaders = _requestHeaders(headers)..remove('Content-Type');
      request.headers.addAll(requestHeaders);
      request.fields.addAll(fields ?? const {});
      request.files.add(
        http.MultipartFile.fromBytes(
          fieldName,
          bytes,
          filename: filename,
          contentType:
              contentType == null ? null : MediaType.parse(contentType),
        ),
      );
      request.files.addAll(additionalFiles);
      final response = await _client.send(request);
      return http.Response.fromStream(response);
    });
  }

  Future<Map<String, dynamic>> deleteJson(
    String path, {
    Map<String, String>? params,
    Map<String, String>? headers,
  }) {
    return _request(() {
      final uri = Uri.parse('${AppConfig.apiBaseUrl}$path')
          .replace(queryParameters: params);
      return _client.delete(uri, headers: _requestHeaders(headers));
    });
  }

  /// 统一执行：超时 + 网络错误转中文 + GET 幂等请求自动重试一次。
  Future<Map<String, dynamic>> _request(
    Future<http.Response> Function() send, {
    bool retry = false,
    bool retryUnauthorized = true,
  }) async {
    http.Response? res;
    try {
      res = await send().timeout(timeout);
    } catch (e) {
      if (retry) {
        try {
          res = await send().timeout(timeout);
        } catch (_) {}
      }
      if (res == null) {
        throw ApiException(_friendlyError(e));
      }
    }
    try {
      return _unwrap(res);
    } on ApiException catch (error) {
      if (!retryUnauthorized ||
          !error.unauthorized ||
          bearerToken == null ||
          onUnauthorized == null) {
        rethrow;
      }
      final previousToken = bearerToken;
      try {
        await onUnauthorized!();
      } catch (_) {}
      if (bearerToken == null || bearerToken == previousToken) rethrow;
      return _request(send, retryUnauthorized: false);
    }
  }

  String _friendlyError(Object e) {
    if (e is TimeoutException) return '请求超时，请检查网络后重试';
    if (e is SocketException) return '网络连接失败（SocketException）';
    if (e is http.ClientException) return '网络请求失败，请检查网络';
    if (e is ApiException) return e.message;
    return '请求失败，请稍后重试';
  }

  /// 解包 V1 响应：{code: 0, data: ...}，非 0 抛 ApiException。
  Map<String, dynamic> _unwrap(http.Response res) {
    Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is! Map) throw const FormatException();
      json = Map<String, dynamic>.from(decoded);
    } catch (_) {
      throw ApiException('服务响应异常（HTTP ${res.statusCode}）');
    }
    final code = json['code'];
    final message = json['message']?.toString();
    final unauthorized = _isUnauthorized(res.statusCode, code, message);
    if (unauthorized) {
      throw ApiException(
        '登录已失效，请重新登录',
        unauthorized: true,
        statusCode: res.statusCode,
      );
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(
        message ?? '请求失败（HTTP ${res.statusCode}）',
        statusCode: res.statusCode,
      );
    }
    if (code != null && code != 0) {
      throw ApiException(message ?? '请求失败 (code=$code)');
    }
    final data = json['data'];
    if (data == null) return const {};
    if (data is Map) return Map<String, dynamic>.from(data);
    if (data is List) return {'list': data};
    return {'value': data};
  }

  bool _isUnauthorized(int statusCode, Object? code, String? message) {
    if (statusCode == 401) return true;
    if (code is num && (code.toInt() == 401 || code.toInt() == 40101)) {
      return true;
    }
    if (code is String) {
      final normalized = code.toUpperCase();
      if (normalized == 'UNAUTHORIZED' ||
          normalized == 'AUTH_REQUIRED' ||
          normalized == 'TOKEN_EXPIRED') {
        return true;
      }
    }
    final normalizedMessage = message?.toLowerCase() ?? '';
    return normalizedMessage.contains('未登录') ||
        normalizedMessage.contains('登录已失效') ||
        normalizedMessage.contains('token expired') ||
        normalizedMessage.contains('unauthorized') ||
        normalizedMessage.contains('unauthenticated');
  }
}
