import 'package:duck_music/core/theme/app_theme.dart';
import 'package:duck_music/widgets/glass.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('glass controls use the active color scheme roles',
      (tester) async {
    final base = AppTheme.forAccent('skyBlue', dark: true).scheme;
    final scheme = base.copyWith(onPrimary: const Color(0xFF101820));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: scheme, useMaterial3: true),
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: Column(
              children: [
                GButton(
                  label: '播放',
                  icon: Icons.play_arrow_rounded,
                  onTap: () {},
                ),
                GChoiceChip(label: '推荐', selected: true, onTap: () {}),
                GSegmented(
                  items: const ['歌曲', '歌单'],
                  selected: 0,
                  onSelected: (_) {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final label = tester.widget<Text>(find.text('播放'));
    expect(label.style?.color, scheme.onPrimary);

    final buttonIcon = tester.widget<Icon>(
      find.byIcon(Icons.play_arrow_rounded).first,
    );
    expect(buttonIcon.color, scheme.onPrimary);

    final choiceLabel = tester.widget<Text>(find.text('推荐'));
    expect(choiceLabel.style?.color, scheme.onPrimary);

    // GSegmented uses a Container (not AnimatedContainer) for the sliding indicator
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.decoration is BoxDecoration &&
            (widget.decoration as BoxDecoration).color ==
                scheme.surfaceContainerHigh,
      ),
      findsOneWidget,
    );
  });
}
