# Typography editor implementation plan

Goal: retain v0.2.0 in Git and extend the native preview editor with app icon, per-block typography, optional details, keyboard nudging and canvas centering.

Architecture: Codable editor settings persist three block styles and normalized offsets in UserDefaults, migrating existing positions. CountdownView owns editing interactions and draws identical settings in preview and overlay. A separate AppKit inspector edits selected blocks. The app icon is generated from the existing vector skull at build time.

Constraints: macOS 15+, Apple Silicon, native AppKit; no dependencies; preserve private SkyLight lifecycle and input-transparent lock screen; default information block hidden, opacity 60%; keep existing default layout and Shift/marquee behavior.

- [x] Snapshot existing sources and changelog as v0.2.0; push main and tag to explicitly confirmed BarryShepard/TEotW.
- [x] Add Sources/EditorSettings.swift: Codable styles (family, weight, point size, line height auto/custom, tracking percent, horizontal and vertical alignment), three normalized offsets, optional details. Validate persisted values and migrate elementOffsets. Include in scripts/build.sh and scripts/test.sh.
- [x] Update Sources/CountdownView.swift: render configured styles and optional detail block; preserve interactions with variable visible indices; selection callback, keyboard arrows (1 logical screen point, Shift 10), group centering with shared translation, reset layout. Meaningful Tests/LayoutTests.swift coverage for migration, typography, hidden details, keyboard nudges and group centers.
- [x] Add Sources/TypographyInspector.swift: native selected-block control, font family and type weight, numeric controls, automatic line height, tracking, alignment, details visibility and centering actions. Wire in Sources/AppDelegate.swift with preview inspector and synchronization to overlays. Preserve focus in numeric controls while arrow keys nudge only the canvas.
- [x] Generate Resources/AppIcon.icns from vector skull using build-time Swift generator and a PNG-backed ICNS container; set CFBundleIconFile. Keep menu icon monochrome. Update version to 0.3.0 and document controls.
- [x] Run scripts/test.sh, scripts/build.sh, --diagnose, diff check, visually render inspector and app icon, review code and correct findings. Native UI restart was refused by the computer tool because the app file changed; manual live verification is still required. Leave new work reviewable on codex/typography-editor; working v0.2.0 remains on main.
