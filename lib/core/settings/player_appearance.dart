enum PlayerSkin {
  classic('经典', '流体背景与大封面'),
  poster('大字海报', '让此刻的歌词成为画面主角'),
  mist('雾笺', '柔雾与手写般的歌词'),
  light('绘光', '在流动的光束中听见文字'),
  fireworks('花火', '随音乐升起的光点与文字');

  const PlayerSkin(this.label, this.description);
  final String label, description;
  static PlayerSkin fromStored(String? value) =>
      values.firstWhere((skin) => skin.name == value, orElse: () => classic);
}
