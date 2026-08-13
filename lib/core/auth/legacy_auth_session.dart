import 'package:flutter/services.dart';

class LegacyAuthSession {
  const LegacyAuthSession({
    required this.accessToken,
    required this.refreshToken,
    this.expiresAtMs,
    this.userId,
  });

  final String accessToken;
  final String refreshToken;
  final int? expiresAtMs;
  final String? userId;

  static LegacyAuthSession? fromMap(Map<Object?, Object?> values) {
    final accessToken = _string(values['accessToken']);
    final refreshToken = _string(values['refreshToken']);
    if (accessToken == null || refreshToken == null) return null;

    return LegacyAuthSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAtMs: _positiveInt(values['expiresAtMs']),
      userId: _string(values['userId']),
    );
  }

  static String? _string(Object? value) {
    final normalized = value?.toString().trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static int? _positiveInt(Object? value) {
    final parsed =
        value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');
    return parsed != null && parsed > 0 ? parsed : null;
  }
}

abstract interface class LegacyAuthSessionSource {
  Future<LegacyAuthSession?> read();

  Future<void> clear();
}

class MethodChannelLegacyAuthSessionSource implements LegacyAuthSessionSource {
  const MethodChannelLegacyAuthSessionSource({
    this.channel = const MethodChannel('duckmusic/legacy_auth_session'),
  });

  final MethodChannel channel;

  @override
  Future<LegacyAuthSession?> read() async {
    try {
      final values =
          await channel.invokeMethod<Object?>('readLegacyAuthSession');
      if (values is! Map) return null;
      return LegacyAuthSession.fromMap(Map<Object?, Object?>.from(values));
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<void> clear() async {
    try {
      await channel.invokeMethod<void>('clearLegacyAuthSession');
    } on MissingPluginException {
      return;
    } on PlatformException {
      return;
    }
  }
}
