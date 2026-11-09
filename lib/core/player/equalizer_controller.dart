import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EqualizerBands {
  const EqualizerBands(
      {required this.frequencies, required this.minDb, required this.maxDb});
  final List<double> frequencies;
  final double minDb, maxDb;
}

abstract interface class EqualizerTarget {
  Future<EqualizerBands> parameters();
  Future<void> apply(bool enabled, List<double> gains);
}

class AndroidEqualizerTarget implements EqualizerTarget {
  AndroidEqualizerTarget(this.effect);
  final AndroidEqualizer effect;
  AndroidEqualizerParameters? _parameters;
  // just_audio 0.9.46 transports Android millibels / 1000, while
  // Android defines 100 millibels per dB. Keep this correction at the adapter.
  static double fromNativeGain(double value) => value * 10;
  static double toNativeGain(double decibels) => decibels / 10;
  @override
  Future<EqualizerBands> parameters() async {
    final p = await effect.parameters;
    _parameters = p;
    return EqualizerBands(
        frequencies: p.bands.map((b) => b.centerFrequency).toList(),
        minDb: fromNativeGain(p.minDecibels),
        maxDb: fromNativeGain(p.maxDecibels));
  }

  @override
  Future<void> apply(bool enabled, List<double> gains) async {
    final p = _parameters;
    if (p == null) return;
    // Apply gains while bypassed when turning on; retain them when bypassing.
    if (!enabled) await effect.setEnabled(false);
    for (var i = 0; i < p.bands.length; i++) {
      await p.bands[i].setGain(toNativeGain(gains[i]));
    }
    if (enabled) await effect.setEnabled(true);
  }
}

class EqualizerController extends ChangeNotifier {
  EqualizerController({EqualizerTarget? target}) : _target = target;
  final EqualizerTarget? _target;
  EqualizerBands? _bands;
  Future<void>? _initializing;
  Future<void> _pending = Future.value();
  bool _disposed = false, _enabled = false;
  String _preset = 'flat';
  String? _error;
  List<double> _gains = [];
  bool get supported => _target != null;
  bool get available => _bands != null;
  bool get enabled => _enabled;
  String get preset => _preset;
  String? get error => _error;
  List<double> get frequencies => _bands?.frequencies ?? const [];
  List<double> get gains => List.unmodifiable(_gains);
  double get minDb => _bands?.minDb ?? -12;
  double get maxDb => _bands?.maxDb ?? 12;
  double get headroom => _gains.fold(0.0, math.max);
  static const presets = {
    'flat': '平直',
    'bass': '低频增强',
    'treble': '高频增强',
    'vocal': '人声',
    'rock': '摇滚',
    'jazz': '爵士',
    'electronic': '电子',
    'soft': '柔和'
  };

  Future<void> initialize() {
    if (_disposed || _target == null || available) return Future.value();
    return _initializing ??= _load().whenComplete(() => _initializing = null);
  }

  Future<void> _load() async {
    try {
      final params =
          await _target!.parameters().timeout(const Duration(seconds: 4));
      if (_disposed) return;
      final prefs = await SharedPreferences.getInstance();
      if (_disposed) return;
      _bands = params;
      _enabled = prefs.getBool('equalizer_enabled') ?? false;
      _preset = prefs.getString('equalizer_preset') ?? 'flat';
      Map saved = {};
      try {
        saved = jsonDecode(prefs.getString('equalizer_gains') ?? '{}') as Map;
      } catch (_) {}
      _gains = params.frequencies.map((f) {
        final value = saved[f.toString()];
        return (value is num && value.isFinite ? value.toDouble() : 0.0)
            .clamp(minDb, maxDb)
            .toDouble();
      }).toList();
      await _apply();
    } catch (_) {
      _error = '音效暂不可用，请先播放一首歌曲后重试';
      _bands = null;
      _notify();
    }
  }

  Future<void> setEnabled(bool value) async {
    if (!available) return;
    _enabled = value;
    await _saveAndApply();
  }

  Future<void> setGain(int band, double gain) async {
    if (!available || band < 0 || band >= _gains.length || !gain.isFinite) {
      return;
    }
    _gains[band] = gain.clamp(minDb, maxDb).toDouble();
    _preset = 'custom';
    await _saveAndApply();
  }

  Future<void> selectPreset(String id) async {
    if (!available || !presets.containsKey(id)) return;
    _preset = id;
    _gains = frequencies.map((f) {
      final low = (1 - math.log(f / 60) / math.log(1000 / 60)).clamp(0.0, 1.0);
      final high =
          (math.log(f / 1500) / math.log(14000 / 1500)).clamp(0.0, 1.0);
      final middle =
          (1 - (math.log(f / 1200) / math.log(8)).abs()).clamp(0.0, 1.0);
      return (switch (id) {
        'bass' => low * 6,
        'treble' => high * 5,
        'vocal' => middle * 4 - low * 2,
        'rock' => low * 5 + high * 4 - middle * 2,
        'jazz' => low * 3 + high * 2 + middle,
        'electronic' => low * 6 + high * 3 - middle,
        'soft' => -high * 4 + middle,
        _ => 0.0,
      })
          .clamp(minDb, maxDb)
          .toDouble();
    }).toList();
    await _saveAndApply();
  }

  Future<void> _saveAndApply() async {
    _notify();
    // Serialize changes so an older slider position cannot win a race.
    _pending = _pending.then((_) async {
      if (_disposed) return;
      await _apply();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('equalizer_enabled', _enabled);
      await prefs.setString('equalizer_preset', _preset);
      await prefs.setString(
          'equalizer_gains',
          jsonEncode({
            for (var i = 0; i < frequencies.length; i++)
              frequencies[i].toString(): _gains[i],
          }));
    }).catchError((Object _) {
      _error = '音效调整失败，请重试';
      _notify();
    });
    await _pending;
  }

  Future<void> _apply() async {
    final gain = headroom;
    await _target!.apply(_enabled,
        _gains.map((v) => (v - gain).clamp(minDb, maxDb).toDouble()).toList());
    _error = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
