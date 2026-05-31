#!/bin/bash
# Build script for Ollama-Desktop with metrics display
# Uses the official Ollama.app from scripts/ directory (no external dependency).
#
# Usage: ./scripts/build_desktop.sh
#
# Prerequisites: Go 1.24+, Node.js/npm, Xcode command line tools

set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="Ollama-Desktop"
SCRIPTS_OLLAMA="scripts/Ollama.app"
SYS_OLLAMA="/Applications/Ollama.app"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

# --- Resolve backend source ---
if [ -d "$REPO_ROOT/$SCRIPTS_OLLAMA" ]; then
    BACKEND_SOURCE="$REPO_ROOT/$SCRIPTS_OLLAMA"
    info "Using bundled backend: $SCRIPTS_OLLAMA"
elif [ -d "$SYS_OLLAMA" ]; then
    BACKEND_SOURCE="$SYS_OLLAMA"
    warn "Using system backend: $SYS_OLLAMA (scripts/Ollama.app not found)"
else
    error "No Ollama.app found. Place one at scripts/Ollama.app or install at /Applications/Ollama.app"
fi

# --- Cleanup on exit: restore source files ---
cleanup() {
    rm -rf "$REPO_ROOT/dist/darwin"
    if [ -f "$REPO_ROOT/app/ui/app/index.html.bak" ]; then
        mv "$REPO_ROOT/app/ui/app/index.html.bak" "$REPO_ROOT/app/ui/app/index.html"
    fi
    if [ -f "$REPO_ROOT/app/cmd/app/webview.go.bak" ]; then
        mv "$REPO_ROOT/app/cmd/app/webview.go.bak" "$REPO_ROOT/app/cmd/app/webview.go"
    fi
}
trap cleanup EXIT

# --- Step 1: Verify tools ---
info "Checking prerequisites..."
command -v go &>/dev/null || error "Go is not installed."
command -v npm &>/dev/null || error "npm is not installed."

# --- Step 2: Temporarily rename brand in source ---
info "Patching brand names..."
cp app/cmd/app/webview.go   app/cmd/app/webview.go.bak
cp app/ui/app/index.html    app/ui/app/index.html.bak
sed -i '' 's/wv\.SetTitle("Ollama")/wv.SetTitle("Ollama-Desktop")/' app/cmd/app/webview.go
perl -pi -e 's/(<title>)Ollama(<\/title>)/$1Ollama-Desktop$2/' app/ui/app/index.html
info "  Source patched."

# --- Step 3: Extract backend binaries ---
info "Extracting backend backend..."
rm -rf "$REPO_ROOT/dist/darwin"
mkdir -p "$REPO_ROOT/dist/darwin"
cp "$BACKEND_SOURCE/Contents/Resources/ollama" "$REPO_ROOT/dist/darwin/"
cp "$BACKEND_SOURCE/Contents/Resources/"*.dylib "$REPO_ROOT/dist/darwin/" 2>/dev/null || true
info "  ollama: $(ls -lh "$REPO_ROOT/dist/darwin/ollama" | awk '{print $5}')"

# --- Step 4: Build frontend ---
info "Building frontend..."
cd "$REPO_ROOT/app/ui/app"
npm install 2>/dev/null || true
npx vite build 2>&1 | tail -3
cd "$REPO_ROOT"

# --- Step 5: Compile Go binary ---
info "Compiling universal binary..."
GOARCH=amd64 CGO_ENABLED=1 GOOS=darwin go build -o dist/darwin-app-amd64 -ldflags="-s -w" ./app/cmd/app 2>&1 | grep -v "warning:" || true
GOARCH=arm64 CGO_ENABLED=1 GOOS=darwin go build -o dist/darwin-app-arm64 -ldflags="-s -w" ./app/cmd/app 2>&1 | grep -v "warning:" || true
lipo -create -output dist/ollama-desktop-universal dist/darwin-app-amd64 dist/darwin-app-arm64
info "  binary: $(ls -lh dist/ollama-desktop-universal | awk '{print $5}')"

# --- Step 6: Assemble .app bundle ---
info "Assembling ${APP_NAME}.app..."
rm -rf "$REPO_ROOT/dist/${APP_NAME}.app"

# Use official app as base template
cp -a "$BACKEND_SOURCE" "$REPO_ROOT/dist/${APP_NAME}.app"

# Patch Info.plist for Desktop branding
plutil -replace CFBundleDisplayName -string "$APP_NAME" "$REPO_ROOT/dist/${APP_NAME}.app/Contents/Info.plist"
plutil -replace CFBundleName -string "$APP_NAME" "$REPO_ROOT/dist/${APP_NAME}.app/Contents/Info.plist"
plutil -replace CFBundleExecutable -string "Ollama-Desktop" "$REPO_ROOT/dist/${APP_NAME}.app/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "com.electron.ollama-desktop" "$REPO_ROOT/dist/${APP_NAME}.app/Contents/Info.plist"

# Replace the desktop UI binary
mkdir -p "$REPO_ROOT/dist/${APP_NAME}.app/Contents/MacOS"
cp dist/ollama-desktop-universal "$REPO_ROOT/dist/${APP_NAME}.app/Contents/MacOS/Ollama-Desktop"

touch "$REPO_ROOT/dist/${APP_NAME}.app"

info ""
info "=========================================="
info " Build complete!"
info "=========================================="
info "  Output: dist/${APP_NAME}.app"
info "  Size:   $(du -sh "dist/${APP_NAME}.app" | cut -f1)"
info ""
info "Quick share (zip):"
info "  ditto -c -k --keepParent dist/${APP_NAME}.app dist/${APP_NAME}.zip"
