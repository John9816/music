import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/player/lrc_parser.dart';
import '../../core/settings/lyric_appearance.dart';
import '../../core/settings/settings_controller.dart';
import '../../widgets/glass.dart';
import '../player/karaoke_lyric_text.dart';
import 'settings_components.dart';

class LyricSettingsView extends StatelessWidget {
  const LyricSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final scheme = Theme.of(context).colorScheme;
    final style = lyricTextStyle(
      Theme.of(context).textTheme.bodyLarge!.copyWith(color: Colors.white),
      fontSize: settings.lyricFontSize,
      fontStyle: settings.lyricFontStyle,
    );
    return Scaffold(
      appBar: GAppBar(
        title: '歌词显示',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
                20, 12, 20, 32 + MediaQuery.paddingOf(context).bottom),
            children: [
              _LyricPreview(style: style),
              const SettingsSection('字体大小'),
              SettingsGroup(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
                  child: Column(children: [
                    Row(children: [
                      const Expanded(child: Text('字号')),
                      Text('${settings.lyricFontSize}',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: TypeScale.semibold,
                              color: scheme.onSurface)),
                    ]),
                    Semantics(
                      label: '歌词字号',
                      child: Slider(
                        value: settings.lyricFontSize.toDouble(),
                        min: minLyricFontSize.toDouble(),
                        max: maxLyricFontSize.toDouble(),
                        divisions: (maxLyricFontSize - minLyricFontSize) ~/ 2,
                        semanticFormatterCallback: (value) =>
                            '${value.round()}',
                        onChanged: (value) =>
                            settings.setLyricFontSize(value.round()),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [Text('小'), Text('大')],
                      ),
                    ),
                  ]),
                ),
              ]),
              const SettingsSection('字形样式'),
              SettingsGroup(children: [
                for (final preset in LyricFontStyle.values)
                  _StyleChoice(
                    preset: preset,
                    selected: settings.lyricFontStyle == preset,
                    onTap: () => settings.setLyricFontStyle(preset),
                  ),
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                child: Text(
                  '调整会自动保存，并应用到播放器歌词。紧凑视图会按比例缩放。',
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: scheme.onSurfaceVariant),
                ),
              ),
              GButton(
                label: '恢复默认',
                filled: false,
                onTap: settings.lyricFontSize != defaultLyricFontSize ||
                        settings.lyricFontStyle != LyricFontStyle.bold
                    ? settings.resetLyricAppearance
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StyleChoice extends StatelessWidget {
  const _StyleChoice(
      {required this.preset, required this.selected, required this.onTap});

  final LyricFontStyle preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '${preset.label}，${preset.description}',
      checked: selected,
      inMutuallyExclusiveGroup: true,
      onTap: onTap,
      child: ExcludeSemantics(
        child: GPressScale(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(preset.label,
                        style: TextStyle(
                            fontSize: 19,
                            fontWeight: preset.weight,
                            letterSpacing: preset.spacing)),
                    const SizedBox(height: 4),
                    Text(preset.description,
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 22,
                  color: selected ? scheme.primary : scheme.outlineVariant),
            ]),
          ),
        ),
      ),
    );
  }
}

class _LyricPreview extends StatelessWidget {
  const _LyricPreview({required this.style});
  final TextStyle style;

  static final _line = LrcLine(
    time: Duration.zero,
    text: '让旋律慢慢靠近',
    words: [
      for (var i = 0; i < '让旋律慢慢靠近'.length; i++)
        LrcWord(
            time: Duration(milliseconds: i * 400),
            duration: const Duration(milliseconds: 400),
            text: '让旋律慢慢靠近'[i]),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF35443F), Color(0xFF1C2624), Color(0xFF151A1A)],
        ),
      ),
      child: LayoutBuilder(builder: (context, constraints) {
        // Reserve the largest selectable text height so dragging the slider
        // never moves that slider away from the user's finger.
        final painter = TextPainter(
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          locale: Localizations.maybeLocaleOf(context),
        );
        var lineHeight = 0.0;
        for (final preset in LyricFontStyle.values) {
          for (final text in ['把喧嚣留在身后', _line.text, '听见此刻的自己']) {
            painter.text = TextSpan(
                text: text,
                style: lyricTextStyle(style,
                    fontSize: maxLyricFontSize, fontStyle: preset));
            painter.layout(maxWidth: constraints.maxWidth);
            if (painter.height > lineHeight) lineHeight = painter.height;
          }
        }
        painter.dispose();
        Widget previewRow(Widget child) => SizedBox(
              height: lineHeight.ceilToDouble(),
              child: Align(alignment: Alignment.centerLeft, child: child),
            );
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('效果预览',
              style: TextStyle(fontSize: 12, color: Color(0xB3FFFFFF))),
          const SizedBox(height: 22),
          previewRow(Text('把喧嚣留在身后',
              style:
                  style.copyWith(color: Colors.white.withValues(alpha: 0.30)))),
          const SizedBox(height: 18),
          previewRow(KaraokeLyricText(
            line: _line,
            style: style,
            position: const Duration(milliseconds: 1500),
            positionStream: const Stream<Duration>.empty(),
            playing: false,
          )),
          const SizedBox(height: 18),
          previewRow(Text('听见此刻的自己',
              style:
                  style.copyWith(color: Colors.white.withValues(alpha: 0.30)))),
        ]);
      }),
    );
  }
}
