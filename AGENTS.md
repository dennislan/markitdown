# AGENTS.md

This file provides guidance to Codex (Codex.ai/code) when working with code in this repository.

## Project Overview

**MarkItDown** — a native macOS desktop app that wraps Microsoft's MarkItDown Python tool, letting users drag-and-drop files (PDF, Word, Excel, PowerPoint, images, audio, etc.) and convert them to Markdown with a pure SwiftUI interface. Built for macOS 13+ with Swift 5.9.

Architecture: **Swift native shell + Python subprocess bridge**. The Swift UI layer manages file lists, conversion config, and progress. The Python conversion kernel is invoked as a subprocess pointing at a local virtual environment (`markitdown-env/`) containing `markitdown[all]` and its dependencies.

## Key Directories

```
MarkItDown/                    # Swift source root
├── MarkItDownApp.swift        # @main entry point, WindowGroup + Settings scene
├── ContentView.swift          # Main UI: toolbar, DropZoneView, FileListView, bottom bar
├── MarkItDownCommands.swift   # macOS menu commands (⌘O, ⌘⇧O, ⌘Return, ⌘Delete)
├── Views/
│   ├── DropZoneView.swift     # Drag-and-drop zone with NSItemProvider handling
│   ├── FileListView.swift     # List of FileItem rows
│   ├── FileListRow.swift      # Individual file row: icon, status, hover actions
│   ├── PreviewSheet.swift     # WKWebView-based Markdown preview (simple regex renderer)
│   └── SettingsView.swift     # macOS Settings scene (general + advanced tabs)
├── ViewModels/
│   └── ConversionViewModel.swift   # @ObservableObject: file management, conversion orchestration, output strategy
├── Models/
│   ├── FileItem.swift            # File metadata + conversion state
│   ├── ConversionStatus.swift    # Enum: pending/converting/completed/failed
│   └── OutputStrategy.swift      # Enum: sameDirectory/customDirectory/customDirectoryPreserveStructure
├── Services/
│   ├── ConversionScheduler.swift # actor: TaskGroup-based concurrent conversion with AsyncSemaphore
│   ├── MarkItDownProxy.swift     # Spawns python3 -c "..." subprocess with markitdown import
│   ├── FileManagerService.swift  # Supported extensions, UTType, directory scanning, output URL resolution
│   └── NotificationService.swift # UNUserNotificationCenter wrapper
├── Utilities/
│   ├── AsyncSemaphore.swift      # Custom async semaphore for concurrency limiting
│   └── KeychainHelper.swift      # Security framework wrapper for Keychain read/write/delete
├── Resources/
│   ├── Assets.xcassets/
│   └── MarkItDown.entitlements   # App sandbox disabled, user-selected file read-write
└── Info.plist                   # Document type registrations for common file formats
```

## Core Architecture

### Conversion Flow
1. User drops files/folders → `DropZoneView.handleDrop()` extracts URLs
2. `ConversionViewModel.addFilesFromURLs()` filters by supported extensions, deduplicates
3. User clicks "全部转换" → `ConversionViewModel.startConversion()` builds `ConversionConfig`
4. `ConversionScheduler` (actor) spawns a `TaskGroup` with `AsyncSemaphore`-limited concurrency
5. Each task calls `MarkItDownProxy.convertFile()` → spawns `python3 -c "..."` subprocess
6. Python script imports `markitdown`, calls `md.convert()`, writes stdout
7. Status updates flow back via callback → `@Published` properties drive SwiftUI refresh

### Python Bridge ([MarkItDownProxy](MarkItDown/Services/MarkItDownProxy.swift))
Hardcoded path to `/Users/dennis/AIProjects/markitdown/markitdown-env` (local venv with Python 3.14). The proxy constructs inline Python scripts that `sys.path.insert()` the site-packages, import `markitdown.MarkItDown`, and call `.convert()`. Output is captured from subprocess stdout; errors from stderr.

### Output Strategies ([OutputStrategy](MarkItDown/Models/OutputStrategy.swift))
- `sameDirectory` — `.md` next to source file
- `customDirectory` — all `.md` in one selected folder
- `customDirectoryPreserveStructure` — rebuild relative directory tree in output

## Build & Run

This is an Xcode project. Build and run from Xcode:

```bash
# Open the project
open MarkItDown.xcodeproj

# Or via xcodebuild (requires proper signing setup)
xcodebuild build -project MarkItDown.xcodeproj -target MarkItDown
```

The Python virtual environment at `markitdown-env/` must exist with `markitdown[all]` installed. A helper script demonstrates usage:

```bash
# conv.sh — activate venv and run markitdown CLI directly
source markitdown-env/bin/activate
markitdown ~/path/to/file.pdf -o output.md
```

## Key Patterns & Conventions

- **UI State**: `@ObservedObject` (ViewModel) + `@Published` properties drive SwiftUI views. All UI updates happen on `@MainActor`.
- **Concurrency**: `ConversionScheduler` is an `actor`. File conversion tasks use `withTaskGroup(of: Void.self)` with a custom `AsyncSemaphore` for concurrency limiting (default 4, configurable 1-8).
- **File I/O**: `FileManagerService` handles directory enumeration, UTType filtering, output URL resolution, and Markdown file writing.
- **Settings Persistence**: `@AppStorage` for simple values (concurrency, strategy, toggles). `UserDefaults.standard` for URL persistence. `KeychainHelper` for sensitive data (API keys).
- **Preview Rendering**: `PreviewSheet` uses a simple regex-based Markdown-to-HTML converter in a `WKWebView`. Not a full parser — handles headings, bold, italic, code, links, blockquotes, lists.
- **No App Sandbox**: Entitlements disable sandbox (`com.apple.security.app-sandbox: false`) for easier file access during development.
- **Hardcoded paths**: `MarkItDownProxy.init()` has a hardcoded path to the local venv. This should be parameterized for distribution.

## Common Tasks

### Adding a new file format
1. Add extension to `FileManagerService.supportedExtensions` set
2. Optionally add a case to `FileListRow.formatIcon` switch for the SF Symbol icon

### Modifying conversion behavior
Edit `MarkItDownProxy._runConvert()` — this is where the Python script is constructed. Changes here affect all conversions.

### Adding a new UI view
Follow the existing pattern: SwiftUI struct, accept `@ObservedObject var viewModel: ConversionViewModel` or `let file: FileItem` as parameters, use system semantic colors and `.regularMaterial` backgrounds.

### Testing the Python bridge manually
```bash
cd /Users/dennis/AIProjects/markitdown
source markitdown-env/bin/activate
markitdown test-file.pdf -o test-output.md
```

## Not Currently Present

- No unit tests or XCTest configuration
- No CI/CD pipeline
- No signing/notarization scripts (mentioned in PRD as V1.0 release requirements)
- No app icon configured in Assets (AppIcon placeholder exists)
- The `markitdown-env/` directory is gitignored — needs to be set up externally
