import 'dart:io';
import 'package:flutter/services.dart';

class DeviceMusicSnapshot {
  const DeviceMusicSnapshot({required this.granted, this.tracks = const []});
  final bool granted;
  final List<Map<String, dynamic>> tracks;
}

abstract interface class DeviceMusicLibrary {
  bool get supported;
  Stream<void> get changes;
  Future<DeviceMusicSnapshot> scan({bool requestPermission = false});
}

class AndroidDeviceMusicLibrary implements DeviceMusicLibrary {
  static const _methods = MethodChannel('duckmusic/device_music');
  static const _events = EventChannel('duckmusic/device_music_changes');
  @override
  bool get supported => Platform.isAndroid;
  @override
  Stream<void> get changes => _events.receiveBroadcastStream().map((_) {});
  @override
  Future<DeviceMusicSnapshot> scan({bool requestPermission = false}) async {
    if (!supported) return const DeviceMusicSnapshot(granted: false);
    final result = await _methods.invokeMapMethod<String, dynamic>(
        'scan', {'requestPermission': requestPermission});
    return DeviceMusicSnapshot(
      granted: result?['granted'] == true,
      tracks: (result?['tracks'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList(),
    );
  }
}
