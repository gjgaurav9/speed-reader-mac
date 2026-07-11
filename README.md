# Speed Reader

A macOS menu-bar app that captures your screen, OCRs the text, and guides your
eyes with a moving highlight over the actual on-screen content at a configurable
words-per-minute pace. See [RESEARCH.md](RESEARCH.md) for the full research
behind the design.

## Status

- ✅ **Milestone 1 — skeleton**: menu-bar app, always-on-top floating widget
  (WPM slider with pace indicator, Focus/Guide mode picker, guide style +
  chunk-size options), global hotkey, position persistence.
- ⬜ Milestone 2 — capture + OCR (ScreenCaptureKit → Vision, word/line boxes,
  debug box viewer).
- ⬜ Milestone 3 — the reader (freeze-frame overlay, word-highlight animation,
  timing engine, keyboard controls).
- ⬜ Milestone 4 — polish (guide styles, line dimming, pause rules, stats,
  multi-monitor).
- ⬜ Milestone 5 — ship (signing, notarization, Sparkle, onboarding).

## Run

```sh
swift build
.build/debug/SpeedReader
```

The widget appears in the top-right corner; the hare icon lives in the menu
bar. No Dock icon — it's a menu-bar utility.

## Controls

| Action | How |
|---|---|
| Show/hide widget | ⌥⇧R (global) or menu-bar icon → Show/Hide Widget |
| Move widget | Drag anywhere on it (position is remembered) |
| Reading options | Gear icon on the widget |
| Quit | Menu-bar icon → Quit Speed Reader |

Clicking the widget never steals focus from the app you're reading
(non-activating panel), and it stays visible across Spaces and over
full-screen apps.
