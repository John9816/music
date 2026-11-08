import 'package:duck_music/core/settings/lyric_appearance.dart';
import 'package:duck_music/core/settings/settings_controller.dart';
import 'package:duck_music/core/theme/app_theme.dart';
import 'package:duck_music/features/player/karaoke_lyric_text.dart';
import 'package:duck_music/features/settings/lyric_settings_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(const {}));

  test('existing users retain bold lyrics and appearance survives restart',
      () async {
    final settings = SettingsController();
    addTearDown(settings.dispose);
    await settings.load();
    expect(settings.lyricFontSize, 28);
    expect(settings.lyricFontStyle, LyricFontStyle.bold);
    await settings.setLyricFontSize(36);
    await settings.setLyricFontStyle(LyricFontStyle.soft);
    final restored = SettingsController();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.lyricFontSize, 36);
    expect(restored.lyricFontStyle, LyricFontStyle.soft);
  });

  test('size stays within readable bounds on write and load', () async {
    final settings = SettingsController();
    addTearDown(settings.dispose);
    await settings.setLyricFontSize(-10);
    expect(settings.lyricFontSize, 20);
    await settings.setLyricFontSize(200);
    expect(settings.lyricFontSize, 40);
    SharedPreferences.setMockInitialValues(const {
      'lyric_font_size': 999,
      'lyric_font_style': 'unavailable-font',
      'reduce_motion': true,
    });
    await settings.load();
    expect(settings.lyricFontSize, 40);
    expect(settings.lyricFontStyle, LyricFontStyle.bold);
    expect(settings.reduceMotion, isTrue);
  });

  test('malformed appearance does not prevent other settings from loading',
      () async {
    SharedPreferences.setMockInitialValues(const {
      'lyric_font_size': 'large',
      'lyric_font_style': 5,
      'reduce_motion': true,
    });
    final settings = SettingsController();
    addTearDown(settings.dispose);
    await settings.load();
    expect(settings.lyricFontSize, 28);
    expect(settings.lyricFontStyle, LyricFontStyle.bold);
    expect(settings.reduceMotion, isTrue);
  });

  test('reset restores only lyric appearance and persists both values',
      () async {
    final settings = SettingsController();
    addTearDown(settings.dispose);
    await settings.setLyricFontSize(40);
    await settings.setLyricFontStyle(LyricFontStyle.standard);
    await settings.setReduceMotion(true);
    await settings.resetLyricAppearance();
    final restored = SettingsController();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.lyricFontSize, 28);
    expect(restored.lyricFontStyle, LyricFontStyle.bold);
    expect(restored.reduceMotion, isTrue);
  });

  test('a quick selection after reset remains the persisted selection',
      () async {
    final settings = SettingsController();
    addTearDown(settings.dispose);
    await settings.setLyricFontStyle(LyricFontStyle.standard);
    final reset = settings.resetLyricAppearance();
    final selection = settings.setLyricFontStyle(LyricFontStyle.soft);
    await Future.wait([reset, selection]);
    final restored = SettingsController();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.lyricFontStyle, settings.lyricFontStyle);
  });

  testWidgets('size and style controls update the word preview and persist',
      (tester) async {
    final settings = await _pump(tester);
    final slider = find.byType(Slider);
    await tester.drag(slider, const Offset(100, 0));
    await tester.pumpAndSettle();
    expect(settings.lyricFontSize, greaterThan(28));
    await tester.ensureVisible(find.text('柔和'));
    await tester.tap(find.text('柔和'));
    await tester.pumpAndSettle();
    final preview =
        tester.widget<KaraokeLyricText>(find.byType(KaraokeLyricText));
    expect(preview.style.fontSize, settings.lyricFontSize);
    expect(preview.style.fontWeight, FontWeight.w300);
    expect(preview.style.decoration, isNot(TextDecoration.underline));
    final restored = SettingsController();
    addTearDown(restored.dispose);
    await restored.load();
    expect(restored.lyricFontSize, settings.lyricFontSize);
    expect(restored.lyricFontStyle, LyricFontStyle.soft);
    await tester.ensureVisible(find.text('恢复默认'));
    await tester.tap(find.text('恢复默认'));
    await tester.pumpAndSettle();
    expect(settings.lyricFontSize, 28);
    expect(settings.lyricFontStyle, LyricFontStyle.bold);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the size slider stays under the finger while preview changes',
      (tester) async {
    final settings = await _pump(tester);
    final initial = tester.getCenter(find.byType(Slider));
    for (final size in [20, 40, 28]) {
      await settings.setLyricFontSize(size);
      await settings.setLyricFontStyle(LyricFontStyle.soft);
      await tester.pumpAndSettle();
      expect(tester.getCenter(find.byType(Slider)), initial);
    }
  });

  for (final size in [const Size(320, 700), const Size(812, 375)]) {
    testWidgets('appearance controls remain usable at $size with large text',
        (tester) async {
      final settings = await _pump(tester, size: size, scale: 2);
      await settings.setLyricFontSize(40);
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('柔和'), 180);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('柔和'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('柔和'));
      await tester.pumpAndSettle();
      expect(settings.lyricFontStyle, LyricFontStyle.soft);
      await tester.scrollUntilVisible(find.text('恢复默认'), 160);
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复默认'));
      await tester.pumpAndSettle();
      expect(settings.lyricFontSize, 28);
      expect(tester.takeException(), isNull);
    });
  }
}

Future<SettingsController> _pump(WidgetTester tester,
    {Size size = const Size(390, 844), double scale = 1}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final settings = SettingsController();
  addTearDown(settings.dispose);
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: settings,
    child: MaterialApp(
      theme: AppTheme.byId('dark').data,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: const LyricSettingsView(),
    ),
  ));
  await tester.pumpAndSettle();
  return settings;
}
