# Native Personal Canvas — Stage A Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver a runnable native text/photo editor with real image import/replacement, persistent scene and typography, native editing commands, and shared rendering on the lock screen.

**Architecture:** Introduce a versioned scene and asset store alongside the existing countdown model. A new AppKit editor owns scene transactions, inspector, selection and native text input; a shared renderer draws the same scene in an input-transparent overlay. Preserve the legacy countdown editor/catalog and private space lifecycle while routing the new editor as the primary entry point.

**Tech Stack:** Swift 5 mode, AppKit, CoreText, CoreGraphics, existing shell/swiftc build. No third-party runtime dependency.

## Global Constraints

- macOS 15+; build on Apple Silicon and preserve the existing universal build option.
- All properties are edited in the sidebar. File choice uses a standard system file picker; no modal settings dialogs.
- Stage A implements text and images; note-specific resizing, configurable timers/presets, crop/rotation handles and superellipse controls are later spec stages, not completed features of this plan.
- Preserve existing `editorSettings.v1`, catalog, diagnostics commands, and legacy tests; do not delete or overwrite user settings to seed the new document.
- Real input/clipboard/drag-and-drop needs native smoke testing; model tests alone never prove those paths.
- Use the current working directory on branch `codex/personal-lockscreen-editor`; a separate worktree requires a user reply authorizing it. Existing README/spec edits belong to this work and must be preserved.
- Tests use temporary storage and private pasteboards, never the user's actual application-support data or general clipboard.
- Do not programmatically lock the user's Mac, change system settings, publish, push, or claim a secure-lock manual test without an observed result.

## Task 1: Versioned scene and durable image resources

**Files:** Create `Sources/SceneModel.swift`, `Sources/SceneStore.swift`, `Tests/SceneTests.swift`; extend `scripts/test.sh` with a separately compiled SceneTests executable. Do not edit UI/AppDelegate/build scripts in this task.

**Interfaces:** Produces the following names for the editor and integration tasks. All geometry is top-left-origin logical points. Types conform to Codable/Equatable; element ID is a UUID; store ID strings are opaque safe file basenames.

```swift
enum SceneElementKind: String, Codable { case text, image }
struct SceneColor: Codable, Equatable {
    var red: Double; var green: Double; var blue: Double; var alpha: Double
    var nsColor: NSColor { /* convert validated RGBA */ }
}
struct SceneTextStyle: Codable, Equatable {
    var family: String; var weight: Int; var fontSize: Double
    var lineHeight: Double; var letterSpacing: Double
    var horizontalAlignment: Int; var verticalAlignment: Int
    var color: SceneColor
    // Supply default initializer, func font(scale: CGFloat) -> NSFont.
}
struct SceneElement: Codable, Equatable, Identifiable {
    var id: UUID; var kind: SceneElementKind; var name: String
    var frame: CGRect; var rotation: Double; var cornerRadius: Double; var opacity: Double
    var text: String; var style: SceneTextStyle
    var assetID: String?; var imageRect: CGRect?
    // Supply defaulted init(kind:frame:), default UUID/name/text/style as appropriate.
}
struct EditorScene: Codable, Equatable {
    var schemaVersion: Int; var canvasSize: CGSize; var elements: [SceneElement]
    // Supply init(canvasSize:elements:), current version 1.
    func validated() throws -> EditorScene
}
final class SceneStore {
    init(directory: URL) throws
    static func defaultDirectory() throws -> URL
    func load() throws -> EditorScene?
    func save(_ scene: EditorScene) throws
    func importImage(at url: URL) throws -> String
    func importImage(data: Data) throws -> String
    func imageURL(for assetID: String) -> URL?
    func image(for assetID: String) -> NSImage?
}
```

- [ ] Write tests for round-trip of text style/position and image reference, import independence after original deletion, unreadable bytes, malformed geometry/version, safe asset ID resolution, and previous valid scene preservation after an invalid save.
- [ ] Implement scene defaults/validation. Reject nonfinite geometry, nonpositive scene/element sizes, duplicate IDs, unsupported versions and invalid numeric style values. Do not silently reset a corrupt document. Source image/scene failure messages are user-readable Russian. NSColor itself is not serialized. Keep font family on fallback and preserve independent block styles.
- [ ] Implement the store: `scene.json` plus `Assets/` inside the passed directory, atomic document writes, decode/validate before replacing a saved document, original imported bytes stored under a new unique ID, no reliance on external source paths, no deleting replaced assets used by Undo. A missing scene returns nil; corrupt existing scene throws. Resolve IDs without directory traversal. Existing missing assets remain representable for the UI placeholder. Default directory is `Application Support/LockScreenWidget`, resolved with FileManager.
- [ ] Run `bash scripts/test.sh`. SceneTests uses `FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)` with cleanup and a generated PNG, not personal files. Concrete core assertions:

```swift
let element = SceneElement(kind: .text, frame: CGRect(x: 20, y: 30, width: 300, height: 100))
let scene = EditorScene(canvasSize: CGSize(width: 1512, height: 982), elements: [element])
try store.save(scene)
assert(try store.load() == scene)
assert(store.imageURL(for: "../scene.json") == nil)
// After a failed save of a copy with NaN width, load() still equals scene.
```

- [ ] Self-review and commit only the four owned files; record test command/output and exact interfaces in the task report.

## Task 2: Adopt and verify colleague MVC refactor

**Files:** Changes from colleague commit `3eecd16ce7b3d556c64e9dddf529d1517ba1c62b` (PR1), especially `Sources/{Models,Views,Controllers,Infrastructure}`, `Sources/AppDelegate.swift`, `Sources/main.swift`, README, scripts and legacy tests. Preserve all Task 1 scene/store/test files and the new spec/plan.

**Interfaces:** New legacy APIs replace old root paths: `ApplicationModel`, `EditorWindowController`, `LockScreenController`, `CountdownController`, `BlockTypographyModel`, `loadEventCatalog(_:)`, `selectNextEvent(in:now:)`. New scene APIs remain exactly as Task 1 defined. `SceneTextStyle` must not depend on the removed root `BlockTypography` type.

- [ ] Read `colleague-pr-review.md` in this plan's SDD workspace and adopt the fetched exact commit locally with `git cherry-pick 3eecd16ce7b3d556c64e9dddf529d1517ba1c62b`. Resolve README/test-script conflicts by preserving both MVC documentation/testing and the new scene suite/spec link. No remote merge/push.
- [ ] Fix the verified editor-open regression in `Sources/Controllers/EditorWindowController.swift`:

```swift
@objc func showPreview() {
    if window == nil { loadWindow() }
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
    refresh(at: Date())
}
```

`isWindowLoaded` is not a usable window-existence guard for this no-nib controller. Existing `LockScreenControllerTests` line51 already catches the bug on this Mac. Preserve that assertion rather than deleting it.

- [ ] Run `bash scripts/test.sh`, including Task 1's SceneTests and the PR's CoreTests/SettingsTests/LayoutTests/LockScreenControllerTests; run `bash scripts/build.sh --universal` and the app diagnostic. Root's scratch check already confirmed original PR builds universally and this exact fix makes the focused lifecycle test pass; validate the combined working branch once.
- [ ] Record runtime output accurately: one AppKit `IOPMScheduleUserActivityLevelNotification returned 0` informational system line is present in CLI lifecycle tests and must be reported, without asserting pristine output. Keep MVC verification documentation honest about additional Mac evidence; no claim of secure-lock validation.
- [ ] Commit scoped follow-up fixes/documentation, write exact resolved source paths and test evidence in report. Do not change the new scene interfaces or implement the scene editor in this task.

## Task 3: Native editor, inspector, clipboard and reusable renderer

**Files:** Create focused files under `Sources/Scene…swift` for editor controller, canvas/input, rendering, inspector and editing state. Add `Tests/SceneEditingTests.swift` and its compilation to `scripts/test.sh`. Extend `Sources/SceneModel.swift` with the backward-compatible optional `var autoTextWidth: Bool? = nil`; nil means fixed width for existing documents. Preserve schema version 1 and test round-trip plus missing-key decode. Do not edit AppDelegate/main/build scripts; integration is Task 4.

**Interfaces:** Consumes Task 1's scene/store and Task 2's adopted MVC checkout. Produces:

```swift
final class SceneEditorWindowController: NSWindowController {
    init(scene: EditorScene, store: SceneStore)
    var scene: EditorScene { get }
    var onSceneChange: ((EditorScene) -> Void)?
    var onRevealLegacy: (() -> Void)?
    func showEditor()
    func setPersistenceBlocked(_ message: String)
    func flush()
}
final class SceneDisplayView: NSView {
    init(scene: EditorScene, store: SceneStore)
    var scene: EditorScene
    // isFlipped == true; no focus or input handling, scales scene with aspect-fit.
}
```

- [ ] Implement an editing state with stable selection IDs and snapshot Undo/Redo for structural changes. Centralize image add/replace so file, private/general pasteboard and drop use one transaction implementation. One import batch/move/group action/replace is one Undo. Replace retains node ID/frame/angle/corners/opacity/order, imports a distinct asset for correct Undo, and fits the new source proportionally into its frame. At the beginning of an async import capture the intended target ID; do not replace whichever layer happens to be selected at completion.
- [ ] Add targeted editing tests: partial marquee intersection (including rotated stored frames), stable layer reordering with multiple selection, Option duplication, structural undo/redo, add vs replace routing and preservation of old source on Undo. Use private NSPasteboard instances for actual AppKit image representation tests. Do not synthesize a fake DOM/event dispatcher.
- [ ] Implement a shared renderer with aspect-fit transform and top-left coordinates. Draw image placeholders for missing assets. Retain stored rotation/corners/opacity, even though advanced handles wait for Stage B. Text uses real font/spacing/line height/alignment/color. Rendering in canvas and SceneDisplayView must call the same implementation.
- [ ] Implement native selection, partial marquee, Shift selection, drag movement with Shift axis constraint, Option-drag duplication, arrows and centering. Topmost layer is the last element. Focus returns to the canvas on selecting a layer, deleting an element, committing an inspector field, or finishing text edit.
- [ ] Implement the “Добавить” dropdown with “Текст” and “Фото с устройства…”, Undo/Redo, layers list and a sidebar. No separate always-on select tool button. T arms text creation: click makes automatic-width text, drag makes fixed-width text; insert starts native NSTextView editing. Double click/Enter edits all text, newline works, Escape commits. Clear text and newly-created-empty-text behavior follows spec. Do not redraw/recreate an active NSTextView every selection update. In-field commands stay with native fields, including Cyrillic/IME input.
- [ ] Sidebar edits name, X/Y/W/H and typography (family, weight, size, color, line height, letter spacing, horizontal/vertical alignment, opacity). Group edits change only the chosen property; mixed values do not reset unrelated styles. Store all settings in the scene. Use the existing BlockTypography font behavior where appropriate without changing legacy preferences.
- [ ] Add local-file import with NSOpenPanel, real NSPasteboard image decoding (PNG/TIFF/file URLs as available), and NSDraggingDestination file drop. Explicit Add always adds. Enter/double-click an image opens a replacement picker. Clipboard with one selected image replaces; clipboard elsewhere adds. File drop on an image replaces that hit-tested target; drop elsewhere adds. Plain text clipboard inserts a text element; internal element copy has its own pasteboard type. Broken or cancelled input leaves prior content unchanged. Import copies originals through SceneStore. Error presentation is inline.
- [ ] Wire native responder commands `copy:`, `cut:`, `paste:`, `selectAll:`, `deleteBackward:`, `duplicate:` and Undo/Redo; key routing must not hijack fields. Use command menus in Task 4 for Cmd shortcuts. Support both English and Russian keyboard layouts via native equivalents and physical tool key codes where needed. Do not use a global key monitor or system permissions.
- [ ] Add system guide controls (master, separate clock toggle); draw approximations only in editor, never in overlay. Selected display geometry defaults to the main screen. Saving is atomic after committed actions and debounced during typing; flush on close. If a write fails, show an inline error and preserve in-memory edits and the last valid disk scene. `setPersistenceBlocked(_:)` disables document writes/flushes and shows an inline explanation; Task 4 uses it after a failed existing-document load so later edits cannot overwrite the corrupt original.
- [ ] Compile all new sources plus existing non-main sources and run `bash scripts/test.sh`; include UI source typecheck, model/editing evidence in report. Commit only owned files and test script. Record any native/manual checks not yet performed as pending.

## Task 4: App integration, native smoke test and delivery checklist

**Files:** Modify `Sources/AppDelegate.swift`, `Sources/Controllers/LockScreenController.swift`, `Sources/main.swift` only if diagnostics need it, `scripts/build.sh`, README/CHANGELOG; create `docs/native-editor-stage-a-verification.md`. Minimal corrections to Scene sources only when integration requires them; preserve the documented public interfaces.

**Interfaces:** Uses Task 1 store and Task 3 editor/display view unchanged, plus the adopted legacy MVC controllers. Adds store/controller properties to AppDelegate.

- [ ] Build script includes new source files exactly once. Preserve existing `--diagnose` and `--probe-space` and universal architecture option. Do not rewrite catalog or research files.
- [ ] On startup resolve/load the scene once; create an empty scene sized to the main screen only when no scene exists. If load fails, create only an in-memory editing scene and call `setPersistenceBlocked(_:)` before showing the editor; do not overwrite the bad file on later edits/close/quit. Call the new editor’s `flush()` before application termination. Retain a way to reach the legacy countdown editor from the status menu. New editor is the primary window/status-menu action.
- [ ] Main menu has a standard Edit menu with nil-target responder actions: undo Cmd+Z, redo Cmd+Shift+Z, copy/cut/paste Cmd+C/X/V, selectAll Cmd+A, duplicate Cmd+D, layer order Cmd+[ / ] and Cmd+Shift+[ / ]. Native NSTextView/NSTextField receive their normal commands rather than canvas actions when focused. Apply field input before losing focus to structural commands.
- [ ] Route committed scene changes to overlay rendering using SceneDisplayView on the selected/main screen. No editor handles or guides appear on the overlay. Preserve existing lock detection, retries, non-key input-transparent panels, hide-first cleanup, test panel and diagnostics. First-run fallback before a new scene has been saved may show the legacy countdown; once the user saves a scene (including an intentionally empty one), do not silently revert to old content. Do not attach a scene to a different external screen because it happens to be first in an array.
- [ ] Run `bash scripts/test.sh`, `bash scripts/build.sh`, and `build/TEotW.app/Contents/MacOS/TEotW --diagnose`. Resolve compile/test failures before UI checks. Only use temporary dirs/private pasteboards for automated tests.
- [ ] Provide an opt-in `--scene-directory <absolute-path>` diagnostic argument for native smoke checks, using it only when explicitly supplied; production launches use the normal application-support directory. This isolates test saves from personal app data. Open the built native application with a private temporary scene directory for a non-destructive smoke test. Check visible Add menu and inspector, T text creation, Enter/double click, typing with a text style, selection/move/Delete/Undo, file choice cancellation, and whether native menu commands reach the right responder. When file or clipboard checks cannot be completed with available UI tooling, explicitly leave them pending; do not mark synthetic tests as native verification. Do not change the user's clipboard or lock the Mac without a specifically authorized manual workflow.
- [ ] Write the exact tested build, platform and passing/pending checks in the verification document. Add a user-facing checklist for real file import, image replacement via clipboard/drop, style persistence after restart, and separate secure-lock test. README distinguishes Stage A from note/timer and advanced-transform followups.
- [ ] Self-review, commit scoped changes, and provide report paths/test evidence for final whole-branch review. No push, merge, or publishing step is authorized by this plan.
