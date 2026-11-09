# LockScreenWidget — MVC refactoring specification

User-approved specification, 2026-11-09. Baseline: `main`, `258dbbf`.

- Keep Swift/AppKit, macOS 15+, the editor, preview, and lock-screen behavior.
- Model data types only store data and must end in `Model`. Use separate functions for event selection, countdown calculations (explicit current time), and settings validation.
- JSON and UserDefaults persistence stay in `Models`, outside data types. Preserve `editorSettings.v1`, its JSON fields, and legacy `elementOffsets` migration.
- Views only lay out/draw supplied state and forward input. Buttons use target-action directed at controllers; other inputs may use callbacks/delegates. Keep shared `CountdownView`, rename the inspector to `TypographyInspectorView`, keep `OverlayPanel: NSPanel` in Views.
- `EditorWindowController` owns the editor window, card selection, inspector actions, and preview updates. `LockScreenController` owns lock notifications, panel lifecycle, and `LockScreenSpace`. One `CountdownController` supplies a shared one-second tick.
- `AppDelegate` owns application lifecycle, menus, and component wiring. Menu commands target controllers.
- Use `Models`, `Views`, `Controllers`, `Infrastructure`; keep `Resources/events.json`. Main filenames match their type. Types use UpperCamelCase; functions/properties use lowerCamelCase.
- Acceptance: open editor from menu; edit typography; see preview; restore settings after restart; display ticking panels on lock and close them on unlock. Retain multi-selection, Shift dragging, keyboard movement, source links, and the eight-second panel test.
