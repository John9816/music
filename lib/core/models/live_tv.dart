class LiveTvCatalog {
  const LiveTvCatalog({
    required this.groups,
    this.epgUrls = const <String>[],
    this.catchup = '',
    this.catchupSource = '',
  });

  final List<LiveChannelGroup> groups;
  final List<String> epgUrls;
  final String catchup;
  final String catchupSource;

  int get channelCount =>
      groups.fold(0, (total, group) => total + group.channels.length);

  int get lineCount => groups.fold(
        0,
        (total, group) =>
            total +
            group.channels.fold(
              0,
              (channelTotal, channel) => channelTotal + channel.lines.length,
            ),
      );

  Iterable<LiveChannel> get channels =>
      groups.expand((group) => group.channels);
}

class LiveChannelGroup {
  const LiveChannelGroup({
    required this.id,
    required this.name,
    required this.channels,
  });

  final String id;
  final String name;
  final List<LiveChannel> channels;
}

class LiveChannel {
  const LiveChannel({
    required this.id,
    required this.name,
    required this.groupName,
    required this.lines,
    this.tvgId = '',
    this.logoUrl = '',
  });

  final String id;
  final String name;
  final String groupName;
  final String tvgId;
  final String logoUrl;
  final List<LiveLine> lines;
}

class LiveLine {
  const LiveLine({
    required this.id,
    required this.name,
    required this.uri,
  });

  final String id;
  final String name;
  final Uri uri;

  String get protocol => uri.scheme.toUpperCase();
}
