enum PlayerSkin {
  classic('经典', '流体背景与大封面'),
  poster('大字海报', '让此刻的歌词成为画面主角'),
  mist('雾笺', '柔雾与手写般的歌词'),
  light('绘光', '在流动的光束中听见文字'),
  fireworks('花火', '随音乐升起的光点与文字'),
  // TuneFreeNext 4.3.7 同款皮肤（内置渲染资源，逐字对齐其协议）。
  lumiere('流光', '流光溢彩的逐字歌词 · 原版引擎'),
  hanabi('花火·原版', '绽放的光点歌词 · 原版引擎'),
  nebbia('氤氲', '雨雾手写歌词 · 原版引擎');

  const PlayerSkin(this.label, this.description);
  final String label, description;

  /// 是否走 TuneFreeNext 原版渲染引擎。
  bool get isTfn =>
      this == PlayerSkin.lumiere ||
      this == PlayerSkin.hanabi ||
      this == PlayerSkin.nebbia;

  static PlayerSkin fromStored(String? value) =>
      values.firstWhere((skin) => skin.name == value, orElse: () => classic);
}

/// Tfn 引擎的皮肤分类，与 [PlayerSkin] 中的原版皮肤一一对应。
enum TfnSkin { lumiere, hanabi, nebbia }

extension TfnSkinX on PlayerSkin {
  TfnSkin? get tfnSkin => switch (this) {
        PlayerSkin.lumiere => TfnSkin.lumiere,
        PlayerSkin.hanabi => TfnSkin.hanabi,
        PlayerSkin.nebbia => TfnSkin.nebbia,
        _ => null,
      };
}

/// 原版渲染引擎的帧率档位，对应对方 `player_skin_frame_rate`。
enum SkinFrameRate {
  powerSave('省电', 24, 1.0),
  balanced('均衡', 30, 1.5),
  smooth('流畅', 60, 2.0);

  const SkinFrameRate(this.label, this.maxFps, this.pixelRatioCap);
  final String label;
  final int maxFps;
  final double pixelRatioCap;

  static SkinFrameRate fromStored(String? value) =>
      values.firstWhere((v) => v.name == value, orElse: () => balanced);
}
