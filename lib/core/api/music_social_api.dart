import 'api_client.dart';
import '../config/app_config.dart';

/// 听歌时长排行榜的一条记录（对应后端 ListenRankItemView）。
class ListenRankItem {
  const ListenRankItem({
    required this.rank,
    required this.userId,
    required this.username,
    required this.avatarUrl,
    required this.seconds,
  });

  final int rank;
  final int? userId;
  final String username;
  final String? avatarUrl;
  final int seconds;

  factory ListenRankItem.fromJson(Map<String, dynamic> json) {
    return ListenRankItem(
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      userId: (json['userId'] as num?)?.toInt(),
      username: json['username']?.toString() ?? '',
      avatarUrl: json['avatarUrl']?.toString(),
      seconds: (json['seconds'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 周/月听歌时长榜（对应后端 ListenRankingView）。
class ListenRanking {
  const ListenRanking({
    required this.period,
    required this.from,
    required this.to,
    required this.source,
    required this.participants,
    required this.items,
  });

  final String period;
  final String? from;
  final String? to;
  final String? source;
  final int participants;
  final List<ListenRankItem> items;

  factory ListenRanking.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    final items = raw is List
        ? raw
            .whereType<Map>()
            .map((e) => ListenRankItem.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <ListenRankItem>[];
    return ListenRanking(
      period: json['period']?.toString() ?? 'week',
      from: json['from']?.toString(),
      to: json['to']?.toString(),
      source: json['source']?.toString(),
      participants: (json['participants'] as num?)?.toInt() ?? 0,
      items: items,
    );
  }
}

/// 我的听歌数据与排名（对应后端 MyListenTimeView）。
class MyListenTime {
  const MyListenTime({
    required this.totalSec,
    required this.weekSec,
    required this.monthSec,
    required this.weekRank,
    required this.monthRank,
    required this.weekParticipants,
    required this.monthParticipants,
    this.weekSource,
    this.monthSource,
  });

  final int totalSec;
  final int weekSec;
  final int monthSec;
  final int weekRank;
  final int monthRank;
  final int weekParticipants;
  final int monthParticipants;
  final String? weekSource;
  final String? monthSource;

  factory MyListenTime.fromJson(Map<String, dynamic> json) {
    return MyListenTime(
      totalSec: (json['totalSec'] as num?)?.toInt() ?? 0,
      weekSec: (json['weekSec'] as num?)?.toInt() ?? 0,
      monthSec: (json['monthSec'] as num?)?.toInt() ?? 0,
      weekRank: (json['weekRank'] as num?)?.toInt() ?? 0,
      monthRank: (json['monthRank'] as num?)?.toInt() ?? 0,
      weekParticipants: (json['weekParticipants'] as num?)?.toInt() ?? 0,
      monthParticipants: (json['monthParticipants'] as num?)?.toInt() ?? 0,
      weekSource: json['weekSource']?.toString(),
      monthSource: json['monthSource']?.toString(),
    );
  }
}

/// 服务端创建分享后返回的视图（对应后端 MusicShareView）。
class MusicShare {
  const MusicShare({
    required this.token,
    required this.source,
    required this.songId,
    required this.name,
    required this.artist,
    required this.album,
    required this.coverUrl,
    required this.expiresAt,
    required this.viewCount,
    this.durationSec,
    this.requestedQuality,
  });

  final String token;
  final String source;
  final String songId;
  final String name;
  final String artist;
  final String album;
  final String? coverUrl;
  final int? durationSec;
  final String? requestedQuality;
  final String? expiresAt;
  final int viewCount;

  /// 供客户端分享出去的公开链接。
  String get shareUrl => '${AppConfig.userContentBaseUrl}share/music/$token';

  factory MusicShare.fromJson(Map<String, dynamic> json) {
    return MusicShare(
      token: json['token']?.toString() ?? '',
      source: json['source']?.toString() ?? '',
      songId: json['songId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      artist: json['artist']?.toString() ?? '',
      album: json['album']?.toString() ?? '',
      coverUrl: json['coverUrl']?.toString(),
      durationSec: (json['durationSec'] as num?)?.toInt(),
      requestedQuality: json['requestedQuality']?.toString(),
      expiresAt: json['expiresAt']?.toString(),
      viewCount: (json['viewCount'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 异常：分享链接已失效（HTTP 410）。客户端据此给出专门提示。
class ShareExpiredException implements Exception {
  const ShareExpiredException([this.message = '分享链接已过期']);
  final String message;
  @override
  String toString() => message;
}

/// 公开分享详情（对应后端 MusicPublicShareView）。
/// playInfo 保留原始 Map，交给现有的播放链路解析，避免重复建模。
class PublicMusicShare {
  const PublicMusicShare({
    required this.token,
    required this.source,
    required this.songId,
    required this.name,
    required this.artist,
    required this.album,
    required this.coverUrl,
    required this.playable,
    required this.playError,
    required this.viewCount,
    required this.playInfo,
    this.expiresAt,
    this.durationSec,
    this.requestedQuality,
  });

  final String token;
  final String source;
  final String songId;
  final String name;
  final String artist;
  final String album;
  final String? coverUrl;
  final int? durationSec;
  final String? requestedQuality;
  final String? expiresAt;
  final bool playable;
  final String? playError;
  final int viewCount;
  final Map<String, dynamic>? playInfo;

  factory PublicMusicShare.fromJson(Map<String, dynamic> json) {
    final playInfo = json['playInfo'];
    return PublicMusicShare(
      token: json['token']?.toString() ?? '',
      source: json['source']?.toString() ?? '',
      songId: json['songId']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      artist: json['artist']?.toString() ?? '',
      album: json['album']?.toString() ?? '',
      coverUrl: json['coverUrl']?.toString(),
      durationSec: (json['durationSec'] as num?)?.toInt(),
      requestedQuality: json['requestedQuality']?.toString(),
      expiresAt: json['expiresAt']?.toString(),
      playable: json['playable'] as bool? ?? false,
      playError: json['playError']?.toString(),
      viewCount: (json['viewCount'] as num?)?.toInt() ?? 0,
      playInfo:
          playInfo is Map ? Map<String, dynamic>.from(playInfo) : null,
    );
  }
}

/// 听歌时长榜 / 分享 API 客户端。
///
/// 对应 website-backend `codex/tvbox-provider` 分支：
/// - 公开榜：GET /api/public/music/listening/ranking
/// - 我的数据：GET /api/user/music/listening/me
/// - 心跳：POST /api/user/music/listening/heartbeat
/// - 分享读：GET /api/public/music/share/{token}、/{token}/meta
/// - 分享写：GET/POST/DELETE /api/user/music/shares
class MusicSocialApi {
  MusicSocialApi({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  /// period 只能是 week 或 month；后端对其他值返回 400。
  Future<ListenRanking> getListeningRanking({
    String period = 'week',
    int limit = 20,
  }) async {
    final data = await _client.getJson(
      'api/public/music/listening/ranking',
      params: {'period': period, 'limit': '$limit'},
    );
    return ListenRanking.fromJson(data);
  }

  Future<MyListenTime> getMyListenTime(String token) async {
    final data = await _client.getJson(
      'api/user/music/listening/me',
      headers: {'Authorization': 'Bearer $token'},
    );
    return MyListenTime.fromJson(data);
  }

  /// 上报自上次心跳以来真实播放的秒数。未登录时调用方应跳过。
  Future<void> reportHeartbeat(int seconds, String token) async {
    if (seconds <= 0) return;
    await _client.postJson(
      'api/user/music/listening/heartbeat',
      body: {'seconds': seconds},
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<MusicShare?> getShareStatus(
    String source,
    String songId,
    String token,
  ) async {
    final data = await _client.getJson(
      'api/user/music/shares/status',
      params: {'source': source, 'songId': songId},
      headers: {'Authorization': 'Bearer $token'},
    );
    if (data.isEmpty) return null;
    return MusicShare.fromJson(data);
  }

  Future<MusicShare> saveShare({
    required String source,
    required String songId,
    required String name,
    required String artist,
    required String album,
    required String coverUrl,
    required int durationSec,
    String? requestedQuality,
    bool rotateToken = false,
    String? expiresAt,
    required String token,
  }) async {
    final data = await _client.postJson(
      'api/user/music/shares',
      body: {
        'source': source,
        'songId': songId,
        'name': name,
        'artist': artist,
        'album': album,
        'coverUrl': coverUrl,
        'durationSec': durationSec,
        if (requestedQuality != null) 'requestedQuality': requestedQuality,
        'rotateToken': rotateToken,
        if (expiresAt != null) 'expiresAt': expiresAt,
      },
      headers: {'Authorization': 'Bearer $token'},
    );
    return MusicShare.fromJson(data);
  }

  Future<void> deleteShare(
    String source,
    String songId,
    String token,
  ) async {
    await _client.deleteJson(
      'api/user/music/shares',
      params: {'source': source, 'songId': songId},
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  /// 公开查看分享。后端在链接过期时返回 410，这里转成专门异常。
  Future<PublicMusicShare> viewShare(String shareToken) async {
    try {
      final data = await _client.getJson(
        'api/public/music/share/${Uri.encodeComponent(shareToken)}',
      );
      return PublicMusicShare.fromJson(data);
    } on ApiException catch (error) {
      if (error.statusCode == 410) throw const ShareExpiredException();
      rethrow;
    }
  }

  /// 社交预览 meta。只读、不计浏览量，当前端落地页做预览时备用。
  Future<Map<String, dynamic>> shareMeta(String shareToken) async {
    try {
      return await _client.getJson(
        'api/public/music/share/${Uri.encodeComponent(shareToken)}/meta',
      );
    } on ApiException catch (error) {
      if (error.statusCode == 410) throw const ShareExpiredException();
      rethrow;
    }
  }
}
