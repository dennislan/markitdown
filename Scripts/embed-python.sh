#!/bin/bash
# embed-python.sh — Bundle Python framework + markitdown venv into app Resources
#
# This script runs as an Xcode build phase (or standalone via build_release.sh).
# It copies the homebrew Python framework and the markitdown virtual environment
# into the app bundle so that the app is fully self-contained (no system Python
# required, no dependency on a specific homebrew Cellar version).
#
# Output structure inside the app bundle:
#   Contents/Resources/python/
#     ├── Frameworks/Python.framework/      (from homebrew, fully relocatable)
#     │     └── Versions/3.14/lib/deps/     (homebrew dylibs needed by stdlib C extensions)
#     └── markitdown-env/                   (venv with markitdown[all])
#
# WHY this file exists: homebrew Python.framework binaries reference absolute
# paths into the Cellar (e.g. /opt/homebrew/Cellar/python@3.14/<ver>/...).
# When homebrew upgrades python (3.14.5 → 3.14.6) the old path disappears and
# the embedded python dies with "Library not loaded: ..." (dyld error, exit 6).
# This script relocates every Mach-O dylib reference to @executable_path and
# bundles the required homebrew libraries, making the copy truly standalone.

set -eo pipefail

# ── Locate sources ────────────────────────────────────────────────────────
PYTHON_VERSION="3.14"
PYTHON_FRAMEWORK_CELLAR=""
for d in /opt/homebrew/Cellar/python@${PYTHON_VERSION}/*/Frameworks/Python.framework; do
    if [ -d "$d" ]; then
        PYTHON_FRAMEWORK_CELLAR="$(dirname "$(dirname "$d")")"
        break
    fi
done

if [ -z "$PYTHON_FRAMEWORK_CELLAR" ]; then
    echo "❌ ERROR: python@${PYTHON_VERSION} Framework not found under /opt/homebrew/Cellar/python@${PYTHON_VERSION}/"
    echo "   Install it: brew install python@${PYTHON_VERSION}"
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

# ── Fast path: already embedded and up-to-date? ────────────────────────────
# Skips the slow full embed when nothing changed. Invalidation sources are the
# venv's site-packages (pip installs) and the homebrew framework version dir
# (brew upgrades); the marker is written at the end of a successful run.
MARKER="${RESOURCES_DIR}/.python_embedded"
SITE_PACKAGES_DIR="${VENV_SRC}/lib/python${PYTHON_VERSION}/site-packages"
if [ -f "$MARKER" ] && [ "$MARKER" -nt "$SITE_PACKAGES_DIR" ] && [ "$MARKER" -nt "$PYTHON_FRAMEWORK_CELLAR" ]; then
    echo "⏭️  Python runtime already embedded and up-to-date — skipping."
    exit 0
fi

# Clean previous embed
rm -rf "$PYTHON_DIR"
mkdir -p "${PYTHON_DIR}/Frameworks"
mkdir -p "$PYTHON_DIR/markitdown-env"

# ── 1. Copy Python.framework ─────────────────────────────────────────────
FRAMEWORK_DST="${PYTHON_DIR}/Frameworks/Python.framework"
FRAMEWORK_VERSIONS_DIR="${FRAMEWORK_DST}/Versions/${PYTHON_VERSION}"
echo "📦 Copying Python.framework…"
cp -R "$PYTHON_FRAMEWORK_CELLAR/Frameworks/Python.framework" "$FRAMEWORK_DST"

# Remove only clearly-useless files from the framework.
# ⚠️  Do NOT delete *.py — the stdlib lives here and python NEEDS it.
echo "✂️  Pruning Python.framework (docs, static libs, pyc only)…"
rm -rf "${FRAMEWORK_DST}/Resources/doc"
rm -rf "${FRAMEWORK_DST}/Resources/Documentation"
find "${FRAMEWORK_DST}" -name "*.a" -delete 2>/dev/null || true
find "${FRAMEWORK_DST}" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find "${FRAMEWORK_DST}" -name "*.pyc" -delete 2>/dev/null || true
find "${FRAMEWORK_DST}" -name "*.pyo" -delete 2>/dev/null || true

# ── 2. Copy venv ─────────────────────────────────────────────────────────
VENV_DST="${PYTHON_DIR}/markitdown-env"
echo "📦 Copying markitdown venv…"
# Copy contents of the venv directory (not the directory itself)
cp -R "${VENV_SRC}/." "$VENV_DST"

# ⚠️  Do NOT delete *.py under PYTHON_DIR — site-packages is all .py!

# ── 3. Bundle homebrew dylibs required by stdlib C extensions ────────────
# lib-dynload/_ssl, _hashlib, _sqlite3, _lzma, _decimal, _zstd link against
# homebrew kegs. Copy those dylibs next to the framework so the app works even
# if homebrew is upgraded or absent.
DEPS_DIR="${FRAMEWORK_VERSIONS_DIR}/lib/deps"
mkdir -p "$DEPS_DIR"
DEPS_SOURCES=(
    "/opt/homebrew/opt/mpdecimal/lib/libmpdec.4.dylib"
    "/opt/homebrew/opt/openssl@3/lib/libssl.3.dylib"
    "/opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib"
    "/opt/homebrew/opt/xz/lib/liblzma.5.dylib"
    "/opt/homebrew/opt/sqlite/lib/libsqlite3.dylib"
    "/opt/homebrew/opt/zstd/lib/libzstd.1.dylib"
)
echo "📦 Bundling homebrew dylibs into ${DEPS_DIR#"$PYTHON_DIR"/}…"
for src in "${DEPS_SOURCES[@]}"; do
    if [ -f "$src" ]; then
        cp -L "$src" "$DEPS_DIR/"   # -L follows symlinks (sqlite/mpdecimal/zstd are links)
        echo "   + $(basename "$src")"
    else
        echo "   ⚠️  missing dependency source: $src"
    fi
done

# ── 4. Relocate every Mach-O dylib reference to @loader_path ─────────────
# NOTE: we must use @loader_path, NOT @executable_path. Homebrew's framework
# makes bin/python3.14 a symlink to Resources/Python.app/Contents/MacOS/Python,
# so the process executable lives several levels deep — @executable_path would
# resolve to the wrong directory. @loader_path resolves relative to *each*
# binary's own directory, which is always correct regardless of nesting.
reloc_path() {
    # $1 = absolute target, $2 = directory of the file being patched
    python3 -c "import os,sys; print('@loader_path/' + os.path.relpath(sys.argv[1], sys.argv[2]))" "$1" "$2"
}

relocate_macho() {
    local f="$1"
    local refs f_dir id
    # Fix the library's own install name if it still points at homebrew
    id=$(otool -D "$f" 2>/dev/null | tail -1)
    if [[ "$id" == /opt/homebrew/* ]]; then
        install_name_tool -id "@loader_path/$(basename "$f")" "$f" 2>/dev/null || true
    fi
    refs=$(otool -L "$f" 2>/dev/null | grep -o "/opt/homebrew/[^ ]*" | sort -u) || true
    [ -z "$refs" ] && return 0
    f_dir=$(dirname "$f")
    while IFS= read -r ref; do
        if [[ "$ref" == *"/Frameworks/Python.framework/Versions/${PYTHON_VERSION}/Python" ]]; then
            # Main Python dylib — sits at Versions/<ver>/Python
            install_name_tool -change "$ref" "$(reloc_path "${FRAMEWORK_VERSIONS_DIR}/Python" "$f_dir")" "$f" >/dev/null 2>&1 || true
        elif [ -f "${DEPS_DIR}/${ref##*/}" ]; then
            # A bundled homebrew dependency
            install_name_tool -change "$ref" "$(reloc_path "${DEPS_DIR}/${ref##*/}" "$f_dir")" "$f" >/dev/null 2>&1 || true
        else
            echo "   ⚠️  unresolved homebrew reference in ${f#"$PYTHON_DIR"/}: $ref"
        fi
    done <<< "$refs"
}

echo "🔧 Relocating dylib references (making bundle self-contained)…"
# Main framework dylib: set a relocatable install name
install_name_tool -id "@loader_path/Python" \
    "${FRAMEWORK_VERSIONS_DIR}/Python" 2>/dev/null || true

# Relocate every Mach-O file under the framework (python3.14, Python.app,
# lib-dynload/*.so, bundled deps)
while IFS= read -r -d '' f; do
    if file -b "$f" 2>/dev/null | grep -q "Mach-O 64-bit"; then
        relocate_macho "$f"
    fi
done < <(find "$FRAMEWORK_DST" -type f -print0)

# ── 5. Resign embedded Mach-O binaries ───────────────────────────────────
# install_name_tool invalidates the original ad-hoc signatures; macOS SIGKILLs
# any modified Mach-O at launch. Re-sign every Mach-O inside the bundle.
echo "🔏 Re-signing embedded Mach-O binaries…"
while IFS= read -r -d '' f; do
    if file -b "$f" 2>/dev/null | grep -q "Mach-O"; then
        codesign -f -s - "$f" 2>/dev/null || echo "   ⚠️  codesign failed: ${f#"$PYTHON_DIR"/}"
    fi
done < <(find "$PYTHON_DIR" -type f -print0)

# ── 6. Fix venv symlinks & config ────────────────────────────────────────
# The venv's bin/python3.14 symlinks to the homebrew absolute path.
# Rewrite it to a relative path pointing into our bundled Framework.
VENV_BIN="${VENV_DST}/bin"
FRAMEWORK_VERSIONS_PATH="../../Frameworks/Python.framework/Versions/${PYTHON_VERSION}"

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

# Rewrite pyvenv.cfg: home/executable must NOT point at the homebrew Cellar
# (it gets upgraded/removed). Relative paths are resolved against the venv's
# bin/ directory, which stays inside the bundle.
echo "🔧 Rewriting pyvenv.cfg to bundle-relative paths…"
cat > "${VENV_DST}/pyvenv.cfg" <<EOF
home = ../../Frameworks/Python.framework/Versions/${PYTHON_VERSION}/bin
include-system-site-packages = false
version = ${PYTHON_VERSION}
executable = ../../Frameworks/Python.framework/Versions/${PYTHON_VERSION}/bin/python3.14
EOF

# ── 6. Clean up cache & unnecessary files ────────────────────────────────
echo "🧹 Cleaning cache files…"
find "${PYTHON_DIR}" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find "${PYTHON_DIR}" -name "*.pyc" -delete 2>/dev/null || true
find "${PYTHON_DIR}" -name "*.pyo" -delete 2>/dev/null || true

# Remove pip's build artifacts (small savings)
find "${PYTHON_DIR}" -name "pip*" -type d -path "*/site-packages/*" -exec rm -rf {} + 2>/dev/null || true

# ── 7. Summary ────────────────────────────────────────────────────────────
BUNDLE_SIZE=$(du -sk "${PYTHON_DIR}" 2>/dev/null | awk '{print $1}')
echo "✅ Python environment embedded (${BUNDLE_SIZE} KB)"
echo "   Python binary: ${VENV_DST}/bin/python3.14"
echo "   Site packages: ${VENV_DST}/lib/python3.14/site-packages"

# Verify the binary works — import stdlib C extensions that pull homebrew
# dylibs plus markitdown. Must succeed with NO /opt/homebrew on the system.
if "${VENV_DST}/bin/python3.14" -c "import sys; import ssl, hashlib, sqlite3, lzma, zlib, decimal, ctypes; import markitdown; print('✅ embedded python OK', sys.version.split()[0], sys.prefix)" >/dev/null 2>&1; then
    echo "✅ Embedded Python + stdlib C-extensions + markitdown verified OK"
else
    echo "⚠️  WARNING: Embedded Python failed verification:"
    "${VENV_DST}/bin/python3.14" -c "import sys; import ssl, hashlib, sqlite3, lzma, zlib, decimal, ctypes; import markitdown" 2>&1 | tail -5 || true
fi

# ── 8. Create output marker for Xcode dependency tracking ───────────────────
# This file serves as the output dependency for the build phase, so Xcode
# knows when the script needs to rerun. It also drives the fast-path skip.
touch "$MARKER" 2>/dev/null || true
