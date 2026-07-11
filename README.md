# Speed Reader

A macOS menu-bar app that captures your screen, OCRs the text, and guides your
eyes with a moving highlight over the actual on-screen content at a configurable
words-per-minute pace. See [RESEARCH.md](RESEARCH.md) for the full research
behind the design.

## Status

- ✅ **Milestone 1 — skeleton**: menu-bar app, always-on-top floating widget
  (WPM slider with pace indicator, Focus/Guide mode picker, guide style +
  chunk-size options), global hotkey, position persistence, minimize to an
  orange line (click to reopen).
- ✅ **Milestone 2 — capture + OCR**: ScreenCaptureKit region capture,
  drag-to-select picker, Vision OCR with per-line and per-word screen-space
  boxes, debug box viewer (menu → Show OCR Boxes).
- ✅ **Milestone 3 — the reader**: freeze-frame Focus mode with line dimming,
  live Guide mode, chunked word-highlight stepping with the research-backed
  timing engine (punctuation/paragraph pauses, number slowdown), keyboard
  controls, progress HUD, session stats.
- ✅ **Milestone 4 — polish**: global hotkeys (⌥⇧S read, ⌥⇧A re-read last
  region — the scroll-and-continue flow), highlight color + dimming
  intensity settings, persistent daily reading stats in the widget.
- ⬜ Milestone 5 — ship (signing, notarization, Sparkle, onboarding).

## Run

```sh
Support/build-app.sh --run
```

This assembles and launches `build/SpeedReader.app`. (A plain `swift build`
binary also works, but macOS then attributes the Screen Recording permission
to your terminal instead of Speed Reader.)

The widget appears in the top-right corner; the hare icon lives in the menu
bar. No Dock icon — it's a menu-bar utility.

## Controls

| Action | How |
|---|---|
| Show/hide widget | ⌥⇧R (global) or menu-bar icon → Show/Hide Widget |
| Start reading (global) | ⌥⇧S — select a region and go |
| Re-read last region | ⌥⇧A — after scrolling, keep reading the same spot |
| Minimize widget | ✕ on the widget → orange line; click the line to reopen |
| Move widget | Drag anywhere on it (position is remembered) |
| Reading options | Gear icon on the widget |
| Start reading | Read Screen button → drag-select the text region |
| While reading | Space/click pause · ←/→ sentence jump · ↑/↓ ±25 wpm · Esc exit |
| Quit | Menu-bar icon → Quit Speed Reader |

Clicking the widget never steals focus from the app you're reading
(non-activating panel), and it stays visible across Spaces and over
full-screen apps.
