import 'dart:math' as math;

import '../models/song.dart';

/// 自动换源打分匹配器（对标 TuneFreeNext 4.3.7 的
/// `AutomaticSourceFallbackResolver`：`_normalize` / `_matchScore` /
/// `_bestCandidateOrNull`）。
///
/// 纯逻辑、无 IO、无 Flutter 依赖：给定原曲与某备用音源搜索到的候选列表，
/// 用「归一化歌名 + 歌手 + 时长」打分，挑出最可能是同一首歌的候选。
/// 打分选最佳（而非顺序取第一个）能显著降低换源播错歌的概率。
class SourceFallbackResolver {
  const SourceFallbackResolver();

  /// 匹配通过的最低分。低于此分视为不同歌曲，宁可跳过也不播错。
  static const double acceptThreshold = 0.55;

  /// 归一化歌名/歌手：去括号附注 + 小写 + 全角转半角 + 去噪音词 + 去标点空白。
  ///
  /// 例：`告白气球 (Live版)` -> `告白气球`，`Hello [Remix]` -> `hello`。
  static String normalize(String value) {
    var text = value
        .replaceAll(RegExp(r'[\(（\[【][^)）\]】]*[)）\]】]'), ' ')
        .toLowerCase();

    // Dart 无内置 NFKC，手工映射常见全角字符（FF01-FF5E / 全角空格）。
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      if (rune >= 0xFF01 && rune <= 0xFF5E) {
        buffer.writeCharCode(rune - 0xFEE0);
      } else if (rune == 0x3000) {
        buffer.write(' ');
      } else {
        buffer.writeCharCode(rune);
      }
    }
    text = buffer.toString();

    for (final noise in _noiseWords) {
      text = text.replaceAll(noise, ' ');
    }
    // 只保留中文 / 字母 / 数字，其余标点空白统一为空格。
    text = text.replaceAll(RegExp(r'[^\u4e00-\u9fff0-9a-z]+'), ' ');
    return text.trim();
  }

  /// 明确的版本噪音词。刻意不放单字「版」或易误伤的 mv/hd，
  /// 避免把正常歌名里的字去掉。
  static const List<String> _noiseWords = [
    'remix',
    'karaoke',
    'instrumental',
    'official',
    'acoustic',
    'live',
    '现场版',
    '现场',
    '伴奏',
    '纯音乐',
    '重制版',
    '高清版',
    '正式版',
    '官方版',
  ];

  /// 综合匹配分，范围 [0,1]。歌名权重最高，歌手与时长作为加分项。
  double matchScore(Song target, Song candidate) {
    final nameScore = _nameScore(
      normalize(target.name),
      normalize(candidate.name),
    );
    var score = nameScore * 0.65;

    if (_artistMatches(target, candidate)) score += 0.25;

    if (target.durationMs > 0 && candidate.durationMs > 0) {
      final diff = (target.durationMs - candidate.durationMs).abs();
      final longer = math.max(target.durationMs, candidate.durationMs);
      if (diff / longer < 0.15) score += 0.10;
    }
    return score.clamp(0.0, 1.0).toDouble();
  }

  /// 从候选里挑出最高分且过阈值的候选；没有可达标的候选则返回 null。
  Song? bestCandidateOrNull(Song target, List<Song> candidates) {
    Song? best;
    var bestScore = 0.0;
    for (final candidate in candidates) {
      if (_key(candidate) == _key(target)) continue;
      final score = matchScore(target, candidate);
      if (score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    return bestScore >= acceptThreshold ? best : null;
  }

  String _key(Song song) => '${song.source}:${song.id}';

  double _nameScore(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1;
    final shorter = a.length <= b.length ? a : b;
    if (shorter.length >= 2 && (a.contains(b) || b.contains(a))) return 0.85;
    return _lcsRatio(a, b);
  }

  /// 最长公共子序列相似度：2*lcs/(lenA+lenB)，范围 [0,1]。
  double _lcsRatio(String a, String b) {
    final m = a.length;
    final n = b.length;
    if (m == 0 || n == 0) return 0;
    final dp = List<List<int>>.generate(
      m + 1,
      (_) => List<int>.filled(n + 1, 0),
    );
    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        dp[i][j] = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1)
            ? dp[i - 1][j - 1] + 1
            : math.max(dp[i - 1][j], dp[i][j - 1]);
      }
    }
    return 2 * dp[m][n] / (m + n);
  }

  bool _artistMatches(Song target, Song candidate) {
    final targetArtists = target.artists
        .map((artist) => normalize(artist.name))
        .where((name) => name.isNotEmpty)
        .toList();
    final candidateArtists = candidate.artists
        .map((artist) => normalize(artist.name))
        .where((name) => name.isNotEmpty)
        .toList();
    for (final a in targetArtists) {
      for (final b in candidateArtists) {
        if (a == b) return true;
        if (a.length >= 2 &&
            b.length >= 2 &&
            (a.contains(b) || b.contains(a))) {
          return true;
        }
      }
    }
    return false;
  }
}
