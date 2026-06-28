#!/usr/bin/env bash
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-stable}"
FLUTTER_HOME="${VERCEL_CACHE_DIR:-$HOME/.cache}/flutter-$FLUTTER_VERSION"

if ! command -v flutter >/dev/null 2>&1; then
  if [[ ! -d "$FLUTTER_HOME/.git" ]]; then
    rm -rf "$FLUTTER_HOME"
    mkdir -p "$(dirname "$FLUTTER_HOME")"
    git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_HOME"
  fi
  export PATH="$FLUTTER_HOME/bin:$PATH"
fi

flutter --version
flutter config --enable-web
flutter pub get

if [[ -z "${API_BASE_URL:-}" ]]; then
  echo "API_BASE_URL is required for Vercel builds" >&2
  exit 1
fi

DART_DEFINES=(
  "--dart-define=API_BASE_URL=$API_BASE_URL"
  "--dart-define=POS_SECRET=${POS_SECRET:-default_if_needed}"
)

if [[ -n "${WS_BASE_URL:-}" ]]; then
  DART_DEFINES+=("--dart-define=WS_BASE_URL=$WS_BASE_URL")
fi

flutter build web --release "${DART_DEFINES[@]}"
