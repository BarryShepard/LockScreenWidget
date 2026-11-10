# Native editor Stage A verification

## Tested build

- Date: 10 November 2026.
- Source: `03e28062b0bd386b58809160337d84b4556407a9` (`codex/personal-lockscreen-editor`). Documentation-only commits after this revision do not change the executable.
- Artifact: `build/TEotW.app/Contents/MacOS/TEotW`, universal `x86_64 arm64`, bundle version remains the development base `0.4.0 (4)`.
- Executable SHA-256: `bd697a0d2de7c4fbcde23c0738587d774f6a383c8cec7a25407828c858e219df`.
- Host: macOS 15.7.3 (24G419), Apple Silicon arm64; Apple Swift 6.1.2, Swift 5 language mode, deployment target macOS 15.0.

## Completed automated checks

- Combined scene/legacy/AppDelegate typecheck passed.
- `bash scripts/test.sh` passed CoreTests, SettingsTests, LayoutTests (348 overlay layouts), LockScreenControllerTests and SceneTests. The sandbox run then stopped in SceneEditingTests because the real private pasteboard service rejected its file-URL write. The unchanged `build/SceneEditingTests` executable passed with narrow host access to that service. These runs jointly cover all six suites; the sandbox script itself did not finish successfully.
- Integration regressions cover first-run non-persistence; saved empty scene loading; in-memory editing, flush and close without overwriting a corrupt document; unavailable directory recovery; absolute diagnostic directory parsing; nil-target Edit actions; launch-display identity matching despite reordered or missing displays; countdown-to-scene panel replacement; live scene updates; intentionally empty scene rendering; non-key input-transparent panels; hide/restore/defer/discard behavior for both editor generations.
- Existing production `showPreview()` first-open assertions remain. The new production `showEditor()` window creation and panel-test restoration are exercised too. These tests create transient test windows, with no interactive input or production app launch.
- `bash scripts/build.sh` and `bash scripts/build.sh --universal` passed. The latter produced the artifact above. `lipo -archs` reports both architectures; `codesign --verify --deep --strict` passed.
- `build/TEotW.app/Contents/MacOS/TEotW --diagnose` passed: 58 events, 19 countdowns, 39 period cards, system bold font and next-event output. `--probe-space` was preserved without changes and was not rerun during this task.

All automated image fixtures use temporary directories. Pasteboard tests use unique private boards; no test reads or writes the general clipboard. The integration implementation work did not open the interactive production application, write personal scene data or lock the Mac.

## Native verification status

The separate `SceneEditorSmoke.app` harness was reported to pass T creation, Cyrillic typing and newlines, Enter editing, Delete/Undo, PNG picker import/cancel, X/Y/font changes, clock guide toggle and quit/relaunch with text/photo/font size 48 persisted. That harness exercised the editor components before production integration. It does **not** prove AppDelegate startup, status-menu wiring, the production Edit menu, overlay routing or production termination handling.

Production native smoke on the exact artifact above is pending the main controller's separate visible check. Compilation, direct responder calls and private-board tests are not marked as native end-to-end verification. The historical successful secure-lock countdown check in version 0.1.0 also does not verify the new scene renderer on a secure lock screen.

## Isolated native acceptance checklist

Use a disposable scene directory. Production launches without `--scene-directory` use `~/Library/Application Support/LockScreenWidget`; this argument is opt-in and must be an absolute path.

```sh
scene_directory="$(mktemp -d /private/tmp/TEotW-scene.XXXXXX)"
open -n build/TEotW.app --args --scene-directory "$scene_directory"
```

- [ ] The first window is the personal screen editor. Its visible Add menu, inspector and layer list work. Close/reopen through the status menu; open the legacy countdown editor through both available actions.
- [ ] Press T, click and type Cyrillic text. Create a fixed-width block by dragging. Use Enter/double click to edit, Enter for a newline and Escape to finish. Change font/size/color and confirm the result.
- [ ] Select, Shift-select and move layers. Test arrows, Delete, Undo/Redo, duplicate and each layer-order menu command.
- [ ] While text is focused, verify Command-A and Undo act on text. While a numeric field is focused, edit/select/copy/paste its contents and commit with Enter. Click a structural toolbar action after changing a field; the field value must be applied first. Only use clipboard content explicitly chosen for this manual check.
- [ ] Import a real image through the system file picker, then cancel another picker and confirm that nothing changes. Move or remove the original file and verify that the saved document still uses its local copy.
- [ ] With exactly one photo selected, replace it from an explicitly chosen clipboard image. Check geometry and layer order, then Undo. Drop another real image onto a photo to replace it and onto empty canvas to add a layer. Check cancellation and errors without losing the existing image.
- [ ] Quit normally and relaunch with the same private directory. Verify text, photo, geometry and font style. Delete every layer, quit/relaunch and confirm the saved scene stays empty.
- [ ] Use the eight-second transparent panel test. Confirm scene content and absence of handles/guides; both visible editors hide and restore. Verify the enabled menu and quit cleanup.
- [ ] On multiple displays, reorder displays and disconnect the launch target. The scene must not migrate to a different display; reconnect the original display and recheck. Automated identity matching is not a physical hot-plug test.

## Separate secure-lock check

This requires the user's authorized manual workflow. No automated task locks the Mac.

- [ ] With a known private scene open, enable display on lock, then manually lock with Control-Command-Q. Confirm the actual scene appears on the chosen display and system authentication remains usable. Editor guides and selection must be absent.
- [ ] Unlock normally; confirm the elevated panel disappears. Repeat with a saved empty scene, disabled display and quit cleanup.
- [ ] Separately check sleep/wake, an interrupted panel test and multiple displays on the actual target system.

Notes/timers and mouse-driven resize, crop and rotation remain outside Stage A. Asset copies are append-only for Undo safety; the current app does not perform asset garbage collection.
