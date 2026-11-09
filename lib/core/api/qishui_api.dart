import 'dart:convert';
import 'dart:typed_data';
import 'api_client.dart';

class QishuiAccountInfo {
  QishuiAccountInfo.fromJson(Map<String, dynamic> json)
      : bound = json['bound'] == true,
        status = json['status']?.toString() ?? 'unbound',
        sessionId = json['sessionId']?.toString(),
        nickname = json['nickname']?.toString(),
        avatarUrl = json['avatarUrl']?.toString(),
        vip = json['vip'] == true,
        qrcode = json['qrcode']?.toString(),
        qrcodeUrl = json['qrcodeUrl']?.toString(),
        expiresAt = DateTime.tryParse(json['expiresAt']?.toString() ?? ''),
        sessionExpiresAt =
            DateTime.tryParse(json['sessionExpiresAt']?.toString() ?? ''),
        pollSeconds =
            ((json['pollIntervalSeconds'] as num?)?.toInt() ?? 2).clamp(2, 10);
  final bool bound, vip;
  final String status;
  final String? sessionId, nickname, avatarUrl, qrcode, qrcodeUrl;
  final DateTime? expiresAt, sessionExpiresAt;
  final int pollSeconds;
  bool get pending => status == 'new' || status == 'scanned';
  Uint8List? get qrBytes {
    final value = qrcode;
    if (value == null || value.length > 2000000) return null;
    try {
      return base64Decode(
          value.replaceFirst(RegExp(r'^data:image/png;base64,'), ''));
    } catch (_) {
      return null;
    }
  }
}

class QishuiApi {
  QishuiApi({ApiClient? client}) : _client = client ?? ApiClient.instance;
  final ApiClient _client;
  static const _base = 'api/v1/music/qishui';
  // Session operations must never be replayed with another account's token.
  Future<QishuiAccountInfo> account() async =>
      QishuiAccountInfo.fromJson(await _client.getJson('$_base/account',
          retry: false, retryUnauthorized: false));
  Future<QishuiAccountInfo> start() async => QishuiAccountInfo.fromJson(
      await _client.postJson('$_base/auth/qr', retryUnauthorized: false));
  Future<QishuiAccountInfo> poll(String sessionId) async =>
      QishuiAccountInfo.fromJson(await _client.getJson(
          '$_base/auth/qr/${Uri.encodeComponent(sessionId)}',
          retry: false,
          retryUnauthorized: false));
  Future<QishuiAccountInfo> refresh() async =>
      QishuiAccountInfo.fromJson(await _client
          .postJson('$_base/account/refresh', retryUnauthorized: false));
  Future<void> unbind() async {
    await _client.deleteJson('$_base/account', retryUnauthorized: false);
  }
}
