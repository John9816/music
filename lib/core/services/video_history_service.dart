import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class VideoHistoryEntry {
  const VideoHistoryEntry({
    required this.source,
    required this.videoId,
    required this.episodeId,
    required this.lineId,
    required this.position,
  });

  factory VideoHistoryEntry.fromJson(Map<String, dynamic> json) {
    return VideoHistoryEntry(
      source: '${json['source'] ?? ''}',
      videoId: '${json['videoId'] ?? ''}',
      episodeId: '${json['episodeId'] ?? ''}',
      lineId: '${json['lineId'] ?? ''}',
      position: Duration(
        milliseconds: _intValue(json['positionMs']).clamp(0, 1 << 53),
      ),
    );
  }

  final String source;
  final String videoId;
  final String episodeId;
  final String lineId;
  final Duration position;

  Map<String, dynamic> toJson() => {
        'source': source,
        'videoId': videoId,
        'episodeId': episodeId,
        'lineId': lineId,
        'positionMs': position.inMilliseconds,
      };
}

class VideoHistoryService {
  static const _keyPrefix = 'videos.history.';

  Future<VideoHistoryEntry?> load(String source, String videoId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(source, videoId));
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final entry = VideoHistoryEntry.fromJson(
        Map<String, dynamic>.from(decoded),
      );
      if (entry.source != source ||
          entry.videoId != videoId ||
          entry.episodeId.isEmpty ||
          entry.lineId.isEmpty) {
        return null;
      }
      return entry;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(VideoHistoryEntry entry) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(entry.source, entry.videoId),
      jsonEncode(entry.toJson()),
    );
  }

  String _key(String source, String videoId) => '$_keyPrefix$source.$videoId';
}

int _intValue(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}
