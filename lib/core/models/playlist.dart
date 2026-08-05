/// 歌单模型（对应 macOS 版 Playlist / V1PlaylistItem）。
class Playlist {
  Playlist({
    required this.id,
    required this.name,
    this.source,
    this.coverUrl,
    this.description,
    this.creatorName,
    this.trackCount,
    this.playCount,
  });

  final int id;
  final String name;
  final String? source;
  final String? coverUrl;
  final String? description;
  final String? creatorName;
  final int? trackCount;
  final int? playCount;

  factory Playlist.fromV1(Map<String, dynamic> json) {
    final id = json['id'] is num
        ? (json['id'] as num).toInt()
        : int.tryParse(json['id']?.toString() ?? '') ?? 0;
    final name = json['name']?.toString().trim() ?? '';
    return Playlist(
      id: id,
      name: name,
      source: _optionalText(json['source']),
      coverUrl: _optionalText(json['coverUrl']),
      description: _optionalText(json['description']),
      creatorName: _optionalText(json['creatorName']),
      trackCount: (json['trackCount'] as num?)?.toInt(),
      playCount: (json['playCount'] as num?)?.toInt(),
    );
  }
}

String? _optionalText(Object? value) {
  if (value == null) return null;
  final text = value.toString().trim();
  return text.isEmpty ? null : text;
}

/// 歌单分类（对应 macOS 版 PlaylistCategory）。
class PlaylistCategory {
  const PlaylistCategory({required this.name, this.hot = false});

  final String name;
  final bool hot;

  static const all = PlaylistCategory(name: '全部');
}

/// 歌单分类组（对应 macOS 版 PlaylistCategoryGroup）。
class PlaylistCategoryGroup {
  const PlaylistCategoryGroup({required this.name, required this.categories});

  final String name;
  final List<PlaylistCategory> categories;
}

/// 本地默认分类目录（与 macOS/Android 版一致，不依赖后端接口）。
const List<PlaylistCategoryGroup> kPlaylistCategoryCatalog = [
  PlaylistCategoryGroup(name: '语种', categories: [
    PlaylistCategory(name: '华语', hot: true),
    PlaylistCategory(name: '欧美'),
    PlaylistCategory(name: '日语'),
    PlaylistCategory(name: '韩语'),
    PlaylistCategory(name: '粤语'),
  ]),
  PlaylistCategoryGroup(name: '风格', categories: [
    PlaylistCategory(name: '流行', hot: true),
    PlaylistCategory(name: '摇滚'),
    PlaylistCategory(name: '民谣'),
    PlaylistCategory(name: '电子'),
    PlaylistCategory(name: '说唱'),
    PlaylistCategory(name: '轻音乐'),
    PlaylistCategory(name: '爵士'),
  ]),
  PlaylistCategoryGroup(name: '场景', categories: [
    PlaylistCategory(name: '清晨', hot: true),
    PlaylistCategory(name: '夜晚'),
    PlaylistCategory(name: '学习'),
    PlaylistCategory(name: '工作'),
    PlaylistCategory(name: '运动'),
    PlaylistCategory(name: '驾车'),
    PlaylistCategory(name: '旅行'),
  ]),
  PlaylistCategoryGroup(name: '情绪', categories: [
    PlaylistCategory(name: '治愈', hot: true),
    PlaylistCategory(name: '怀旧'),
    PlaylistCategory(name: '安静'),
    PlaylistCategory(name: '浪漫'),
    PlaylistCategory(name: '伤感'),
    PlaylistCategory(name: '快乐'),
  ]),
  PlaylistCategoryGroup(name: '主题', categories: [
    PlaylistCategory(name: '影视原声', hot: true),
    PlaylistCategory(name: 'ACG'),
    PlaylistCategory(name: '校园'),
    PlaylistCategory(name: '游戏'),
    PlaylistCategory(name: '翻唱'),
    PlaylistCategory(name: '网络歌曲'),
  ]),
];
