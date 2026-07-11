# Speed Reader — Deep Research Report

*Compiled 2026-07-11 from four parallel research tracks: app architecture, capture/OCR pipeline, overlay rendering, and speed-reading science + competitive landscape.*

---

## 1. Verdict: Can this be built?

**Yes. No hard blockers.** Every required capability exists on macOS and is proven by shipping open-source apps:

- Always-on-top floating widget (like the Pomodoro app) → `NSPanel` with `.floating` level — trivial.
- Full-screen transparent **click-through** overlay for drawing the pointer over other apps → `NSWindow` with `ignoresMouseEvents = true` — trivial, many apps do it.
- One-shot screen capture → **ScreenCaptureKit** (`SCScreenshotManager`), ~tens of ms.
- Text extraction **with word/line coordinates** → **Apple Vision** (`VNRecognizeTextRequest`), free, offline, on-device; returns per-line bounding boxes plus per-word boxes via `boundingBox(for: range)`. Full-screen OCR on Apple Silicon: **~0.3–1.0 s** — fast enough for a "press start" flow.
- Animate the guide word-by-word over the real screen → Core Animation layer on the overlay window.

**And the product is unclaimed territory.** Extensive searching found **no direct competitor** doing pointer/highlight-guided pacing over arbitrary on-screen content:
- `speed-reader.pro` (macOS, $8.99) does screen-OCR but dumps text into an RSVP widget — loses spatial context.
- "Pacer" Chrome extension does moving-highlight pacing, but only on browser DOM.
- "Overlays!" (Mac) is a system-wide reading ruler, but manual — no text awareness, no pacing.

The combination — **OCR word boxes + animated guide over the user's actual screen** — doesn't exist yet.

### The two real friction points (not blockers)

1. **macOS Sequoia/Tahoe monthly screen-recording re-approval nag.** All third-party capture apps get a monthly "Continue to Allow" prompt. Not suppressible by developers. Mitigation: use `SCContentSharingPicker` (system picker per session — exempt from the nag) and/or accept the monthly prompt as a cost.
2. **Stale coordinates.** OCR boxes are only valid for the frozen frame; if the user scrolls, the pointer highlights the wrong pixels. Solved by the **freeze-frame reading mode** (see §4).

---

## 2. Recommended stack: native Swift (AppKit + SwiftUI), macOS-only

| | Swift native | Electron | Tauri v2 |
|---|---|---|---|
| Always-on-top widget | First-class (`NSPanel`, `.nonactivatingPanel`) | Works | Needs community plugin for panel behavior |
| Click-through overlay | Trivial | Works but forwarding has gotchas (#15376, #33281) | No `forward` option — needs 60fps cursor-polling hack |
| Transparent full-screen overlay perf | Native, GPU-composited, smooth | **Worst case for Electron** — documented lag (#28439); caused system-wide Tahoe WindowServer bug | Transparency needs `macOSPrivateApi` (kills App Store); prod rendering bugs |
| Vision OCR | In-process | Needs a Swift sidecar binary anyway | Needs Rust→ObjC bindings anyway |
| Coordinate math (Retina, multi-display) | One process, one coordinate system | IPC hand-offs, DIP conversion bugs | Same |
| Footprint | ~5 MB app, 20–40 MB RAM | ~150 MB app, 200–300 MB RAM | ~10 MB app, but Tahoe 4× memory regression |

**Why Swift wins decisively for this app:** every hard part (ScreenCaptureKit, Vision, overlay window, coordinate mapping) is a macOS-native API. Electron/Tauri would each need a native Swift sidecar for OCR anyway, and a full-screen transparent Chromium window is precisely where Electron performs worst on macOS. All reference apps in this space (TRex, EasyPresent, mac-mouse-highlighter, Boring.Notch) are Swift.

*Fallback if cross-platform ever becomes a requirement: Tauri v2 (a comparable overlay product shipped on it in 2025-26), Electron third.*

### Window architecture (three windows)

1. **Widget panel** — the always-visible floating control (like the Pomodoro app): `NSPanel`, `styleMask: [.nonactivatingPanel, .borderless]`, `level = .floating`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, `LSUIElement = YES` (menu-bar app, no Dock icon).
2. **Overlay window** — one borderless transparent window **per display**: `level = .screenSaver`, `isOpaque = false`, `ignoresMouseEvents = true`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`. Fully click-through — never mix interactive regions into it.
3. **Reading control bar** — small separate interactive panel (pause/speed/exit) shown during a session. Separate window, not hit-test tricks (most robust pattern; historic macOS regressions make partial click-through unreliable).

Guide rendering: a `CALayer` whose position animates via Core Animation (GPU-composited, smooth even if main thread hiccups). Line-dimming = full-screen black layer with an animated `CAShapeLayer` even-odd mask cutout.

---

## 3. The pipeline

```
Click "Read" on widget
  → (optional) drag-select region, or pick window via SCContentSharingPicker
  → SCScreenshotManager.captureImage (exclude own overlay windows from filter)
  → VNRecognizeTextRequest (.accurate, usesLanguageCorrection, full Retina pixels)
  → per-line observations; word boxes via boundingBox(for: wordRange)
  → line grouping + XY-cut column detection + UI-chrome filtering
  → freeze-frame overlay shows the captured image + starts the guide animation
```

### Coordinate conversion (the classic bug farm)

Vision returns **normalized 0–1, bottom-left origin, relative to the image**. To screen points:
1. `pxRect = VNImageRectForNormalizedRect(bbox, imgW, imgH)`
2. Flip Y: `pxTopY = imgH - (pxRect.maxY)`
3. Divide by `SCContentFilter.pointPixelScale` (per-display — don't assume 2.0; compute `capturePixelWidth / screenPointWidth`)
4. Offset by the capture region's screen origin.

Watch: AppKit is bottom-left origin, CG/AX/captured images are top-left; mixed-DPI multi-monitor setups (2× laptop + 1× external); one overlay window per `NSScreen`, recomputed on `didChangeScreenParametersNotification`.

### Reading order + chrome filtering

- Merge observations whose vertical centers differ < 0.6 × median line height → visual lines.
- Recursive **XY-cut** (~100 lines) on line boxes for columns/blocks; read blocks in order.
- Paragraph break when vertical gap > ~1.5 × median line gap.
- Chrome filtering v1: main content = largest block by (area × line count); drop narrow blocks (< 25% width), sparse blocks (median < 3 words/line), low-confidence (< 0.4) observations, menu-bar band.
- **Escape hatch that makes all of this optional for v1: let the user drag-select the region to read** (TRex-style). Auto-detection becomes a v1.5 nicety.
- macOS 26 only: `RecognizeDocumentsRequest` returns document → paragraph → line → word structure natively; use behind `if #available(macOS 26)`.

### Why OCR, not the Accessibility API

AX (`AXBoundsForRange`) gives perfect text + live coordinates **when implemented** — but only ~33% of macOS apps expose full AX metadata (Screen2AX paper); Chrome/Electron apps disable their AX tree by default; PDFs/images/terminals are hit-or-miss. OCR gives one uniform code path over everything visible. AX is a good v2 enhancement for known-good apps (adds live tracking), not the v1 foundation.

---

## 4. Key design decision: freeze-frame "Focus mode" as the default

The stale-capture problem (user scrolls → boxes wrong) is otherwise unsolved. The recommended v1 model:

- On start, the overlay **displays the captured screenshot itself**, pixel-perfect over the real screen — the user can't tell the difference, but now we fully control the pixels: we can dim non-current lines, draw rulers, boost contrast, and coordinates can never go stale. (Precedent: Sysinternals ZoomIt freezes the screen the moment you annotate.)
- Reading a passage is naturally modal. Esc / click / scroll instantly dismisses the freeze; optionally auto-recapture + "continue reading" after a scroll settles.
- A "live overlay" lite mode (pointer over the real, unfrozen screen) remains viable later for static content, with scroll-detection (`NSEvent.addGlobalMonitorForEvents(.scrollWheel)` — no extra permission) → pause + re-OCR.

---

## 5. The guide: what the science says

### How the pointer should move

Reading eyes move in **saccades + fixations**, not smooth motion — continuous horizontal drift actively interferes with reading saccades (JOV drifting-text study). Product precedent (Speechify, MS Immersive Reader) is karaoke-style discrete word highlighting.

**Default: discrete word-by-word highlight jump** (each jump is the target for the next saccade). Options: glide-within-word/jump-between-words, and a line-level ruler mode. A constant-velocity gliding dot is the weakest mode — last priority.

### Visual guide styles, ranked (CHI 2023 "Digital Reading Rulers", n=177, ~51% dyslexic: Grey Bar / Shade / Underline gave +10–20 WPM, biggest gains for dyslexic readers, no universally preferred style → **make it user-selectable**)

1. **Word highlight box** (karaoke) — default; unambiguous, tolerates OCR slop, matches saccades.
2. **Line ruler + dimming** (shade everything except current line) + word cursor — strongest accessibility evidence; natural in freeze mode.
3. **Underline sweep** — the "teacher's finger"; offer with per-word easing.
4. **Moving dot** — cheapest, weakest signal.
5. BeeLine-style line-wrap color gradient — v2, freeze-mode only (requires re-rendering text).

### Per-word timing (adapted from pasky/speedread + Spritz)

```
base = 0.9                       # plain word
     | 1.2  (multi-word chunk)
     | 2.0  (ends with , ; :)
     | 3.0  (ends with . ? !)
t(word) = (base + 0.04 * sqrt(len(word))) * (60 / WPM) seconds
+ line-end pause ≈ comma weight; paragraph pause ≈ 2–3× full stop
+ auto-slow 1.5× for numbers/URLs; +10 ms/char over 6 chars for long words
```

Word-length-proportional duration measured 33% faster sentence reading vs constant duration in RSVP research.

### Technique evidence (what to build vs skip)

| Technique | Verdict |
|---|---|
| **Meta-guiding / pointer pacing** | Helps modestly (~fewer regressions & fixations, ~+10–25% honest speed gain). **Our core mechanic — and it preserves regressions, sidestepping the main scientific criticism of RSVP.** |
| **Line ruler + dimming** | Helps, especially dyslexia/ADHD (CHI 2023). First-class mode. |
| **Chunking (2–3 words)** | Reasonable UX within physiology (perceptual span ≈ 15 chars). Offer 1–4 words. |
| **RSVP (Spritz-style)** | Mixed → harmful above ~350–400 WPM (Schotter 2014: blocking regressions drops comprehension 75%→50%; Rayner 2016; Benedetto 2015). Fine as an optional v1.1 mode, capped sensibly, with one-key rewind. |
| **Bionic reading** | Debunked for speed (Readwise n>2000; Acta Psych 2024). Preference toggle at most. |
| **Subvocalization suppression** | Debunked — don't build or market. |
| **Dyslexia fonts / color tints** | No performance evidence; offer as preferences, no claims. (Letter/word *spacing* does have evidence.) |

**WPM reality (Brysbaert 2019 meta-analysis):** average adult ≈ 238 WPM non-fiction; comprehension holds to ~400–450, collapses beyond; 600+ is skimming. → Default 300, range 100–800 with honesty indicator (green ≤400, amber 400–600 "skimming", red >600). **Market as "a pacer that keeps you moving and focused," not "read 3× faster"** — exaggerated claims are what the literature debunks.

---

## 6. v1 feature set

**Widget (always on top):** Start Reading (global hotkey too) · WPM slider · mode picker · settings gear · session stats.

**Reading modes:**
- **Focus mode (default):** freeze-frame + line dimming + word highlight.
- **Guide mode:** pointer over live screen (static content).
- Chunk stepping (1–4 words) as a setting on both.

**Settings panel:**
- WPM 100–800 (default 300) + honesty indicator; optional ramp-up (+10 WPM/min).
- Guide style: word highlight / underline / ruler band + dim; color & opacity.
- Pause multipliers: sentence 1.5×, paragraph 2×, comma 1.2× (editable).
- Auto-slowdown: long words, numbers/URLs (on).
- Keyboard: Space pause · ←/→ sentence rewind/skip (rewind must be frictionless — regressions aid comprehension) · ↑/↓ ±25 WPM · Esc exit.
- Accessibility: tint overlay, dim opacity, high-contrast, highlight colors (not red/green-only).
- Progress: % + time remaining; stats (words read, effective WPM).

**v2 ideas:** RSVP popup mode · AX-based live tracking for native apps · acceleration training gated by comprehension quizzes (AceReader model) · frequency-based word timing · auto re-OCR on scroll ("continue reading") · BeeLine gradient in Focus mode · re-rendered clean-reader view · stats history/streaks · Windows port (Tauri + Windows.Media.OCR).

---

## 7. Permissions & distribution

- **Screen Recording (TCC):** prompted on first capture; user must enable in System Settings and relaunch. Sequoia/Tahoe re-prompt ~monthly — handle gracefully; `SCContentSharingPicker` avoids the nag. **Dev gotcha:** the TCC grant is tied to code-signing identity — use a stable Apple Development cert or every rebuild re-prompts.
- No Accessibility permission needed for v1 (scroll monitoring via `addGlobalMonitorForEvents` is permission-free; global hotkey via `RegisterEventHotKey`/KeyboardShortcuts lib).
- **Distribute outside the App Store:** Developer ID + notarization ($99/yr), Sparkle for updates. (MAS possible but risky for overlay apps; unnecessary.)

---

## 8. Reference projects to steal from

| Project | What to take |
|---|---|
| [TRex](https://github.com/amebalabs/TRex) (Swift, ~3k★) | Entire capture→Vision pipeline, region-selection UX, menu-bar app structure |
| [mac-mouse-highlighter](https://github.com/nikhilbhansali/mac-mouse-highlighter) (Swift) | CVDisplayLink-driven overlay highlight animation — nearly identical to our pointer |
| [EasyPresent](https://github.com/josiahcoad/EasyPresent) (Swift 6) | Click-through overlay window flags, pointer rendering |
| [Annotate](https://github.com/epilande/Annotate) (Swift) | fullScreenAuxiliary handling, interactive↔click-through mode toggling |
| [Capso](https://github.com/lzhgus/Capso) / [macshot](https://github.com/sw33tLie/macshot) | ScreenCaptureKit region-selector overlay |
| [boring.notch](https://github.com/TheBoredTeam/boring.notch) (SwiftUI) | SwiftUI-in-NSPanel floating-widget polish |
| [pasky/speedread](https://github.com/pasky/speedread) | Per-word timing formula, ORP math |
| [sprint-reader-chrome](https://github.com/anthonynosek/sprint-reader-chrome) (OSS) | Settings & stats panel reference |
| [screenpipe](https://github.com/screenpipe/screenpipe) (Rust, ~15k★) | AX-first/OCR-fallback strategy (v2) |
| [bytefer/macos-vision-ocr](https://github.com/bytefer/macos-vision-ocr) | Swift CLI JSON-emitting OCR template (if a sidecar is ever needed) |

---

## 9. Top risks

1. **Coordinate mapping bugs** (normalized bottom-left → screen top-left, per-display Retina scale, multi-monitor) — the classic off-by-half-screen bug farm; isolate in one tested module.
2. **Sequoia monthly permission nag** — design the re-grant flow up front.
3. **Reading order on complex layouts** (multi-column PDFs, chat UIs) — v1 escape hatch: user drag-selects the region.
4. **Word-box slop** — Vision word rects are derived from the line model (~few px error); prefer generous highlight boxes/line-level dimming over pixel-tight underlines.
5. **Unstable dev code signing** resets the TCC grant every build — set up signing before testing capture.
6. **OCR misses** on low-contrast themes/tiny fonts — always OCR at full Retina resolution.

---

## 10. Suggested build order

1. **Milestone 1 — skeleton:** menu-bar app + floating widget panel (Pomodoro-style), global hotkey.
2. **Milestone 2 — capture + OCR:** Screen Recording permission flow, drag-select region, SCScreenshotManager → Vision → word/line boxes; debug view drawing boxes over the screenshot (validates all coordinate math).
3. **Milestone 3 — the reader:** freeze-frame overlay + word-highlight animation with the timing engine; Space/arrows/Esc controls; control bar.
4. **Milestone 4 — polish:** guide styles, line dimming, settings persistence, pause rules, stats, multi-monitor.
5. **Milestone 5 — ship:** signing, notarization, Sparkle, onboarding for the permission flow.
