import 'dart:async';
import 'dart:ui' as ui;

import 'package:duck_music/core/player/lrc_parser.dart';
import 'package:duck_music/features/player/karaoke_lyric_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('short centered lyric highlight stays over the centered text',
      (tester) async {
    const key = ValueKey('centered-capture');
    final line = parseLrc('[100000,2000](100000,2000,0)AAA').single;
    await tester.pumpWidget(MaterialApp(
        home: Center(
            child: RepaintBoundary(
                key: key,
                child: ColoredBox(
                    color: Colors.black,
                    child: SizedBox(
                        width: 300,
                        child: KaraokeLyricText(
                            line: line,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 24),
                            position: const Duration(seconds: 103),
                            positionStream: const Stream.empty(),
                            playing: false,
                            textAlign: TextAlign.center)))))));
    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
    final bounds = await tester.runAsync(() async {
      final image = await boundary.toImage();
      final bytes =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      var left = image.width;
      var right = -1;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final offset = (y * image.width + x) * 4;
          if (bytes.getUint8(offset) > 230) {
            if (x < left) left = x;
            if (x > right) right = x;
          }
        }
      }
      image.dispose();
      return (left, right);
    });
    expect(bounds!.$1, greaterThan(100));
    expect(bounds.$2, lessThan(200));
    expect(bounds.$2, greaterThan(bounds.$1));
  });

  for (final reducedMotion in [false, true]) {
    testWidgets(
        'playing highlight stops at the last native time reduced=$reducedMotion',
        (tester) async {
      final positions = StreamController<Duration>.broadcast();
      addTearDown(positions.close);
      final line = parseLrc('[100000,2000](100000,2000,0)AAAA').single;
      const key = ValueKey('capture');
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reducedMotion),
          child: Center(
              child: RepaintBoundary(
                  key: key,
                  child: ColoredBox(
                    color: Colors.black,
                    child: SizedBox(
                        width: 140,
                        child: KaraokeLyricText(
                          line: line,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 24),
                          position: const Duration(seconds: 100),
                          positionStream: positions.stream,
                          playing: true,
                        )),
                  ))),
        ),
      ));
      final initial = await _whitePixels(tester, key);
      positions.add(const Duration(milliseconds: 100200));
      await tester.pumpAndSettle();
      final highlighted = await _whitePixels(tester, key);
      expect(highlighted, greaterThan(initial));
      await tester.pump(const Duration(seconds: 3));
      expect(await _whitePixels(tester, key), highlighted);
      positions.add(const Duration(milliseconds: 100300));
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
      'word highlight follows time, freezes paused, and seeks backwards',
      (tester) async {
    final positions = StreamController<Duration>.broadcast();
    addTearDown(positions.close);
    final line =
        parseLrc('[100000,2000](100000,1000,0)AAA (101000,1000,0)BBB').single;
    const key = ValueKey('capture');
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: RepaintBoundary(
          key: key,
          child: ColoredBox(
            color: Colors.black,
            child: SizedBox(
              width: 140,
              child: KaraokeLyricText(
                line: line,
                style: const TextStyle(color: Colors.white, fontSize: 24),
                position: const Duration(seconds: 99),
                positionStream: positions.stream,
                playing: false,
              ),
            ),
          ),
        ),
      ),
    ));
    final before = await _whitePixels(tester, key);
    final size = tester.getSize(find.text('AAA BBB'));
    positions.add(const Duration(milliseconds: 100500));
    await tester.pumpAndSettle();
    final partial = await _whitePixels(tester, key);
    expect(partial, greaterThan(before + 50));
    await tester.pump(const Duration(seconds: 2));
    expect(await _whitePixels(tester, key), partial,
        reason: 'Paused lyrics cannot advance on wall-clock time');
    positions.add(const Duration(seconds: 103));
    await tester.pumpAndSettle();
    expect(await _whitePixels(tester, key), greaterThan(partial + 50));
    expect(tester.getSize(find.text('AAA BBB')), size);
    positions.add(const Duration(seconds: 99));
    await tester.pumpAndSettle();
    expect(await _whitePixels(tester, key), before);
    expect(tester.takeException(), isNull);
  });
}

Future<int> _whitePixels(WidgetTester tester, Key key) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    var count = 0;
    for (var i = 0; i < bytes!.lengthInBytes; i += 4) {
      if (bytes.getUint8(i) > 230 && bytes.getUint8(i + 1) > 230) count++;
    }
    image.dispose();
    return count;
  }))!;
}
