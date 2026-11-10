import 'dart:async';
import 'dart:convert';

import 'package:duck_music/core/api/api_client.dart';
import 'package:duck_music/core/auth/auth_controller.dart';
import 'package:duck_music/core/models/song.dart';
import 'package:duck_music/core/player/player_controller.dart';
import 'package:duck_music/core/services/sleep_timer.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:duck_music/core/settings/lyric_appearance.dart';
import 'package:duck_music/core/theme/app_theme.dart';
import 'package:duck_music/features/player/mini_player.dart';
import 'package:duck_music/features/player/player_view.dart';
import 'package:duck_music/features/player/karaoke_lyric_text.dart';
import 'package:duck_music/features/player/spectrum_player_view.dart';
import 'package:duck_music/features/player/desktop_player_panel.dart';
import 'package:duck_music/widgets/glass.dart';
import 'package:flutter/cupertino.dart' as cupertino;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

late Future<http.Response> Function(http.Request) _handleRequest;

void main() {
  setUpAll(() {
    http.runWithClient(
      () => ApiClient.instance,
      () => MockClient((request) => _handleRequest(request)),
    );
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(const {});
    _handleRequest = (_) async => _response(const {'items': []});
  });

  testWidgets(
      'reference player uses artwork backdrop and left aligned identity',
      (tester) async {
    await _pumpPlayer(tester, themeId: 'light');
    final title = find.text('Test song same-id');
    expect(tester.widget<Text>(title).textAlign, TextAlign.left);
    expect(find.byType(ImageFiltered), findsWidgets);
    final titleRect = tester.getRect(title);
    expect(titleRect.left, closeTo(28, 1));
    for (final label in ['查看歌词', '播放设备', '播放队列']) {
      expect(find.byTooltip(label).hitTestable(), findsOneWidget);
    }
    expect(
        tester.getTopLeft(find.byTooltip('收藏歌曲')).dy,
        greaterThan(tester
            .getTopLeft(find.byKey(const ValueKey('mobile-player-artwork')))
            .dy));
  });

  testWidgets(
      'reference lyric page hides transport and closes through cover thumbnail',
      (tester) async {
    await _pumpPlayer(tester);
    await tester.tap(find.byTooltip('查看歌词'));
    await tester.pumpAndSettle();
    expect(find.byType(GProgressBar).hitTestable(), findsNothing);
    expect(find.byTooltip('播放队列').hitTestable(), findsNothing);
    expect(find.byKey(const ValueKey('lyric-cover-return')).hitTestable(),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('lyric-cover-return')));
    await tester.pumpAndSettle();
    expect(find.byType(GProgressBar).hitTestable(), findsOneWidget);
  });

  testWidgets('cover pull handle and lyric header retain accessible dismissal',
      (tester) async {
    await _pumpPlayer(tester);
    expect(find.byTooltip('收起播放器').hitTestable(), findsOneWidget);
    expect(tester.getCenter(find.byTooltip('收起播放器')).dx, 195);
    await tester.tap(find.byTooltip('查看歌词'));
    await tester.pumpAndSettle();
    final back = tester.getRect(find.byTooltip('返回封面'));
    final thumbnail = tester.getRect(find.byTooltip('通过封面返回'));
    expect(thumbnail.center.dy, back.center.dy);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reference sleep dialog supports short presets and end of track',
      (tester) async {
    await _pumpPlayer(tester);
    await _openPlaybackSettings(tester);
    await tester.tap(find.text('睡眠定时'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    for (final label in [
      '5 分钟后暂停',
      '15 分钟后暂停',
      '30 分钟后暂停',
      '45 分钟后暂停',
      '60 分钟后暂停',
      '本曲结束后暂停',
      '自定义'
    ]) {
      expect(find.text(label).hitTestable(), findsOneWidget);
    }
  });

  testWidgets('reference custom sleep time validates input and starts timer',
      (tester) async {
    final harness = await _pumpPlayer(tester);
    await _openPlaybackSettings(tester);
    await tester.tap(find.text('睡眠定时'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '0');
    await tester.tap(find.text('开始计时'));
    await tester.pumpAndSettle();
    expect(find.text('请输入 1–1440 分钟'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '23');
    await tester.tap(find.text('开始计时'));
    await tester.pumpAndSettle();
    expect(harness.timer.remaining, const Duration(minutes: 23));
    harness.timer.stop();
    expect(tester.takeException(), isNull);
  });

  testWidgets('reference spectrum opens and returns without changing playback',
      (tester) async {
    final harness = await _pumpPlayer(tester);
    await _openPlaybackSettings(tester);
    await tester.tap(find.text('频谱视图'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('返回播放器'), findsOneWidget);
    expect(harness.player.playing, isFalse);
    await tester.tap(find.byTooltip('返回播放器'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('更多'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('spectrum lyrics follow playback and backward seeks',
      (tester) async {
    final harness = await _pumpPlayer(tester, themeId: 'light');
    await _openPlaybackSettings(tester);
    await tester.tap(find.text('频谱视图'));
    await tester.pumpAndSettle();
    final spectrum = find.byType(SpectrumPlayerView);
    Finder lyric(String text) =>
        find.descendant(of: spectrum, matching: find.text(text));
    expect(lyric('Lyric line 6'), findsOneWidget);
    expect(lyric('Test song same-id'), findsNothing);
    await harness.player.seek(const Duration(seconds: 85));
    await tester.pumpAndSettle();
    expect(lyric('Lyric line 8'), findsOneWidget);
    expect(lyric('Lyric line 6'), findsNothing);
    await harness.player.seek(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(lyric('Lyric line 1'), findsOneWidget);
    final progress =
        find.descendant(of: spectrum, matching: find.byType(GProgressBar));
    expect(
        Theme.of(tester.element(progress))
            .colorScheme
            .onPrimary
            .computeLuminance(),
        greaterThan(.7));
    expect(tester.takeException(), isNull);
  });

  testWidgets('spectrum preserves centered word timing after lyrics change',
      (tester) async {
    final harness = await _pumpPlayer(tester);
    await _openPlaybackSettings(tester);
    await tester.tap(find.text('频谱视图'));
    await tester.pumpAndSettle();
    harness.player.lyricOverride =
        '[60000,3000](60000,1500,0)同步(61500,1500,0)歌词\n'
        '[63000,3000](63000,3000,0)下一句';
    harness.player.setPlaying(false);
    await tester.pumpAndSettle();
    final spectrum = find.byType(SpectrumPlayerView);
    final karaoke =
        find.descendant(of: spectrum, matching: find.byType(KaraokeLyricText));
    expect(karaoke, findsOneWidget);
    expect(
        tester.widget<KaraokeLyricText>(karaoke).textAlign, TextAlign.center);
    expect(tester.widget<KaraokeLyricText>(karaoke).line.text, '同步歌词');
    await harness.player.seek(const Duration(seconds: 64));
    await tester.pumpAndSettle();
    expect(tester.widget<KaraokeLyricText>(karaoke).line.text, '下一句');
    expect(tester.takeException(), isNull);
  });

  testWidgets('spectrum long lyrics fit compact landscape with large text',
      (tester) async {
    final harness =
        await _pumpPlayer(tester, size: const Size(812, 375), textScale: 1.5);
    harness.player.lyricOverride =
        '[00:00]这是一句很长很长用于检查换行的歌词这是一句很长很长用于检查换行的歌词\n[01:30]下一句歌词';
    await tester.ensureVisible(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await _openPlaybackSettings(tester);
    await tester.tap(find.text('频谱视图'));
    await tester.pumpAndSettle();
    final spectrum = find.byType(SpectrumPlayerView);
    expect(
        find
            .descendant(of: spectrum, matching: find.byTooltip('播放'))
            .hitTestable(),
        findsOneWidget);
    expect(
        find
            .descendant(of: spectrum, matching: find.byType(GProgressBar))
            .hitTestable(),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Lotus toolbar keeps secondary actions in a reachable menu',
      (tester) async {
    await _pumpPlayer(tester, size: const Size(320, 700));
    expect(find.byTooltip('AirPlay 或蓝牙'), findsNothing);
    expect(find.byTooltip('歌曲百科'), findsNothing);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    for (final label in ['AirPlay 或蓝牙', '歌曲百科', '下载歌曲']) {
      expect(find.text(label).hitTestable(), findsOneWidget);
    }
    await tester.tap(find.text('歌曲百科'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('关闭歌曲信息'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('player song operations keep only the missing download action',
      (tester) async {
    await _pumpPlayer(tester);
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('下载歌曲'));
    await tester.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    expect(
        find.descendant(of: sheet, matching: find.text('下载')), findsOneWidget);
    for (final label in ['播放', '下一首播放', '喜欢', '收藏到歌单']) {
      expect(
          find.descendant(of: sheet, matching: find.text(label)), findsNothing);
    }
  });

  testWidgets('Lotus lyrics gain reading space and system back restores cover',
      (tester) async {
    await _pumpPlayer(tester, route: true);
    await tester.tap(find.bySemanticsLabel('查看歌词'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(PageView)).height, greaterThan(550));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(PlayerView), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-player-artwork')).hitTestable(),
        findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(PlayerView), findsNothing);
  });

  testWidgets(
      'lyrics stay open on blank taps and have an explicit cover action',
      (tester) async {
    await _pumpPlayer(tester);
    await tester.tap(find.bySemanticsLabel('查看歌词'));
    await tester.pumpAndSettle();
    final pages = tester.getRect(find.byType(PageView));
    await tester.tapAt(Offset(pages.left + 8, pages.center.dy));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lyric-title')), findsOneWidget);
    await tester.tap(find.byTooltip('返回封面'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mobile-player-artwork')).hitTestable(),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'tapping a browsed lyric immediately resumes following its timestamp',
      (tester) async {
    final harness = await _pumpPlayer(tester);
    await tester.tap(find.bySemanticsLabel('查看歌词'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -160));
    await tester.pumpAndSettle();
    expect(find.text('回到当前'), findsOneWidget);
    final target = find.text('Lyric line 10');
    await tester.scrollUntilVisible(target, 120,
        scrollable: find.descendant(
            of: find.byType(ListView), matching: find.byType(Scrollable)));
    await Scrollable.ensureVisible(tester.element(target), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(harness.player.soughtTo, const Duration(seconds: 100));
    expect(find.text('回到当前'), findsNothing);
    expect(tester.getCenter(target).dy,
        closeTo(tester.getCenter(find.byType(ListView)).dy, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('long lyrics remain readable and centered with large text',
      (tester) async {
    const longLine =
        'This is a deliberately long lyric line that needs several lines to remain fully readable';
    final harness = await _pumpPlayer(tester, textScale: 2);
    harness.player.lyricOverride =
        '[00:00.00]Intro\n[01:00.00]$longLine\n[02:00.00]Outro';
    harness.player.notifyListeners();
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('查看歌词'));
    await tester.pumpAndSettle();
    final text = find.text(longLine);
    final paragraph = tester.renderObject<RenderParagraph>(text);
    expect(paragraph.didExceedMaxLines, isFalse);
    final textWidget = tester.widget<Text>(text);
    final style = DefaultTextStyle.of(tester.element(text)).style;
    final painter = TextPainter(
      text: TextSpan(text: textWidget.data, style: style),
      textDirection: TextDirection.ltr,
      textScaler: const TextScaler.linear(2),
    )..layout(maxWidth: tester.getSize(text).width);
    expect(
        tester.getSize(text).height, greaterThanOrEqualTo(painter.height - 1));
    painter.dispose();
    expect(tester.getCenter(text).dy,
        closeTo(tester.getCenter(find.byType(ListView)).dy, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('changing lyric appearance preserves word timing and centering',
      (tester) async {
    final harness = await _pumpPlayer(tester, textScale: 1.5);
    harness.player.lyricOverride = '[0,1000](0,1000,0)序曲\n'
        '[60000,10000](60000,5000,0)沿着这条很长很长的路，(65000,5000,0)走到有光的地方\n'
        '[70000,1000](70000,1000,0)下一句';
    harness.player.notifyListeners();
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('查看歌词'));
    await tester.pumpAndSettle();
    await harness.player.seek(const Duration(seconds: 62));
    await tester.pumpAndSettle();
    final position = harness.player.position;
    for (final style in LyricFontStyle.values) {
      await harness.settings.setLyricFontSize(40);
      await harness.settings.setLyricFontStyle(style);
      await tester.pumpAndSettle();
      final text = find.byType(KaraokeLyricText);
      final widget = tester.widget<KaraokeLyricText>(text);
      expect(widget.style.fontSize, 40);
      expect(widget.style.fontWeight, style.weight);
      expect(widget.position, position);
      expect(tester.getCenter(text).dy,
          closeTo(tester.getCenter(find.byType(ListView)).dy, 1));
      expect(tester.takeException(), isNull);
    }
    await harness.settings.resetLyricAppearance();
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<KaraokeLyricText>(find.byType(KaraokeLyricText))
            .style
            .fontSize,
        28);
  });

  testWidgets('desktop lyrics remeasure wrapped rows after font changes',
      (tester) async {
    final harness = await _pumpPlayer(tester,
        desktopLyrics: true, size: const Size(380, 700), textScale: 1.5);
    harness.player.lyricOverride = List.generate(
            10,
            (i) =>
                '[${i ~/ 6}:${(i % 6 * 10).toString().padLeft(2, '0')}.00]长句歌词第$i行，沿着这条路一直走到有光的地方')
        .join('\n');
    harness.player.notifyListeners();
    await tester.pumpAndSettle();
    await harness.settings.setLyricFontSize(40);
    await harness.settings.setLyricFontStyle(LyricFontStyle.soft);
    await tester.pumpAndSettle();
    final active = find.text('长句歌词第6行，沿着这条路一直走到有光的地方');
    expect(active, findsOneWidget);
    expect(tester.widget<Text>(active).style!.fontWeight, FontWeight.w300);
    expect(tester.getCenter(active).dy,
        closeTo(tester.getCenter(find.byType(ListView)).dy, 1));
    await harness.player.seek(const Duration(seconds: 70));
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.text('长句歌词第7行，沿着这条路一直走到有光的地方')).dy,
        closeTo(tester.getCenter(find.byType(ListView)).dy, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('lyrics keep their wrapping when playback advances',
      (tester) async {
    const line = '沿着这条很长很长的路，走到有光的地方';
    final harness = await _pumpPlayer(tester);
    harness.player.lyricOverride =
        '[00:00.00]序曲\n[01:00.00]$line\n[01:10.00]下一句';
    harness.player.notifyListeners();
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('查看歌词'));
    await tester.pumpAndSettle();
    final activeSize = tester.getSize(find.text(line));

    await harness.player.seek(const Duration(seconds: 70));
    await tester.pumpAndSettle();

    expect(tester.getSize(find.text(line)), activeSize,
        reason: 'Highlighting must not change text wrapping or row geometry');
    expect(tester.getCenter(find.text('下一句')).dy,
        closeTo(tester.getCenter(find.byType(ListView)).dy, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('karaoke lyrics render clean text and seek with absolute time',
      (tester) async {
    final harness = await _pumpPlayer(tester);
    harness.player.lyricOverride =
        '[60000,2000](60000,1000,0)晚(61000,1000,0)风\n'
        '[62000,2000](62000,1000,0)明(63000,1000,0)天';
    harness.player.notifyListeners();
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('查看歌词'));
    await tester.pumpAndSettle();
    expect(find.text('晚风'), findsOneWidget);
    await harness.player.seek(const Duration(milliseconds: 60100));
    await tester.pumpAndSettle();
    final before = tester.widget<ShaderMask>(find.byType(ShaderMask));
    await harness.player.seek(const Duration(milliseconds: 60500));
    await tester.pumpAndSettle();
    expect(tester.widget<ShaderMask>(find.byType(ShaderMask)), same(before),
        reason: 'Word progress must not rebuild the lyric list');
    await tester.tap(find.text('明天'));
    await tester.pumpAndSettle();
    expect(harness.player.soughtTo, const Duration(seconds: 62));
    expect(tester.getCenter(find.text('明天')).dy,
        closeTo(tester.getCenter(find.byType(ListView)).dy, 1));
    expect(tester.takeException(), isNull);
  });

  for (final reducedMotion in [false, true]) {
    testWidgets(
        'browsing reveals surrounding lyrics until following resumes reduced=$reducedMotion',
        (tester) async {
      await _pumpPlayer(tester, reducedMotion: reducedMotion);
      await tester.tap(find.bySemanticsLabel('查看歌词'));
      await tester.pumpAndSettle();
      final surroundingLine = find.text('Lyric line 8');
      final filter = find.ancestor(
          of: surroundingLine, matching: find.byType(ImageFiltered));
      expect(filter, findsOneWidget);
      final textStyle = find
          .ancestor(
              of: surroundingLine,
              matching: find.byType(AnimatedDefaultTextStyle))
          .first;
      expect(
          tester.widget<AnimatedDefaultTextStyle>(textStyle).style.color!.a, 0);

      await tester.drag(find.byType(ListView), const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(find.text('回到当前'), findsOneWidget);
      expect(tester.widget<AnimatedDefaultTextStyle>(textStyle).style.color!.a,
          greaterThan(.7),
          reason: 'Browsing lyrics must be legible away from the playing line');

      await tester.tap(find.text('回到当前'));
      await tester.pumpAndSettle();

      expect(
          tester.widget<AnimatedDefaultTextStyle>(textStyle).style.color!.a, 0);
      final currentFilter = find.ancestor(
          of: find.text('Lyric line 6'), matching: find.byType(ImageFiltered));
      expect(tester.widget<ImageFiltered>(currentFilter).enabled, isFalse);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('player transport press feedback follows its circular button',
      (tester) async {
    await _pumpPlayer(tester);
    final play = find.byTooltip('播放');
    final gesture = await tester.startGesture(tester.getCenter(play));
    await tester.pump(const Duration(milliseconds: 180));
    final feedback = tester.widget<AnimatedContainer>(find
        .descendant(of: play, matching: find.byType(AnimatedContainer))
        .first);
    final decoration = feedback.foregroundDecoration! as BoxDecoration;
    final bounds = tester.getRect(play);
    final radius =
        decoration.borderRadius!.resolve(TextDirection.ltr).topLeft.x;
    expect(radius, greaterThanOrEqualTo(bounds.shortestSide / 2));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(find.byTooltip('播放'), findsOneWidget);
  });

  testWidgets('untimed lyrics can scroll without overflowing the player',
      (tester) async {
    final harness = await _pumpPlayer(tester, textScale: 1.5);
    harness.player.lyricOverride =
        List.generate(40, (i) => 'Untimed lyric $i').join('\n');
    harness.player.notifyListeners();
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('查看歌词'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final pages = tester.getRect(find.byType(PageView));
    final lyricsScroll = find
        .descendant(
            of: find.byType(PageView), matching: find.byType(Scrollable))
        .last;
    await tester.dragFrom(pages.center, const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(tester.state<ScrollableState>(lyricsScroll).position.pixels,
        greaterThan(100));
    expect(find.byKey(const ValueKey('lyric-title')), findsOneWidget);
    expect(harness.player.soughtTo, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android player actions retain 48 pixel touch targets',
      (tester) async {
    await _pumpPlayer(tester, size: const Size(320, 700));
    for (final label in ['收藏歌曲', '更多', '查看歌词', '播放队列']) {
      expect(tester.getSize(find.byTooltip(label)).shortestSide,
          greaterThanOrEqualTo(48),
          reason: label);
    }
  });

  testWidgets('top drag follows the finger and returns below the threshold',
      (tester) async {
    await _pumpPlayer(tester, route: true);
    final cover = find.byKey(const ValueKey('mobile-player-artwork'));
    final originalTop = tester.getTopLeft(cover).dy;
    final gesture = await tester.startGesture(
      tester.getCenter(
          find.byKey(const ValueKey('mobile-player-dismiss-region'))),
    );

    await gesture.moveBy(const Offset(0, 24));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 52));
    await tester.pump();
    expect(tester.getTopLeft(cover).dy, greaterThan(originalTop + 40));

    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(PlayerView), findsOneWidget);
    expect(tester.getTopLeft(cover).dy, closeTo(originalTop, 0.5));
    expect(tester.takeException(), isNull);
  });

  for (final surface in ['cover', 'desktop', 'mini']) {
    testWidgets(
        '$surface time labels agree at fractional seconds and unknown duration',
        (tester) async {
      final wide = surface == 'desktop' || surface == 'mini';
      final harness = await _pumpPlayer(tester,
          size: wide ? const Size(1280, 800) : const Size(390, 844),
          platform: wide ? TargetPlatform.macOS : TargetPlatform.android,
          mini: surface == 'mini',
          desktopMini: surface == 'mini');
      if (surface == 'lyrics') {
        await tester.tap(find.bySemanticsLabel('查看歌词'));
        await tester.pumpAndSettle();
      }
      await harness.player.seek(const Duration(milliseconds: 119900));
      await tester.pumpAndSettle();
      expect(find.text(surface == 'mini' ? '1:59' : '01:59'), findsOneWidget);
      expect(find.text(surface == 'mini' ? '-2:01' : '-02:01'), findsOneWidget);
      harness.player.timelineDuration = null;
      harness.player.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('--:--'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '$surface scrubbing previews times and cancellation restores them',
        (tester) async {
      final wide = surface == 'desktop' || surface == 'mini';
      final harness = await _pumpPlayer(tester,
          size: wide ? const Size(1280, 800) : const Size(390, 844),
          platform: wide ? TargetPlatform.macOS : TargetPlatform.android,
          mini: surface == 'mini',
          desktopMini: surface == 'mini');
      if (surface == 'lyrics') {
        await tester.tap(find.bySemanticsLabel('查看歌词'));
        await tester.pumpAndSettle();
      }
      final bar = tester.getRect(find.byType(GProgressBar));
      final gesture = await tester
          .startGesture(Offset(bar.left + bar.width * .25, bar.center.dy));
      await gesture.moveTo(Offset(bar.left + bar.width * .5, bar.center.dy));
      await tester.pump();
      await gesture.moveTo(Offset(bar.left + bar.width * .75, bar.center.dy));
      await tester.pumpAndSettle();
      expect(find.text(surface == 'mini' ? '3:00' : '03:00'), findsOneWidget);
      expect(find.text(surface == 'mini' ? '-1:00' : '-01:00'), findsOneWidget);
      expect(harness.player.soughtTo, isNull);
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(find.text(surface == 'mini' ? '1:00' : '01:00'), findsOneWidget);
      expect(find.text(surface == 'mini' ? '-3:00' : '-03:00'), findsOneWidget);
      expect(harness.player.soughtTo, isNull);
    });
  }

  testWidgets('released progress stays at the target while seek is pending',
      (tester) async {
    final harness = await _pumpPlayer(tester);
    final gate = Completer<void>();
    harness.player.seekGate = gate;
    final bar = tester.getRect(find.byType(GProgressBar));
    await tester.tapAt(Offset(bar.left + bar.width * .75, bar.center.dy));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('03:00'), findsOneWidget);
    expect(find.text('-01:00'), findsOneWidget);
    expect(
        tester
            .getSemantics(find.bySemanticsLabel('播放进度'))
            .getSemanticsData()
            .value,
        '3:00 / 4:00');
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('03:00'), findsOneWidget);
    expect(harness.player.soughtTo, const Duration(minutes: 3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed seek restores live time and leaves progress usable',
      (tester) async {
    final harness = await _pumpPlayer(tester);
    final gate = Completer<void>();
    harness.player.seekGate = gate;
    final bar = tester.getRect(find.byType(GProgressBar));
    await tester.tapAt(Offset(bar.left + bar.width * .75, bar.center.dy));
    await tester.pump();
    gate.completeError(StateError('Native seek failed'));
    await tester.pumpAndSettle();
    expect(find.text('01:00'), findsOneWidget);
    expect(find.text('暂时无法调整播放进度，请重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
    harness.player.seekGate = null;
    await tester.tapAt(Offset(bar.center.dx, bar.center.dy));
    await tester.pumpAndSettle();
    expect(find.text('02:00'), findsOneWidget);
  });

  testWidgets('changing songs clears an old drag preview', (tester) async {
    final harness = await _pumpPlayer(tester);
    final bar = tester.getRect(find.byType(GProgressBar));
    final gesture = await tester.startGesture(bar.center);
    await gesture.moveTo(Offset(bar.left + bar.width * .75, bar.center.dy));
    await tester.pump();
    expect(find.text('03:00'), findsOneWidget);
    harness.player.replaceCurrent(_song(id: 'replacement'));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('01:00'), findsOneWidget);
    expect(harness.player.soughtTo, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a deliberate downward drag dismisses the player route',
      (tester) async {
    await _pumpPlayer(tester, route: true);
    await tester.dragFrom(
      tester.getCenter(
          find.byKey(const ValueKey('mobile-player-dismiss-region'))),
      const Offset(0, 210),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PlayerView), findsNothing);
    expect(find.text('Open player'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rapid queue taps open only one dismissible sheet',
      (tester) async {
    await _pumpPlayer(tester);
    final queue = find.byTooltip('播放队列');
    final queuePoint = tester.getCenter(queue);
    await tester.tap(queue);
    await tester.tapAt(queuePoint);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('关闭播放队列').last);
    await tester.pumpAndSettle();
    expect(find.byType(DraggableScrollableSheet), findsNothing);

    await tester.tap(queue);
    await tester.pumpAndSettle();
    expect(find.byType(DraggableScrollableSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('quality selection does not restart a replacement song',
      (tester) async {
    final harness = await _pumpPlayer(tester);
    await tester.tap(find.byTooltip('切换音质'));
    await tester.pumpAndSettle();

    harness.player.replaceCurrent(_song(source: 'qq'));
    await tester.pump();
    await tester.tap(find.text('标准音质'));
    await tester.pumpAndSettle();

    expect(harness.player.retryCount, 0);
    expect(harness.player.soughtTo, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('canceling mini player volume leaves playback unchanged',
      (tester) async {
    final harness = await _pumpPlayer(
      tester,
      mini: true,
      desktopMini: true,
      size: const Size(1280, 800),
    );
    final volumeGesture = find
        .descendant(
          of: find.byType(MiniPlayer),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is GestureDetector &&
                widget.onHorizontalDragUpdate != null,
          ),
        )
        .last;
    final volume = tester.getRect(volumeGesture);
    expect(volume.height, greaterThanOrEqualTo(44));
    final gesture = await tester.startGesture(
      Offset(volume.left + volume.width * 0.2, volume.center.dy),
    );
    await tester.pump(const Duration(milliseconds: 150));
    await gesture.cancel();
    await tester.pumpAndSettle();

    expect(harness.player.volumeChanges, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(320, 640), const Size(844, 390)]) {
    testWidgets('quality choices fit $size with large text', (tester) async {
      await _pumpPlayer(tester, size: size, textScale: 2);
      await tester.ensureVisible(find.byTooltip('切换音质'));
      await tester.tap(find.byTooltip('切换音质'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Hi-Res'));
      await tester.pumpAndSettle();
      expect(find.text('Hi-Res').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Hi-Res'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Hi-Res'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sleep timer choices fit $size with large text',
        (tester) async {
      final harness = await _pumpPlayer(tester, size: size, textScale: 2);
      await _openPlaybackSettings(tester);
      await tester.tap(find.text('睡眠定时'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('60 分钟后暂停'));
      await tester.pumpAndSettle();
      expect(find.text('60 分钟后暂停').hitTestable(), findsOneWidget);
      await tester.tap(find.text('60 分钟后暂停'));
      await tester.pumpAndSettle();
      expect(find.text('60 分钟后暂停'), findsNothing);
      expect(harness.timer.isActive, isTrue);
      harness.timer.stop();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('lyrics scroll and progress scrubbing keep the player open',
      (tester) async {
    final harness = await _pumpPlayer(tester, route: true);
    await tester.drag(find.byType(PageView), const Offset(-340, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lyric-title')), findsOneWidget);
    final closeTop = tester.getTopLeft(find.byTooltip('返回封面'));

    await tester.drag(find.byType(ListView), const Offset(0, 150));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byTooltip('返回封面')), closeTop);
    expect(find.byType(PlayerView), findsOneWidget);
    expect(harness.player.soughtTo, isNull);

    await tester.tap(find.byTooltip('返回封面'));
    await tester.pumpAndSettle();
    final progress = tester.getRect(find.byType(GProgressBar));
    await tester.dragFrom(
      Offset(progress.left + 20, progress.center.dy),
      Offset(progress.width * 0.55, 0),
    );
    await tester.pumpAndSettle();
    expect(harness.player.soughtTo, isNotNull);
    expect(find.byType(PlayerView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion keeps playing artwork still without a ticker',
      (tester) async {
    await _pumpPlayer(tester, playing: true, reducedMotion: true);
    final artwork = find.byKey(const ValueKey('mobile-player-artwork'));
    final initialBounds = tester.getRect(artwork);
    await tester.pump(const Duration(seconds: 2));

    expect(tester.getRect(artwork), initialBounds);
    expect(tester.binding.transientCallbackCount, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('paused queue equalizer does not keep animating', (tester) async {
    final harness = await _pumpPlayer(tester, playing: true);
    await tester.tap(find.byTooltip('播放队列'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final equalizer = _equalizerAnimation(tester);
    expect(equalizer.isAnimating, isTrue);

    harness.player.setPlaying(false);
    await tester.pump();

    expect(equalizer.isAnimating, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('queue equalizer stops when reduced motion is enabled',
      (tester) async {
    await _pumpPlayer(tester, playing: true, reducedMotion: true);
    await tester.tap(find.byTooltip('播放队列'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(_equalizerAnimation(tester).isAnimating, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same song id from another source resets the lyrics page',
      (tester) async {
    final harness = await _pumpPlayer(tester);
    await tester.drag(find.byType(PageView), const Offset(-340, 0));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('lyric-title')), findsOneWidget);

    harness.player.replaceCurrent(_song(source: 'qq'));
    await tester.pumpAndSettle();

    final page = tester.widget<PageView>(find.byType(PageView));
    expect(page.controller!.page, 0);
    expect(find.byTooltip('收起播放器'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a late favorite response cannot like the replacement song',
      (tester) async {
    final mutation = Completer<http.Response>();
    var favoriteLoads = 0;
    String? submittedSource;
    _handleRequest = (request) async {
      if (request.method == 'POST') {
        submittedSource = (jsonDecode(request.body) as Map)['source'] as String;
        return mutation.future;
      }
      favoriteLoads++;
      return _response(const {'items': []});
    };
    final harness = await _pumpPlayer(tester, loggedIn: true);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.favorite_outline_rounded));
    await tester.pump();
    expect(submittedSource, 'netease');

    harness.player.replaceCurrent(_song(source: 'qq'));
    await tester.pump();
    mutation.complete(_response(const {}));
    await tester.pumpAndSettle();

    expect(harness.player.current.source, 'qq');
    expect(harness.player.liked, isFalse);
    expect(find.byIcon(Icons.favorite_outline_rounded), findsOneWidget);
    expect(favoriteLoads, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lyrics follow the current line again after scrolling stops',
      (tester) async {
    await _pumpPlayer(tester);
    await tester.drag(find.byType(PageView), const Offset(-340, 0));
    await tester.pumpAndSettle();
    final list = tester.widget<ListView>(find.byType(ListView));
    final initialOffset = list.controller!.offset;

    await tester.drag(find.byType(ListView), const Offset(0, -170));
    await tester.pumpAndSettle();
    expect(list.controller!.offset, greaterThan(initialOffset + 100));
    expect(find.text('回到当前'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(list.controller!.offset, closeTo(initialOffset, 0.5));
    expect(find.text('回到当前'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('return to current realigns lyrics even within the same line',
      (tester) async {
    await _pumpPlayer(tester);
    await tester.drag(find.byType(PageView), const Offset(-340, 0));
    await tester.pumpAndSettle();
    final list = tester.widget<ListView>(find.byType(ListView));
    final initialOffset = list.controller!.offset;

    await tester.drag(find.byType(ListView), const Offset(0, -150));
    await tester.pumpAndSettle();
    await tester.tap(find.text('回到当前'));
    await tester.pumpAndSettle();

    expect(list.controller!.offset, closeTo(initialOffset, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('queue sheet expands before scrolling the queue independently',
      (tester) async {
    await _pumpPlayer(tester, queueLength: 30);
    await tester.tap(find.byTooltip('播放队列'));
    await tester.pumpAndSettle();
    final sheetFinder = find.byType(DraggableScrollableSheet);
    expect(sheetFinder, findsOneWidget);
    final initialHeight = tester.getSize(sheetFinder).height;
    final scroll = find.descendant(
      of: sheetFinder,
      matching: find.byType(Scrollable),
    );

    await tester.drag(scroll, const Offset(0, -220));
    await tester.pumpAndSettle();
    expect(tester.getSize(sheetFinder).height, greaterThan(initialHeight));
    await tester.drag(scroll, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(
        tester.state<ScrollableState>(scroll).position.pixels, greaterThan(0));
    expect(find.byTooltip('关闭播放队列'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final queueLength in [0, 1]) {
    testWidgets('queue with $queueLength tracks still expands and dismisses',
        (tester) async {
      await _pumpPlayer(tester, queueLength: queueLength);
      await tester.tap(find.byTooltip('播放队列'));
      await tester.pumpAndSettle();
      final sheet = find.byType(DraggableScrollableSheet);
      final initialHeight = tester.getSize(sheet).height;
      final scroll = find.descendant(
        of: sheet,
        matching: find.byType(Scrollable),
      );

      await tester.drag(scroll, const Offset(0, -220));
      await tester.pumpAndSettle();
      expect(tester.getSize(sheet).height, greaterThan(initialHeight));

      await tester.drag(scroll, const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('320 wide mini player fits large text and Android touch targets',
      (tester) async {
    await _pumpPlayer(
      tester,
      mini: true,
      size: const Size(320, 700),
      textScale: 2,
    );

    final bar = tester.getRect(find.byType(MiniPlayer));
    expect(find.byTooltip('上一首'), findsNothing);
    for (final label in ['播放', '下一首']) {
      final button = tester.getRect(find.byTooltip(label));
      expect(button.shortestSide, greaterThanOrEqualTo(48));
      expect(button.left, greaterThanOrEqualTo(0));
      expect(button.right, lessThanOrEqualTo(320));
    }
    final title = tester.getRect(find.textContaining('Test song same-id'));
    final artwork = tester.getRect(
      find.byKey(const ValueKey('mobile-mini-player-artwork')),
    );
    expect(title.width, greaterThanOrEqualTo(90));
    expect(artwork.width, artwork.height);
    expect(bar.contains(artwork.topLeft), isTrue);
    expect(bar.contains(artwork.bottomRight), isTrue);
    expect(bar.contains(title.topLeft), isTrue);
    expect(bar.contains(title.bottomRight), isTrue);
    expect(title.left, greaterThanOrEqualTo(artwork.right));
    expect(title.right,
        lessThanOrEqualTo(tester.getRect(find.byTooltip('播放')).left));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'narrow mini player keeps play and next targets on both platforms',
      (tester) async {
    for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
      await _pumpPlayer(
        tester,
        mini: true,
        size: const Size(280, 700),
        textScale: 2,
        platform: platform,
      );

      expect(find.byTooltip('上一首'), findsNothing);
      final minimumTarget = platform == TargetPlatform.android ? 48 : 44;
      for (final label in ['播放', '下一首']) {
        expect(
          tester.getSize(find.byTooltip(label)).shortestSide,
          greaterThanOrEqualTo(minimumTarget),
        );
      }
      expect(
        tester.getSize(find.textContaining('Test song same-id')).width,
        greaterThanOrEqualTo(32),
      );
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'mini player keeps controls in place during track and state changes',
      (tester) async {
    final harness = await _pumpPlayer(tester, mini: true);
    final size = tester.getSize(find.byType(MiniPlayer));
    final nextPosition = tester.getCenter(find.byTooltip('下一首'));
    harness.player
        .replaceCurrent(_song(source: 'qq', name: 'A much longer title'));
    harness.player.setPlaying(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    expect(tester.getSize(find.byType(MiniPlayer)), size);
    expect(tester.getCenter(find.byTooltip('下一首')), nextPosition);
    await tester.pumpAndSettle();
    expect(find.byIcon(cupertino.CupertinoIcons.pause_fill), findsOneWidget);
    expect(find.byTooltip('暂停'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mini player keeps playback failures visible and retries',
      (tester) async {
    final harness = await _pumpPlayer(tester, mini: true);
    harness.player.playbackError = '无法获取播放地址';
    harness.player.setPlaying(false);
    await tester.pumpAndSettle();
    expect(find.text('无法获取播放地址'), findsOneWidget);
    expect(find.text('Test artist'), findsOneWidget);
    expect(find.byTooltip('重试'), findsOneWidget);
    await tester.tap(find.byTooltip('重试'));
    await tester.pumpAndSettle();
    expect(harness.player.retryCount, 1);
    expect(find.byType(PlayerView), findsNothing);
  });

  testWidgets('mini player opens the full player and its playback queue',
      (tester) async {
    await _pumpPlayer(tester, mini: true, reducedMotion: true);
    await tester.tap(find.byKey(const ValueKey('mobile-mini-player-artwork')));
    await tester.pumpAndSettle();

    expect(find.byType(PlayerView), findsOneWidget);
    await tester.tap(find.byTooltip('播放队列'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('关闭播放队列'), findsOneWidget);
    await tester.tap(find.byTooltip('关闭播放队列'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('收起播放器'));
    await tester.pumpAndSettle();
    expect(find.byType(PlayerView), findsNothing);
    expect(find.byType(MiniPlayer), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _openPlaybackSettings(WidgetTester tester) async {
  await tester.ensureVisible(find.byTooltip('更多'));
  await tester.tap(find.byTooltip('更多'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('播放设置'));
  await tester.pumpAndSettle();
}

AnimationController _equalizerAnimation(WidgetTester tester) {
  return tester
      .widgetList<AnimatedBuilder>(find.byType(AnimatedBuilder))
      .map((widget) => widget.animation)
      .whereType<AnimationController>()
      .singleWhere(
        (controller) =>
            controller.duration == const Duration(milliseconds: 800),
      );
}

http.Response _response(Map<String, dynamic> data) => http.Response(
      jsonEncode({'code': 0, 'data': data}),
      200,
      headers: const {'content-type': 'application/json'},
    );

Future<_PlayerHarness> _pumpPlayer(
  WidgetTester tester, {
  bool route = false,
  bool playing = false,
  bool reducedMotion = false,
  bool loggedIn = false,
  bool mini = false,
  bool desktopMini = false,
  bool desktopLyrics = false,
  int queueLength = 1,
  Size size = const Size(390, 844),
  double textScale = 1,
  String themeId = 'dark',
  TargetPlatform platform = TargetPlatform.android,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final settings = SettingsController();
  final player = _InteractionPlayer(settings, queueLength: queueLength)
    ..setPlaying(playing);
  final auth = _InteractionAuth(loggedIn);
  final timer = SleepTimer();
  addTearDown(settings.dispose);
  addTearDown(player.dispose);
  addTearDown(auth.dispose);
  addTearDown(timer.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<PlayerController>.value(value: player),
        ChangeNotifierProvider<SettingsController>.value(value: settings),
        ChangeNotifierProvider<AuthController>.value(value: auth),
        ChangeNotifierProvider<SleepTimer>.value(value: timer),
      ],
      child: MaterialApp(
        theme: AppTheme.byId(themeId).data.copyWith(platform: platform),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            padding: const EdgeInsets.only(top: 24, bottom: 24),
            disableAnimations: reducedMotion,
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: desktopLyrics
            ? Scaffold(
                body: DesktopPlayerPanel(
                    panel: MiniPlayerPanel.lyrics, onClose: () {}))
            : mini
                ? Scaffold(
                    body: Align(
                      child: MiniPlayer(sidebarWidth: desktopMini ? 264 : null),
                    ),
                  )
                : route
                    ? Builder(
                        builder: (context) => Scaffold(
                          body: Center(
                            child: TextButton(
                              onPressed: () => Navigator.of(context).push(
                                buildPlayerRoute(reducedMotion: reducedMotion),
                              ),
                              child: const Text('Open player'),
                            ),
                          ),
                        ),
                      )
                    : const PlayerView(),
      ),
    ),
  );
  if (route) {
    await tester.tap(find.text('Open player'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }
  await tester.pump();
  return _PlayerHarness(player, timer, settings);
}

class _PlayerHarness {
  const _PlayerHarness(this.player, this.timer, this.settings);

  final _InteractionPlayer player;
  final SleepTimer timer;
  final SettingsController settings;
}

class _InteractionAuth extends AuthController {
  _InteractionAuth(this.loggedIn);

  final bool loggedIn;

  @override
  String? get token => loggedIn ? 'interaction-token' : null;
}

class _InteractionPlayer extends PlayerController {
  _InteractionPlayer(SettingsController settings, {required int queueLength})
      : _queue = List.generate(queueLength, (index) => _song(id: '$index')),
        super(settings: settings);

  final List<Song> _queue;
  Song _current = _song();
  bool _playing = false;
  Duration _position = const Duration(seconds: 60);
  final _positions = StreamController<Duration>.broadcast();
  String? lyricOverride;
  String? playbackError;

  @override
  String? get error => playbackError;
  Duration? timelineDuration = const Duration(minutes: 4);
  Duration? soughtTo;
  Completer<void>? seekGate;
  int retryCount = 0;
  final volumeChanges = <double>[];

  @override
  Song get current => _current;

  @override
  List<Song> get queue => _queue;

  @override
  int get queueIndex => 0;

  @override
  bool get loading => false;

  @override
  bool get playing => _playing;

  @override
  Duration get position => _position;

  @override
  Stream<Duration> get positionStream => _positions.stream;

  @override
  Duration? get duration => timelineDuration;

  @override
  String get lyric =>
      lyricOverride ??
      List.generate(
        24,
        (index) => '[${(index ~/ 6).toString().padLeft(2, '0')}:'
            '${(index % 6 * 10).toString().padLeft(2, '0')}.00]Lyric line $index',
      ).join('\n');

  void replaceCurrent(Song song) {
    _current = song;
    notifyListeners();
  }

  void setPlaying(bool value) {
    _playing = value;
    notifyListeners();
  }

  @override
  Future<void> seek(Duration position) async {
    soughtTo = position;
    await seekGate?.future;
    _position = position;
    _positions.add(position);
  }

  @override
  void dispose() {
    _positions.close();
    super.dispose();
  }

  @override
  Future<void> retry() async {
    retryCount++;
  }

  @override
  Future<void> pause() async => setPlaying(false);

  @override
  Future<void> setVolume(double value) async {
    volumeChanges.add(value);
  }
}

Song _song({String id = 'same-id', String source = 'netease', String? name}) =>
    Song(
      id: id,
      name: name ?? 'Test song $id',
      source: source,
      artists: const [Artist(id: 1, name: 'Test artist')],
      album: const Album(id: 1, name: 'Test album'),
      durationMs: 240000,
    );
