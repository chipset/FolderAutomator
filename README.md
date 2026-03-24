# FolderAutomator

FolderAutomator is an open source macOS file automation app inspired by Hazel. It includes:

- A native menu bar runner that watches folders and executes rules.
- A separate native settings app for editing watched folders, conditions, actions, and general preferences.
- A native Xcode project that builds signed local `.app` bundles.
- Persistent JSON-backed configuration in `~/Library/Application Support/FolderAutomator`.
- Launch-at-login support through an embedded `SMAppService` login helper, with a LaunchAgent fallback for non-bundled runs.

## Main features

- Watch one or more folders recursively.
- Match files by name, extension, source folder, size, age, Finder tags, common media/file-type booleans, Uniform Type identifiers, file contents, content regexes, filename dates, image dimensions, archive entry names, duplicate filenames, and duplicate file hashes within a watched tree.
- Build nested condition groups with all/any matching, plus per-rule stop-after-match and run-once behavior.
- Move, copy, rename, tag, trash, reveal in Finder, sort into subfolders, append dates, notify, open with the default app, or run a shell script on matching files.
- Keep an activity log in the runner app with search and reversible-operation history.
- Pick watched folders and destination folders with native macOS open panels, plus drag-and-drop folder setup in the settings app.
- Preview rules against a chosen file without changing anything.
- Track previously matched files to avoid repeated actions on unchanged files.
- Persist folder bookmarks for more reliable future access.
- Import and export configuration as JSON from the settings app.
- Undo reversible move, copy, rename, trash, and Finder-tag actions.

## Run

### SwiftPM

```bash
swift run FolderAutomatorSettingsApp
```

In another terminal:

```bash
swift run FolderAutomatorApp
```

The settings app writes configuration shared by the runner.

### Xcode

Open [FolderAutomator.xcodeproj](./FolderAutomator.xcodeproj) in Xcode and build either `FolderAutomatorApp` or `FolderAutomatorSettingsApp`.

From the command line:

```bash
xcodebuild -project FolderAutomator.xcodeproj -scheme FolderAutomatorApp -configuration Debug -derivedDataPath .xcode-derived build
xcodebuild -project FolderAutomator.xcodeproj -scheme FolderAutomatorSettingsApp -configuration Debug -derivedDataPath .xcode-derived build
```

App bundle outputs:

- `.xcode-derived/Build/Products/Debug/FolderAutomatorApp.app`
- `.xcode-derived/Build/Products/Debug/FolderAutomatorSettingsApp.app`
- `.xcode-derived/Build/Products/Debug/FolderAutomatorSettingsApp.app/Contents/Library/LoginItems/FolderAutomatorLoginHelper.app`

## Test

```bash
swift test
xcodebuild -project FolderAutomator.xcodeproj -scheme FolderAutomatorApp -configuration Debug -derivedDataPath .xcode-derived build
xcodebuild -project FolderAutomator.xcodeproj -scheme FolderAutomatorSettingsApp -configuration Debug -derivedDataPath .xcode-derived build
```

## Package

```bash
chmod +x ./scripts/package-apps.sh
./scripts/package-apps.sh
```

See [RELEASE.md](./RELEASE.md) for release and notarization notes.
