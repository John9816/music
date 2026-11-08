import 'package:duck_music/core/theme/app_theme.dart';
import 'package:duck_music/widgets/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('touch seeking hides the keyboard focus outline', (tester) async {
    final strategy = FocusManager.instance.highlightStrategy;
    addTearDown(() => FocusManager.instance.highlightStrategy = strategy);
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
    await tester.pumpWidget(_app(SizedBox(
      width: 200,
      child: GProgressBar(
        position: const Duration(seconds: 20),
        duration: const Duration(seconds: 100),
        onSeek: (_) {},
      ),
    )));
    final bar = find.byType(GProgressBar);
    await tester.tap(bar);
    await tester.pumpAndSettle();
    Border? outline() => (tester
            .widget<DecoratedBox>(find
                .descendant(of: bar, matching: find.byType(DecoratedBox))
                .first)
            .decoration as BoxDecoration)
        .border as Border?;
    expect(outline(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(outline(), isNotNull);
    await tester.tap(bar);
    await tester.pumpAndSettle();
    expect(outline(), isNull);
  });

  testWidgets(
      'a quick tap remains visible then releases without a second action',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(_app(GButton(label: 'Play', onTap: () => calls++)));
    await tester.tap(find.byType(GButton));
    await tester.pump();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
        lessThan(1));
    expect(calls, 1);
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    expect(calls, 1);
  });

  testWidgets('canceling a press restores its appearance without activation',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(_app(GButton(label: 'Play', onTap: () => calls++)));
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(GButton)));
    await tester.pump(const Duration(milliseconds: 150));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
  });

  testWidgets('disabled controls are visually distinct and cannot activate',
      (tester) async {
    var calls = 0;
    await tester
        .pumpWidget(_app(Column(mainAxisSize: MainAxisSize.min, children: [
      GButton(label: 'Enabled', onTap: () => calls++),
      const GButton(label: 'Disabled'),
      GIconButton(icon: Icons.add, onTap: () => calls++),
      const GIconButton(icon: Icons.remove),
    ])));
    final enabled = tester.widget<Text>(find.text('Enabled')).style!.color;
    final disabled = tester.widget<Text>(find.text('Disabled')).style!.color;
    expect(disabled, isNot(enabled));
    expect(tester.widget<Icon>(find.byIcon(Icons.add)).color,
        isNot(tester.widget<Icon>(find.byIcon(Icons.remove)).color));
    await tester.tap(find.text('Disabled'));
    await tester.tap(find.byIcon(Icons.remove));
    expect(calls, 0);
  });

  testWidgets('page header actions wrap on narrow screens with large text',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(_app(
        GPageHeader(title: 'My music', actions: [
          GButton(label: 'Create playlist', onTap: () {}),
          GButton(label: 'Import playlist', onTap: () {}),
        ]),
        scale: 2));
    expect(tester.takeException(), isNull);
    for (final label in ['Create playlist', 'Import playlist']) {
      expect(tester.getRect(find.text(label)).right, lessThanOrEqualTo(300));
    }
  });

  testWidgets('loading preserves button geometry and prevents duplicate taps',
      (tester) async {
    var calls = 0;
    var loading = false;
    late StateSetter update;
    await tester.pumpWidget(_app(
      StatefulBuilder(builder: (context, setState) {
        update = setState;
        return Row(mainAxisSize: MainAxisSize.min, children: [
          GButton(
            label: 'Add to playlist',
            icon: Icons.playlist_add,
            loading: loading,
            onTap: () => calls++,
          ),
        ]);
      }),
    ));
    final before = tester.getSize(find.byType(GButton));
    await tester.tap(find.byType(GButton));
    expect(calls, 1);
    update(() => loading = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.getSize(find.byType(GButton)), before);
    await tester.tap(find.byType(GButton));
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Android controls have usable touch targets and semantic actions',
      (tester) async {
    final semantics = tester.ensureSemantics();
    var calls = 0;
    await tester
        .pumpWidget(_app(Column(mainAxisSize: MainAxisSize.min, children: [
      GIconButton(
        icon: Icons.favorite_border,
        size: 18,
        padding: 4,
        tooltip: 'Favorite',
        onTap: () => calls++,
      ),
      GButton(label: 'Play', small: true, onTap: () => calls++),
    ])));
    expect(tester.getSize(find.byType(GIconButton)).shortestSide,
        greaterThanOrEqualTo(48));
    expect(
        tester.getSize(find.byType(GButton)).height, greaterThanOrEqualTo(48));
    final node = tester.getSemantics(find.bySemanticsLabel('Favorite'));
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    node.owner!.performAction(node.id, SemanticsAction.tap);
    expect(calls, 1);
    semantics.dispose();
  });

  testWidgets('section headers and buttons fit narrow large-text layouts',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 720);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(_app(
      Column(mainAxisSize: MainAxisSize.min, children: [
        SectionHeader(
          'Daily recommendations',
          subtitle: 'Selected from your favorite artists',
          action: GIconButton(icon: Icons.refresh, onTap: () {}),
        ),
        SizedBox(
          width: 220,
          child: GButton(
            label: 'Add all songs to the playback queue',
            icon: Icons.playlist_add,
            onTap: () {},
          ),
        ),
      ]),
      scale: 2,
    ));
    expect(tester.takeException(), isNull);
  });

  testWidgets('enabling reduced motion reveals a pending list item immediately',
      (tester) async {
    var reduced = false;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(
      home: StatefulBuilder(builder: (context, setState) {
        update = setState;
        return MediaQuery(
          data: MediaQueryData(disableAnimations: reduced),
          child: const GListEntrance(index: 8, child: Text('Track')),
        );
      }),
    ));
    update(() => reduced = true);
    await tester.pump();
    final fade = tester.widget<FadeTransition>(find.descendant(
      of: find.byType(GListEntrance),
      matching: find.byType(FadeTransition),
    ));
    expect(fade.opacity.value, 1);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });
}

Widget _app(Widget child, {double scale = 1}) => MaterialApp(
      theme: AppTheme.forAccent('forestGreen', dark: false)
          .data
          .copyWith(platform: TargetPlatform.android),
      home: Builder(builder: (context) {
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: Center(child: child)),
        );
      }),
    );
