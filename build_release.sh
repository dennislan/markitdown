#!/usr/bin/env bash
# build_release.sh — One-click Release build for MarkItDown
# Usage: ./build_release.sh
#
# Prerequisites:
#   - Xcode command-line tools installed (xcode-select --install)
#   - Python 3.14 homebrew framework (brew install python@3.14)
#   - markitdown-env/ Python venv present alongside this project
#   - (Optional) Valid signing identity for notarization

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="${SCRIPT_DIR}/MarkItDown.xcodeproj"
SCHEME="MarkItDown"
CONFIGURATION="Release"
BUILD_DIR="${SCRIPT_DIR}/build"
APP_NAME="MarkItDown.app"

# ── colours ────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

# ── preflight checks ───────────────────────────────────────────────
info "Checking prerequisites…"

if ! command -v xcodebuild &>/dev/null; then
  error "xcodebuild not found. Install Xcode command-line tools."
  exit 1
fi

if [[ ! -d "${PROJECT}" ]]; then
  error "Project not found at ${PROJECT}"
  exit 1
fi

if [[ ! -d "${SCRIPT_DIR}/markitdown-env" ]]; then
  error "markitdown-env/ not found at ${SCRIPT_DIR}/markitdown-env"
  exit 1
fi

# ── Step 1: Xcode build ────────────────────────────────────────────
info "Building ${SCHEME} (${CONFIGURATION})…"

xcodebuild clean build \
  -project "${PROJECT}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "${BUILD_DIR}/DerivedData" \
  BUILD_DIR="${BUILD_DIR}" \
  ONLY_ACTIVE_ARCH=NO \
  2>&1 | tee "${BUILD_DIR}/build.log"

if grep -q "BUILD SUCCEEDED" "${BUILD_DIR}/build.log"; then
  success "Build succeeded!"
else
  error "Build failed. See ${BUILD_DIR}/build.log"
  exit 1
fi

RELEASE_APP="${BUILD_DIR}/${CONFIGURATION}/${APP_NAME}"

if [[ ! -d "${RELEASE_APP}" ]]; then
  error "Expected app not found at ${RELEASE_APP}"
  info "Searching build output directory…"
  find "${BUILD_DIR}" -name "${APP_NAME}" -type d 2>/dev/null | head -5
  exit 1
fi

# ── Step 2: Embed Python into the built app bundle ──────────────────
info "Embedding Python runtime into app bundle…"

# Point embed-python.sh at the exact Release .app output
BUILT_PRODUCTS_DIR="${BUILD_DIR}/${CONFIGURATION}" \
PRODUCT_NAME="${APP_NAME%.app}" \
SRCROOT="${SCRIPT_DIR}" \
bash "${SCRIPT_DIR}/Scripts/embed-python.sh"

success "Python runtime embedded."

# ── Step 3: Verify ──────────────────────────────────────────────────
EMBEDDED_PYTHON="${RELEASE_APP}/Contents/Resources/python/markitdown-env/bin/python3"
if [[ -f "${EMBEDDED_PYTHON}" ]]; then
  success "Embedded Python verified inside app bundle: ${EMBEDDED_PYTHON}"
else
  warn "Embedded Python binary not found at ${EMBEDDED_PYTHON} — app may not run standalone."
fi

open "${RELEASE_APP}"
info "Opened in Finder."
