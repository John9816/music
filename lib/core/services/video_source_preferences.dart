import 'package:shared_preferences/shared_preferences.dart';

import '../models/video_source.dart';

/// Persists the last selected video source independently from the server
/// catalog. A removed or disabled source is never returned by [resolve].
class VideoSourcePreferences {
  static const String key = 'videos.selectedSource.v1';

  Future<String?> loadSelectedSource() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(key)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<void> saveSelectedSource(String sourceId) async {
    final value = sourceId.trim();
    final prefs = await SharedPreferences.getInstance();
    if (value.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }

  Future<void> clearSelectedSource() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  Future<VideoSource?> resolve(List<VideoSource> sources) async {
    if (sources.isEmpty) return null;
    final selected = await loadSelectedSource();
    VideoSource? find(String? id) {
      if (id == null) return null;
      for (final source in sources) {
        if (source.id == id && source.enabled) return source;
      }
      return null;
    }

    final preferred = find(selected);
    if (preferred != null) return preferred;
    for (final source in sources) {
      if (source.defaultSource && source.enabled) return source;
    }
    for (final source in sources) {
      if (source.enabled) return source;
    }
    return sources.first;
  }
}
