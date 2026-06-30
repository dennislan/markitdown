# MarkItDown

A native macOS app that converts files to Markdown. Built with SwiftUI, powered by [Microsoft MarkItDown](https://github.com/microsoft/markitdown).

Drag in your PDFs, Word docs, Excel spreadsheets, PowerPoint presentations, images, audio files, and more — get clean Markdown out.

## Features

- **Drag & drop** — drop files or folders directly into the app window
- **Batch conversion** — convert dozens of files in parallel with configurable concurrency (1–8 tasks)
- **14+ formats** — PDF, DOCX, XLSX, PPTX, HTML, CSV, JSON, XML, images, audio, EPub, ZIP, and more
- **Native macOS experience** — SwiftUI interface with vibrancy materials, dark mode, SF Symbols, and system dialogs
- **Flexible output** — save Markdown next to the source file, or to a custom directory with optional directory structure preservation
- **Markdown preview** — built-in preview sheet for converted files
- **LLM image description** — optional GPT-4o integration for image content analysis
- **Keychain security** — API keys stored in macOS Keychain, never in plaintext

## Supported Formats

| Category | Formats |
|----------|---------|
| Documents | PDF, Word (.docx), PowerPoint (.pptx) |
| Spreadsheets | Excel (.xlsx), CSV |
| Data | JSON, XML |
| Web | HTML |
| Images | JPEG, PNG, GIF, BMP, TIFF |
| Audio | WAV, MP3 (requires `[audio-transcription]`) |
| E-books | EPub |
| Archives | ZIP (converts each contained file) |
| Email | Outlook (.msg, .eml, requires `[outlook]`) |

## Requirements

- macOS 13 Ventura or later
- Python 3.10+ with `markitdown[all]` installed (in a virtual environment)

## Setup

1. Clone the repository
2. Create and activate a Python virtual environment with MarkItDown:

```bash
python3 -m venv markitdown-env
source markitdown-env/bin/activate
pip install "markitdown[all]"
```

3. Open the Xcode project and run:

```bash
open MarkItDown.xcodeproj
```

> **Note:** The Python bridge currently uses a hardcoded path to `markitdown-env/`. Adjust `MarkItDownProxy.swift` if your venv is located elsewhere.

## Architecture

```
Swift UI (SwiftUI + AppKit)
  ├── ContentView          — main window layout
  ├── DropZoneView         — drag-and-drop file import
  ├── FileListView/Row     — file list with status and actions
  ├── SettingsView         — preferences (concurrency, output, LLM config)
  │
  ├── ConversionViewModel  — state management, conversion orchestration
  ├── ConversionScheduler  — actor: TaskGroup-based parallel conversion
  ├── MarkItDownProxy      — spawns Python subprocess for each conversion
  ├── FileManagerService   — file scanning, UTType filtering, output resolution
  │
  └── Python (markitdown)  — subprocess bridge, runs in local venv
```

### Conversion Flow

1. User drops files → `DropZoneView` extracts URLs
2. `ConversionViewModel` filters by supported extensions, deduplicates
3. User clicks "全部转换" → `ConversionScheduler` spawns a `TaskGroup`
4. Each task calls `MarkItDownProxy.convertFile()` → launches `python3 -c "..."` subprocess
5. Python imports `markitdown`, calls `md.convert()`, writes result to stdout
6. Swift reads stdout, writes `.md` file, updates UI via `@Published` properties

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `⌘ O` | Open file picker |
| `⌘ ⇧ O` | Open folder picker |
| `⌘ Return` | Start conversion |
| `⌘ Delete` | Clear file list |
| `⌘ ,` | Open settings |

## License

This project wraps [Microsoft MarkItDown](https://github.com/microsoft/markitdown), which is licensed under the MIT License.
