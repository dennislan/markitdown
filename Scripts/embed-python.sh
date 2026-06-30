#!/bin/bash
# embed-python.sh — Bundle Python framework + markitdown venv into app Resources
#
# This script runs as an Xcode build phase. It copies the homebrew Python 3.14
# framework and the markitdown virtual environment into the app bundle so that
# the app is fully self-contained (no system Python required).
#
# Output structure inside the app bundle:
#   Contents/Resources/python/
#     ├── Frameworks/Python.framework/      (from homebrew)
#     └── markitdown-env/                   (venv with markitdown[all])

set -eo pipefail

# ── Locate sources ────────────────────────────────────────────────────────
PYTHON_FRAMEWORK_CELLAR=""
for d in /opt/homebrew/Cellar/python@3.14/*/Frameworks/Python.framework; do
    if [ -d "$d" ]; then
        PYTHON_FRAMEWORK_CELLAR="$(dirname "$(dirname "$d")")"
        break
    fi
done

if [ -z "$PYTHON_FRAMEWORK_CELLAR" ]; then
    echo "❌ ERROR: python@3.14 Framework not found under /opt/homebrew/Cellar/python@3.14/"
    echo "   Install it: brew install python@3.14"
    exit 1
fi

# Resolve PROJECT_DIR from script location if not set by Xcode
PROJECT_DIR="${PROJECT_DIR:-}"
if [ -z "$PROJECT_DIR" ]; then
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
fi
VENV_SRC="${PROJECT_DIR}/markitdown-env"
if [ ! -d "$VENV_SRC" ]; then
    echo "❌ ERROR: markitdown-env not found at $VENV_SRC"
    exit 1
fi

# ── Destination ───────────────────────────────────────────────────────────
BUILT_PRODUCTS_DIR="${BUILT_PRODUCTS_DIR:-}"
PRODUCT_NAME="${PRODUCT_NAME:-MarkItDown}"
if [ -z "$BUILT_PRODUCTS_DIR" ]; then
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
    BUILT_PRODUCTS_DIR="${PROJECT_DIR}/build/Debug"
fi
RESOURCES_DIR="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Resources"
PYTHON_DIR="${RESOURCES_DIR}/python"

echo "🐍 Embedding Python environment into app bundle…"
echo "   Framework source : $PYTHON_FRAMEWORK_CELLAR"
echo "   Venv source      : $VENV_SRC"
echo "   Destination      : $PYTHON_DIR"

# Clean previous embed
rm -rf "$PYTHON_DIR"
mkdir -p "${PYTHON_DIR}/Frameworks"
mkdir -p "$PYTHON_DIR/markitdown-env"

# ── 1. Copy Python.framework ─────────────────────────────────────────────
FRAMEWORK_DST="${PYTHON_DIR}/Frameworks/Python.framework"
echo "📦 Copying Python.framework…"
cp -R "$PYTHON_FRAMEWORK_CELLAR/Frameworks/Python.framework" "$FRAMEWORK_DST"

# Remove unnecessary files from framework to shrink bundle
echo "✂️  Pruning Python.framework (removing docs, static libs, tests)…"
rm -rf "${FRAMEWORK_DST}/Resources/doc"
rm -rf "${FRAMEWORK_DST}/Resources/Documentation"
find "${FRAMEWORK_DST}" -name "*.a" -delete 2>/dev/null || true
find "${FRAMEWORK_DST}" -name "*.py" -delete 2>/dev/null || true

# ── 2. Copy venv ─────────────────────────────────────────────────────────
VENV_DST="${PYTHON_DIR}/markitdown-env"
echo "📦 Copying markitdown venv…"
# Copy contents of the venv directory (not the directory itself)
cp -R "${VENV_SRC}/." "$VENV_DST"

# ── 3. Fix symlinks ──────────────────────────────────────────────────────
# The venv's bin/python3.14 symlinks to the homebrew absolute path.
# Rewrite it to a relative path pointing into our bundled Framework.

VENV_BIN="${VENV_DST}/bin"
FRAMEWORK_VERSIONS_PATH="../../Frameworks/Python.framework/Versions/3.14"

# Rewrite python3.14 symlink
rm -f "${VENV_BIN}/python3.14"
ln -sf "${FRAMEWORK_VERSIONS_PATH}/bin/python3.14" "${VENV_BIN}/python3.14"

# Ensure python3 symlink points to python3.14
rm -f "${VENV_BIN}/python3"
ln -sf "python3.14" "${VENV_BIN}/python3"

# Fix shebangs in venv scripts (markitdown, magika, etc.)
echo "🔧 Fixing shebangs in venv scripts…"
FRAMEWORK_PYTHON="${FRAMEWORK_VERSIONS_PATH}/bin/python3.14"
for script in "${VENV_BIN}"/*; do
    if [ -f "$script" ] && [ ! -L "$script" ]; then
        # Replace absolute homebrew path in shebang with relative path
        sed -i '' "s|^#!${PYTHON_FRAMEWORK_CELLAR}/Frameworks/Python.framework/.*|#!${FRAMEWORK_PYTHON}|" "$script" 2>/dev/null || true
        # Also handle /opt/homebrew/opt/python@3.14/ paths
        sed -i '' "s|^#!${PYTHON_FRAMEWORK_CELLAR}/opt/.*|#!${FRAMEWORK_PYTHON}|" "$script" 2>/dev/null || true
    fi
done

# ── 4. Clean up cache & unnecessary files ─────────────────────────────────
echo "🧹 Cleaning cache files…"
find "${PYTHON_DIR}" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find "${PYTHON_DIR}" -name "*.pyc" -delete 2>/dev/null || true
find "${PYTHON_DIR}" -name "*.pyo" -delete 2>/dev/null || true

# Remove pip's build artifacts (small savings)
find "${PYTHON_DIR}" -name "pip*" -type d -path "*/site-packages/*" -exec rm -rf {} + 2>/dev/null || true

# ── 5. Summary ────────────────────────────────────────────────────────────
BUNDLE_SIZE=$(du -sk "${PYTHON_DIR}" 2>/dev/null | awk '{print $1}')
echo "✅ Python environment embedded (${BUNDLE_SIZE} KB)"
echo "   Python binary: ${VENV_DST}/bin/python3.14"
echo "   Site packages: ${VENV_DST}/lib/python3.14/site-packages"

# Verify the binary works
if "${VENV_DST}/bin/python3.14" -c "import markitdown; print('markitdown', markitdown.__version__)" >/dev/null 2>&1; then
    echo "✅ Embedded Python + markitdown verified OK"
else
    echo "⚠️  WARNING: Embedded Python cannot import markitdown"
fi

# ── 6. Create output marker for Xcode dependency tracking ───────────────────
# This file serves as the output dependency for the build phase, so Xcode
# knows when the script needs to rerun.
MARKER="${BUILT_PRODUCTS_DIR}/${PRODUCT_NAME}.app/Contents/Resources/.python_embedded"
touch "$MARKER" 2>/dev/null || true
