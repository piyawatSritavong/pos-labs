#!/usr/bin/env bash
# ============================================================================
# build-pos-windows.sh
#
# Builds the Windows 10 POS deployment package on macOS:
#   1. Builds Flutter Web release
#   2. Cross-compiles the Go backend to Windows x64
#   3. Packages everything into dist/POSApp/
#
# Output: dist/POSApp/  →  zip and copy to C:\POSApp on the Windows POS machine.
#
# Usage:  bash scripts/build-pos-windows.sh
# ============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$REPO_ROOT/dist/POSApp"
FRONTEND_DIR="$REPO_ROOT/frontend"
BACKEND_DIR="$REPO_ROOT/backend"
DEPLOY_DIR="$REPO_ROOT/deploy/windows"

echo
echo "=== POS Windows Build ==="
echo "Repo root  : $REPO_ROOT"
echo "Output     : $DIST_DIR"
echo

# -- Sanity checks -----------------------------------------------------------
command -v flutter >/dev/null 2>&1 || { echo "[ERROR] flutter not found on PATH"; exit 1; }
command -v go      >/dev/null 2>&1 || { echo "[ERROR] go not found on PATH"; exit 1; }

[[ -d "$FRONTEND_DIR" ]] || { echo "[ERROR] Frontend dir missing: $FRONTEND_DIR"; exit 1; }
[[ -d "$BACKEND_DIR"  ]] || { echo "[ERROR] Backend dir missing : $BACKEND_DIR";  exit 1; }
[[ -d "$DEPLOY_DIR"   ]] || { echo "[ERROR] Deploy dir missing  : $DEPLOY_DIR";   exit 1; }

# -- Clean output ------------------------------------------------------------
echo "[1/5] Cleaning $DIST_DIR ..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR/static" "$DIST_DIR/logs"

# -- Flutter Web build -------------------------------------------------------
# POS_SECRET must match what's stored in pos_setting.pos_secret (set by
# backend/migrations/0010_real_seed_data.up.sql). Override by exporting
# POS_SECRET before running this script.
POS_SECRET_FOR_BUILD="${POS_SECRET:-windows-pos-default-secret}"
API_BASE_URL_FOR_BUILD="${API_BASE_URL:-http://127.0.0.1:8080}"
echo "[2/5] Building Flutter Web (release, API_BASE_URL=$API_BASE_URL_FOR_BUILD, POS_SECRET=$POS_SECRET_FOR_BUILD) ..."
(
    cd "$FRONTEND_DIR"
    flutter pub get
    if ! flutter build web --release \
        --dart-define=API_BASE_URL="$API_BASE_URL_FOR_BUILD" \
        --dart-define=POS_SECRET="$POS_SECRET_FOR_BUILD"; then
        echo
        echo "[ERROR] flutter build web failed."
        echo
        echo "Common cause: desktop-only plugins (window_manager, desktop_multi_window)"
        echo "in pubspec.yaml are not Web-compatible. Wrap their initialization in"
        echo "  if (!kIsWeb) { ... }"
        echo "inside lib/main.dart, then re-run this script."
        exit 1
    fi
)

# -- Copy Flutter output -----------------------------------------------------
echo "[3/5] Copying Flutter Web → $DIST_DIR/static/ ..."
cp -R "$FRONTEND_DIR/build/web/." "$DIST_DIR/static/"

# -- Go cross-compile --------------------------------------------------------
echo "[4/5] Cross-compiling Go backend (GOOS=windows GOARCH=amd64) ..."
(
    cd "$BACKEND_DIR"
    GOOS=windows GOARCH=amd64 CGO_ENABLED=0 \
        go build -trimpath -ldflags="-s -w" \
        -o "$DIST_DIR/pos-backend.exe" ./cmd/server
)

# -- Copy deploy files -------------------------------------------------------
echo "[5/5] Copying deploy files ..."
cp "$DEPLOY_DIR/.env.example"       "$DIST_DIR/.env.example"
cp "$DEPLOY_DIR/start-pos.bat"      "$DIST_DIR/start-pos.bat"
cp "$DEPLOY_DIR/start-backend-hidden.vbs" "$DIST_DIR/start-backend-hidden.vbs"
cp "$DEPLOY_DIR/stop-pos.bat"       "$DIST_DIR/stop-pos.bat"
cp "$DEPLOY_DIR/load-real-data.bat" "$DIST_DIR/load-real-data.bat"
cp "$DEPLOY_DIR/verify-data.bat"    "$DIST_DIR/verify-data.bat"

# Real-data SQL script (the user runs this manually after first start to load
# 1,566 products + categories + Thai units; see load-real-data.bat helper).
if [[ -f "$DEPLOY_DIR/seed-real-data.sql" ]]; then
    cp "$DEPLOY_DIR/seed-real-data.sql"      "$DIST_DIR/seed-real-data.sql"
    cp "$DEPLOY_DIR/seed-real-data.down.sql" "$DIST_DIR/seed-real-data.down.sql"
else
    echo "      [WARN] $DEPLOY_DIR/seed-real-data.sql not found."
    echo "             Run: python3 scripts/generate-real-seed-sql.py  (needs openpyxl)"
fi

# Migrations are run automatically by the backend on startup (schema + core seed).
# Bundle a copy in case the operator wants to inspect or run manually.
if [[ -d "$BACKEND_DIR/migrations" ]]; then
    echo "      (also copying backend/migrations → $DIST_DIR/migrations/)"
    cp -R "$BACKEND_DIR/migrations" "$DIST_DIR/migrations"
fi

# -- Done --------------------------------------------------------------------
echo
echo "=== Build complete ==="
echo "Tree (top 2 levels):"
( cd "$DIST_DIR" && find . -maxdepth 2 -not -path './static/assets/*' -not -path './static/canvaskit/*' -not -path './static/icons/*' | sort )
echo
echo "Backend size:"
ls -lh "$DIST_DIR/pos-backend.exe" | awk '{print "  " $5 "  " $NF}'
echo
echo "Next steps:"
echo "  1. cd dist && zip -r POSApp.zip POSApp/"
echo "  2. Copy POSApp.zip to the Windows 10 POS machine"
echo "  3. Unzip into  C:\\POSApp"
echo "  4. Follow  deploy/windows/README-WINDOWS-POS.md"
echo
