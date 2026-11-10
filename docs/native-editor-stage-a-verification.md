# Native editor Stage A verification

## Final fixes — 10 November 2026

- Current code: `9ac681b9a57028436d9526018d7a0f33a34f281a`, following the six-finding fix commit `17d1c78`.
- Current universal executable SHA-256: `a2b94f840f0fcc0090bb8c863746ca4b4439b8c0dd5f6b67e4c846ebbe7b8886`. Build, signature, architectures and `--diagnose` passed.
- All six suites passed after the main fix wave. After the narrow IME correction, SceneEditingTests and LockScreenControllerTests passed again. Native AppKit regressions cover marked-only insertion discard, accepted text preservation, fallback, persistence and one-step Undo across finish, Escape and focus loss; canvas mouse-down is also covered in SceneEditingTests.
- Native production smoke on `17d1c78`, using an isolated temporary scene: typed Cyrillic text while the field remained active; verified debounced storage; deleted the text, pressed Escape and quit. The provisional scene file was absent after discard and termination. This smoke predates the narrow IME fix; actual input-method switching was not manually tested.
- Additional image-integrity validation is PNG-specific. Other formats retain AppKit decoding checks. An existing AppKit constraint-constant warning remains in controller tests; its origin has not been isolated.
- The manual gaps listed below remain pending. Earlier artifact hashes and visible checks below are historical evidence, not additional native checks of the final executable.

## Earlier tested build

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

All automated image fixtures use temporary directories. CLI pasteboard tests use unique private boards, not the general clipboard. The implementation test commands did not launch the interactive production app or lock the Mac. The separate visible UI checks below use an explicitly isolated scene directory.

## Native verification status

The separate `SceneEditorSmoke.app` harness was reported to pass T creation, Cyrillic typing and newlines, Enter editing, Delete/Undo, PNG picker import/cancel, X/Y/font changes, clock guide toggle and quit/relaunch with text/photo/font size 48 persisted. That harness exercised the editor components before production integration. It does **not** prove AppDelegate startup, status-menu wiring, the production Edit menu, overlay routing or production termination handling.

Production native smoke was then performed on the exact artifact above with `--scene-directory /private/tmp/lockscreen-editor-smoke-nldritem/Scene`:

- The production app opened the personal editor and loaded the saved text/photo composition, including 48 pt text. Its accessibility tree exposed the production Edit menu.
- A real mouse drag moved the photo from X=100 to X=197.548, preserving Y=500 and its 640×400 pt frame.
- A real double-click opened the replacement picker. Selecting a second generated PNG changed visible pixels while preserving the same two layers, photo name, position and frame.
- Command-Z visibly restored the original photo pixels. Command-Shift-Z re-applied replacement. This verifies native production command routing, not only direct state calls.
- Enter opened native text editing. Backspace deleted the final character of the text; Command-Z restored that character inside the field without undoing another scene action. Escape finished text input. The shortened line-height label was visible.
- The isolated production session was quit. A normal launch without the diagnostic directory then opened a clean, ordinary personal editor; test layers were not injected into the normal profile. The editor was left open without editing the personal scene.

Visible clipboard-image insertion, external file drag-and-drop, real display hot-plug, the panel test and protected-screen appearance remain pending. Compilation/direct responder tests do not replace those checks. The historical secure-lock countdown check in version 0.1.0 also does not verify the new scene renderer on a secure lock screen.

## Чеклист для проверки приложения

Для экспериментов можно использовать отдельную папку сцены. Обычный запуск без `--scene-directory` сохраняет данные в `~/Library/Application Support/LockScreenWidget`. Диагностический путь должен быть абсолютным.

```sh
scene_directory="$(mktemp -d /private/tmp/TEotW-scene.XXXXXX)"
open -n build/TEotW.app --args --scene-directory "$scene_directory"
```

Уже проверено в основной сборке:

- [x] Открывается новый редактор; сохранённая тестовая композиция загружает текст, фото и кегль 48 pt.
- [x] Перетаскивание двигает фото без изменения его размеров.
- [x] Двойной клик открывает выбор замены; новый файл меняет содержимое, сохраняя рамку и число слоёв.
- [x] Cmd+Z возвращает прежние пиксели изображения; Cmd+Shift+Z повторяет замену.
- [x] Enter включает редактирование текста; Backspace и Cmd+Z внутри текста работают с символами; Escape завершает ввод.
- [x] Запуск без тестового аргумента открывает обычный профиль без тестовых элементов.

Отдельно в нативном тестовом окне компонентов проверены T с кликом, многострочный ввод на русском, удаление слоя/Undo, импорт через «Добавить», отмена выбора файла, координаты/кегль в панели, отдельный выключатель часов и восстановление после перезапуска. Это не помечается как повторная проверка каждого сценария в основной сборке.

Для ручного прохода:

- [ ] Через «Добавить» вставить свои текст и фото. После T проверить и клик, и протягивание рамки. Двойной клик по тексту должен включать ввод; Enter внутри него — добавлять строку.
- [ ] Изменить шрифт, начертание, кегль, цвет и интервалы. В числовом поле выделение и команды ввода относятся к полю; Enter подтверждает значение. Убедиться, что незавершённый ввод не сбрасывается.
- [ ] Выделить несколько слоёв рамкой с частичным пересечением и Shift-кликами. Проверить перемещение, Option-копию, стрелки, Delete, Undo/Redo и все команды порядка слоёв.
- [ ] Импортировать фото, затем переместить исходный файл вне приложения: сцена должна пользоваться собственной копией. Отмена выбора файла и ошибка чтения сохраняют прежнее содержимое.
- [ ] Скопировать выбранное для теста изображение во внешний буфер и нажать Cmd+V на выделенном фото: должна произойти замена без нового слоя; Undo возвращает прежнее фото. Без выделенного фото вставка создаёт слой.
- [ ] Перетащить файл из Finder на фото — замена; на пустое место — новый слой. Проверить подсветку цели и сохранение рамки.
- [ ] Завершить приложение и открыть снова: все элементы и стили восстановлены. Отдельно удалить все слои и проверить, что сохранённая пустая сцена не возвращает прежний отсчёт.
- [ ] Закрыть и открыть редактор через строку меню; проверить оба способа открытия прежнего редактора отсчёта.
- [ ] Запустить восьмисекундную прозрачную панель: видна сцена без рамок выделения и ориентиров; оба редактора скрываются и затем возвращаются. Проверить отключение показа и завершение приложения.
- [ ] На нескольких дисплеях отключить выбранный при запуске экран: композиция не должна переехать на другой. Подключить его обратно и проверить восстановление. Модельный тест идентичности не заменяет физическую проверку.

## Separate secure-lock check

This requires the user's authorized manual workflow. No automated task locks the Mac.

- [ ] With a known private scene open, enable display on lock, then manually lock with Control-Command-Q. Confirm the actual scene appears on the chosen display and system authentication remains usable. Editor guides and selection must be absent.
- [ ] Unlock normally; confirm the elevated panel disappears. Repeat with a saved empty scene, disabled display and quit cleanup.
- [ ] Separately check sleep/wake, an interrupted panel test and multiple displays on the actual target system.

Notes/timers and mouse-driven resize, crop and rotation remain outside Stage A. Asset copies are append-only for Undo safety; the current app does not perform asset garbage collection.
