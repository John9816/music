import '../models/live_tv.dart';

class LiveM3uParser {
  const LiveM3uParser();

  static final RegExp _attributePattern =
      RegExp(r'''([A-Za-z0-9_-]+)\s*=\s*"([^"]*)"''');

  LiveTvCatalog parse(String source) {
    final lines = source.replaceFirst('\ufeff', '').split(RegExp(r'\r?\n'));
    final header = lines
        .map((line) => line.trim())
        .firstWhere((line) => line.startsWith('#EXTM3U'), orElse: () => '');
    final headerAttributes = _attributes(header);
    final groups = <String, _GroupBuilder>{};
    var channelSequence = 0;
    _EntryMetadata? pending;

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('#EXTINF:')) {
        pending = _entryMetadata(line);
        continue;
      }
      if (line.startsWith('#')) continue;
      final metadata = pending;
      pending = null;
      if (metadata == null) continue;

      final uri = Uri.tryParse(line);
      if (!_isPlayableUri(uri)) continue;
      final channelName = _firstNonEmpty([
        metadata.attributes['tvg-name'],
        metadata.attributes['tvg-id'],
        metadata.title,
      ]);
      if (channelName.isEmpty) continue;
      final groupName = _firstNonEmpty([
        metadata.attributes['group-title'],
        '其他频道',
      ]);
      final group = groups.putIfAbsent(
        groupName,
        () => _GroupBuilder(id: 'group-${groups.length}', name: groupName),
      );
      final channel = group.channels.putIfAbsent(
        channelName,
        () => _ChannelBuilder(
          id: 'channel-${channelSequence++}',
          name: channelName,
          groupName: groupName,
          tvgId: metadata.attributes['tvg-id'] ?? '',
          logoUrl: metadata.attributes['tvg-logo'] ?? '',
        ),
      );
      channel.fillMissingMetadata(
        tvgId: metadata.attributes['tvg-id'] ?? '',
        logoUrl: metadata.attributes['tvg-logo'] ?? '',
      );
      channel.addLine(uri!);
    }

    if (groups.isEmpty) {
      throw const FormatException('M3U document contains no playable channels');
    }

    final epgValue = headerAttributes['x-tvg-url'] ?? '';
    return LiveTvCatalog(
      groups: List<LiveChannelGroup>.unmodifiable(
        groups.values.map((group) => group.build()),
      ),
      epgUrls: List<String>.unmodifiable(
        epgValue
            .split(',')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty),
      ),
      catchup: headerAttributes['catchup'] ?? '',
      catchupSource: headerAttributes['catchup-source'] ?? '',
    );
  }

  Map<String, String> _attributes(String line) => <String, String>{
        for (final match in _attributePattern.allMatches(line))
          match.group(1)!.toLowerCase(): match.group(2) ?? '',
      };

  _EntryMetadata _entryMetadata(String line) {
    final commaIndex = _firstCommaOutsideQuotes(line);
    final attributesPart =
        commaIndex < 0 ? line : line.substring(0, commaIndex);
    final title = commaIndex < 0 ? '' : line.substring(commaIndex + 1).trim();
    return _EntryMetadata(
        attributes: _attributes(attributesPart), title: title);
  }

  int _firstCommaOutsideQuotes(String value) {
    var quoted = false;
    for (var index = 0; index < value.length; index++) {
      final character = value[index];
      if (character == '"') {
        quoted = !quoted;
      } else if (character == ',' && !quoted) {
        return index;
      }
    }
    return -1;
  }

  bool _isPlayableUri(Uri? uri) =>
      uri != null &&
      uri.host.isNotEmpty &&
      (uri.scheme.toLowerCase() == 'http' ||
          uri.scheme.toLowerCase() == 'https');

  String _firstNonEmpty(Iterable<String?> values) {
    for (final value in values) {
      final normalized = value?.trim() ?? '';
      if (normalized.isNotEmpty) return normalized;
    }
    return '';
  }
}

class _EntryMetadata {
  const _EntryMetadata({required this.attributes, required this.title});

  final Map<String, String> attributes;
  final String title;
}

class _GroupBuilder {
  _GroupBuilder({required this.id, required this.name});

  final String id;
  final String name;
  final Map<String, _ChannelBuilder> channels = <String, _ChannelBuilder>{};

  LiveChannelGroup build() => LiveChannelGroup(
        id: id,
        name: name,
        channels: List<LiveChannel>.unmodifiable(
          channels.values.map((channel) => channel.build()),
        ),
      );
}

class _ChannelBuilder {
  _ChannelBuilder({
    required this.id,
    required this.name,
    required this.groupName,
    required this.tvgId,
    required this.logoUrl,
  });

  final String id;
  final String name;
  final String groupName;
  String tvgId;
  String logoUrl;
  final List<LiveLine> lines = <LiveLine>[];

  void fillMissingMetadata({required String tvgId, required String logoUrl}) {
    if (this.tvgId.isEmpty && tvgId.isNotEmpty) this.tvgId = tvgId;
    if (this.logoUrl.isEmpty && logoUrl.isNotEmpty) this.logoUrl = logoUrl;
  }

  void addLine(Uri uri) {
    final number = lines.length + 1;
    lines.add(LiveLine(
      id: '$id-line-$number',
      name: '线路 $number',
      uri: uri,
    ));
  }

  LiveChannel build() => LiveChannel(
        id: id,
        name: name,
        groupName: groupName,
        tvgId: tvgId,
        logoUrl: logoUrl,
        lines: List<LiveLine>.unmodifiable(lines),
      );
}
