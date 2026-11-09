import '../models/song.dart';
import 'api_client.dart';

class RoamingMode {
  const RoamingMode(
      {required this.id, required this.name, this.group = '', this.iconUrl});
  factory RoamingMode.fromJson(Map<String, dynamic> json) => RoamingMode(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      group: json['group']?.toString() ?? '',
      iconUrl: json['iconUrl']?.toString());
  final String id, name, group;
  final String? iconUrl;
}

class RoamingPage {
  RoamingPage.fromJson(Map<String, dynamic> json)
      : sessionId = json['sessionId']?.toString() ?? '',
        modeId = json['modeId']?.toString(),
        nextSequence = (json['nextSequence'] as num?)?.toInt() ?? 1,
        hasMore = json['hasMore'] == true,
        expiresAt = DateTime.tryParse(json['expiresAt']?.toString() ?? ''),
        songs = (json['list'] as List? ?? const [])
            .whereType<Map>()
            .map((j) => Song.fromV1(Map<String, dynamic>.from(j)))
            .where((s) => s.id.isNotEmpty)
            .toList();
  final String sessionId;
  final String? modeId;
  final int nextSequence;
  final bool hasMore;
  final DateTime? expiresAt;
  final List<Song> songs;
}

class QishuiFeedApi {
  QishuiFeedApi({ApiClient? client}) : _client = client ?? ApiClient.instance;
  final ApiClient _client;
  static const _base = 'api/v1/music/qishui';
  Future<List<RoamingMode>> modes() async {
    final json = await _client.getJson('$_base/roaming/modes',
        retry: false, retryUnauthorized: false);
    return (json['list'] as List? ?? const [])
        .whereType<Map>()
        .map((j) => RoamingMode.fromJson(Map<String, dynamic>.from(j)))
        .where((m) => m.id.isNotEmpty)
        .toList();
  }

  Future<List<Song>> discovery() async {
    final json = await _client.getJson('$_base/discovery',
        retry: false, retryUnauthorized: false);
    return (json['list'] as List? ?? const [])
        .whereType<Map>()
        .map((j) => Song.fromV1(Map<String, dynamic>.from(j)))
        .toList();
  }

  Future<RoamingPage> start({String? modeId}) async =>
      RoamingPage.fromJson(await _client.postJson(
          '$_base/roaming/sessions${modeId == null ? '' : '?modeId=${Uri.encodeQueryComponent(modeId)}'}',
          retryUnauthorized: false));
  Future<RoamingPage> next(String id, int sequence, {String? modeId}) async =>
      RoamingPage.fromJson(await _client.postJson(
          '$_base/roaming/sessions/${Uri.encodeComponent(id)}/next?sequence=$sequence${modeId == null ? '' : '&modeId=${Uri.encodeQueryComponent(modeId)}'}',
          retryUnauthorized: false));
  Future<void> close(String id) async {
    await _client.deleteJson(
        '$_base/roaming/sessions/${Uri.encodeComponent(id)}',
        retryUnauthorized: false);
  }
}
