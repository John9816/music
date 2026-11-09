import 'package:duck_music/core/player/equalizer_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Target implements EqualizerTarget {
  bool enabled = false;
  List<double> gains = [];
  @override
  Future<EqualizerBands> parameters() async => const EqualizerBands(
      frequencies: [60, 230, 910, 3600, 14000], minDb: -15, maxDb: 15);
  @override
  Future<void> apply(bool value, List<double> db) async {
    enabled = value;
    gains = List.of(db);
  }
}

void main() {
  test('Android millibel transport maps to real decibels', () {
    expect(AndroidEqualizerTarget.fromNativeGain(1.5), 15);
    expect(AndroidEqualizerTarget.fromNativeGain(-1.5), -15);
    expect(AndroidEqualizerTarget.toNativeGain(-6), -.6);
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('presets reach real effect adapter with headroom and restore on restart',
      () async {
    final target = _Target();
    final eq = EqualizerController(target: target);
    await eq.initialize();
    await eq.selectPreset('bass');
    await eq.setEnabled(true);
    expect(target.enabled, isTrue);
    expect(target.gains.first, greaterThan(target.gains.last));
    expect(target.gains.every((v) => v <= 0 && v >= -15), isTrue);
    final next = EqualizerController(target: _Target());
    await next.initialize();
    expect(next.enabled, isTrue);
    expect(next.preset, 'bass');
    await eq.setEnabled(false);
    expect(target.enabled, isFalse);
    expect(eq.gains, isNot(everyElement(0)));
  });
  test('manual gain clamps, reset flattens and unsupported has no live sliders',
      () async {
    final target = _Target();
    final eq = EqualizerController(target: target);
    await eq.initialize();
    await eq.setGain(0, 999);
    expect(eq.gains.first, 15);
    await eq.selectPreset('flat');
    expect(target.gains, everyElement(0));
    final unsupported = EqualizerController();
    await unsupported.initialize();
    expect(unsupported.available, isFalse);
  });
}
