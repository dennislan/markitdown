"""
Legacy .ppt (PowerPoint 97-2003 Binary) converter for MarkItDown.

Uses olefile to read the OLE2 Compound Document format and extracts
text from the PPT8 binary stream via UTF-16 LE scanning.
"""

import olefile
import re
from typing import BinaryIO, Any

from markitdown import DocumentConverter, StreamInfo, DocumentConverterResult


class PptConverter(DocumentConverter):
    """Converts legacy .ppt files to Markdown."""

    ACCEPTED_FILE_EXTENSIONS = {".ppt"}

    _NOISE_WORDS = frozenset(
        {
            "click",
            "edit",
            "master",
            "title",
            "styles",
            "level",
            "second",
            "third",
            "fourth",
            "fifth",
            "image",
            "textbox",
            "text box",
            "text",
            "picture",
            "rectangle",
            "line",
            "arrow",
            "connector",
            "placeholder",
            "layout",
            "serif",
            "sans-serif",
            "unicode",
            "bold",
            "italic",
            "times",
            "arial",
            "segoe",
            "calibri",
            "courier",
            "verdana",
            "trebuchet",
            "tahoma",
            "georgia",
            "impact",
            "new",
            "roman",
            "narrow",
            "black",
            "semibold",
            "monotype",
            "sorts",
            "de",
            "luxe",
            "blue",
            "pearl",
            "trade",
            "booth",
            "pic",
            "btn",
            "ctrl",
            "http",
            "www",
            "com",
            "org",
            "net",
            "jpg",
            "png",
            "gif",
            "rels",
            "xml",
            "pk",
            "content",
            "types",
            "downrev",
            "shapexml",
            "slidexml",
            "themexml",
            "drsxml",
            "slidemasters",
            "slidelayouts",
            "thememanager",
            "themes",
            "tablestyles",
            "accent",
            "back",
            "forward",
            "next",
            "previous",
            "home",
            "begin",
            "start",
            "end",
            "stop",
            "play",
            "hyperlink",
            "action",
            "sound",
            "movie",
            "embed",
            "object",
            "link",
            "ole",
            "group",
            "freeform",
            "oval",
            "autop",
            "autoshape",
            "shape",
            "auto shape",
            "best",
            "performances",
            "performance",
            "management",
            "solution",
            "solutions",
            "ibm",
            "corporation",
        }
    )

    _NOISE_PATTERNS = [
        re.compile(r"^[a-z]+ \d+$", re.IGNORECASE),
        re.compile(r"^\d{4,}$"),
        re.compile(r"^r\d+$", re.IGNORECASE),
        re.compile(r"^rect\d+$", re.IGNORECASE),
        re.compile(r"^pic\d+$", re.IGNORECASE),
        re.compile(r"^shape\d+$", re.IGNORECASE),
        re.compile(r"^\w+ \d+$", re.IGNORECASE),
    ]

    # ------------------------------------------------------------------
    # DocumentConverter interface
    # ------------------------------------------------------------------

    def accepts(
        self,
        file_stream: BinaryIO,
        stream_info: StreamInfo,
        **kwargs: Any,
    ) -> bool:
        extension = (stream_info.extension or "").lower()
        mimetype = (stream_info.mimetype or "").lower()

        if extension in self.ACCEPTED_FILE_EXTENSIONS:
            return True
        if mimetype.startswith("application/vnd.ms-powerpoint"):
            return True
        if mimetype.startswith("application/powerpoint"):
            return True
        return False

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _is_noise(text: str) -> bool:
        stripped = text.strip()
        lower = stripped.lower()

        if not lower or len(lower) < 3:
            return True

        for pattern in PptConverter._NOISE_PATTERNS:
            if pattern.match(lower):
                return True

        words = lower.split()
        meaningful = [w for w in words if w not in PptConverter._NOISE_WORDS and len(w) > 2]

        if len(words) > 2 and len(meaningful) / len(words) < 0.3:
            return True
        if len(meaningful) == 0:
            return True

        return False

    @staticmethod
    def _is_garbled(text: str) -> bool:
        rare = sum(1 for c in text if 0x3300 <= ord(c) < 0x3400)
        total = len(text)
        if total > 0 and rare / total > 0.5:
            return True
        symbols = sum(1 for c in text if c in "　、。〃〄々〆〇〈〉")
        if symbols > 5:
            return True
        return False

    def _extract_text(self, ppt_data: bytes) -> list:
        texts: list[str] = []
        try:
            utf16 = ppt_data.decode("utf-16-le", errors="ignore")
            runs = re.findall(
                r"([\x20-\x7e＀-￯一-鿿぀-ゟ゠-ヿ가-힯]{4,})",
                utf16,
            )

            for run in runs:
                words = run.split()
                meaningful = [
                    w for w in words if w.lower() not in self._NOISE_WORDS and len(w) > 2
                ]

                if len(meaningful) >= 2:
                    text = " ".join(meaningful)
                    if text not in texts and not self._is_noise(text) and not self._is_garbled(text):
                        texts.append(text)
        except Exception:
            pass

        return texts[:80]

    # ------------------------------------------------------------------
    # DocumentConverter.convert
    # ------------------------------------------------------------------

    def convert(
        self,
        file_stream: BinaryIO,
        stream_info: StreamInfo,
        **kwargs: Any,
    ) -> DocumentConverterResult:
        ole = olefile.OleFileIO(file_stream)

        # --- Title ---
        title = ""
        try:
            props = ole.getproperties("\x05SummaryInformation")
            if 2 in props and isinstance(props[2], bytes):
                title = props[2].decode("utf-8", errors="replace").strip()
            elif 7 in props and isinstance(props[7], bytes):
                title = props[7].decode("utf-8", errors="replace").strip()
        except Exception:
            pass

        if not title and stream_info.filename:
            title = stream_info.filename

        # --- Body ---
        try:
            ppt_data = ole.openstream("PowerPoint Document").read()
        except Exception as e:
            ole.close()
            raise RuntimeError(f"Cannot read PowerPoint Document stream: {e}") from e

        texts = self._extract_text(ppt_data)

        md_parts: list[str] = []
        if title and title.lower() not in ("powerpoint presentation", ""):
            md_parts.append(f"# {title}\n")

        if texts:
            md_parts.append("\n\n".join(f"## Slide {i+1}\n\n{text}" for i, text in enumerate(texts)))
        else:
            md_parts.append("*No text content could be extracted from this presentation.*\n")

        md_content = "\n".join(md_parts)
        ole.close()
        return DocumentConverterResult(md_content, title=title or None)
