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

# Flutter normally emits a fixed `main.dart.js` filename. Vercel can retain the
# previous file at that path across otherwise-successful deployments, leaving
# index.html on the new release while cashiers still execute old POS logic.
# Give every Git deployment an immutable bundle URL and point the generated
# bootstrap at it. Query-string cache busting is insufficient because the CDN
# may key this static asset by path only.
if [[ -n "${VERCEL_GIT_COMMIT_SHA:-}" ]]; then
  BUILD_REVISION="${VERCEL_GIT_COMMIT_SHA:0:12}"
  MAIN_BUNDLE="main.${BUILD_REVISION}.dart.js"
  mv build/web/main.dart.js "build/web/$MAIN_BUNDLE"
  sed "s/main\\.dart\\.js/$MAIN_BUNDLE/g" \
    build/web/flutter_bootstrap.js > build/web/flutter_bootstrap.js.tmp
  mv build/web/flutter_bootstrap.js.tmp build/web/flutter_bootstrap.js
fi
