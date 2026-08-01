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
- Python 3.14 (Homebrew: `brew install python@3.14`) with `markitdown[all]` installed in a virtual environment

## Setup

1. Clone the repository
2. Create and activate a Python virtual environment with MarkItDown:

```bash
python3 -m venv markitdown-env
source markitdown-env/bin/activate
pip install "markitdown[all]"
```

> PDF 字体编码损坏（如缺失 ToUnicode/cmap 导致输出 `(cid:0)` 乱码）时，app 会通过 macOS 原生 Vision 框架（PDFKit 渲染 + `VNRecognizeTextRequest`，中英双语）在本地做 OCR 兜底，无需任何额外 Python 依赖。

3. Open the Xcode project and run:

```bash
open MarkItDown.xcodeproj
```

> **Self-contained runtime:** the "Embed Python Runtime" Xcode build phase copies the Python framework and `markitdown-env` into the app bundle (`Contents/Resources/python/`) and relocates every dylib reference to `@loader_path`, so the built app runs standalone without Homebrew or the dev machine's venv. The embed is incremental — it only re-runs when the venv or framework changes. For a distributable release build, use `./build_release.sh`.

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
  └── Python (markitdown)  — subprocess bridge, runs from the app-embedded runtime
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
