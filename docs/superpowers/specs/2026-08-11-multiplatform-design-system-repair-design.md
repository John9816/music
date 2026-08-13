# DuckMusic Multiplatform Design System Repair

## Product frame

DuckMusic is a daily-use music player for iOS, Android, macOS, and Windows. Its
primary job is to help listeners resume, find, and control music quickly. The
7511 number lockup and green/yellow app icon are the fixed brand layer; user
theme colors remain a personalization layer.

## Direction

Keep the existing information architecture and immersive player. Repair the
shared design system instead of replacing every screen:

- Keep all seven theme colors and light/dark modes.
- Keep page surfaces neutral so changing an accent does not recolor the whole
  application.
- Derive readable foreground colors for every accent and container.
- Use one responsive vocabulary: compact 600, content split 720, navigation
  840, docked player 1080, content maximum 1320.
- Restore pointer affordances and scroll position feedback on Windows/Linux.
  Preserve the current macOS MouseTracker workaround.
- Make authentication layouts mobile-first and vertically balanced on desktop,
  with persistent field labels and wrapping legal consent copy.

## Visual tokens

- Stage black: `#0D1114`
- Paper white: `#F5F7F8`
- 7511 green: `#2FD365`
- Cue yellow: `#FFD25A`
- Track gray: `#909A93`
- Error red: `#FF453A`

Typography continues to use native platform UI fonts for reliable Chinese
rendering. Display headings use a restrained heavy weight, body copy uses
regular/medium weights, and rankings/times use tabular figures as the utility
voice. No external font payload is added in this repair.

## Layout

Mobile authentication:

```text
[7511 mark]
[title]
[field label]
[field]
[field label]
[field]
[consent wraps] [recovery]
[primary action]
```

Desktop authentication:

```text
+--------------------------------------------+
|                                            |
|          [7511 mark + form]                |
|          vertically balanced              |
|                                            |
+--------------------------------------------+
```

The single signature is the 7511 number lockup. Theme colors do not replace it
and no new decorative glass layers, gradients, or nested cards are added.

## Accessibility and interaction

- Normal-size text on accent fills must reach WCAG AA contrast of 4.5:1.
- Legal consent copy may wrap and remains available at larger text scales.
- Keyboard focus remains visible.
- Windows/Linux pointer targets expose hover and click cursors.
- Desktop scrollbars appear where the platform expects them; mobile remains
  edge-to-edge without persistent scrollbars.

## Verification

- Unit/widget tests cover all accent foreground ratios and neutral surfaces.
- Widget tests cover responsive breakpoint consistency and authentication at
  mobile/desktop sizes with enlarged text.
- Existing shell, player, and playlist tests remain green.
- Final visual review uses the macOS build and iPhone Simulator.
