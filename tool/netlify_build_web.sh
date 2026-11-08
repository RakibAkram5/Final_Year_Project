#!/usr/bin/env bash
# Builds the Flutter web app into build/web (netlify.toml "publish") for
# Netlify. Netlify's build image has no Flutter SDK, so when `flutter` is not
# on PATH a pinned SDK is downloaded into the build cache directory.
#
# No --dart-define is needed: on a non-localhost origin the app calls the API
# on its own origin (/api/v2), which netlify.toml proxies to the backend.
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.9}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export CI=true
export FLUTTER_SUPPRESS_ANALYTICS=true

if command -v flutter >/dev/null 2>&1; then
  FLUTTER="flutter"
else
  # NETLIFY_CACHE_DIR persists between Netlify builds.
  CACHE_DIR="${NETLIFY_CACHE_DIR:-$ROOT/.cache}"
  SDK_DIR="$CACHE_DIR/flutter-$FLUTTER_VERSION"
  export PUB_CACHE="$CACHE_DIR/pub-cache"

  if [ ! -x "$SDK_DIR/flutter/bin/flutter" ]; then
    echo "Installing Flutter $FLUTTER_VERSION"
    rm -rf "$CACHE_DIR"/flutter-*
    mkdir -p "$SDK_DIR"
    curl -fsSL \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
      | tar -xJ --no-same-owner -C "$SDK_DIR"
  fi

  git config --global --add safe.directory '*'
  FLUTTER="$SDK_DIR/flutter/bin/flutter"
fi

"$FLUTTER" --version
"$FLUTTER" config --no-analytics >/dev/null
"$FLUTTER" pub get
"$FLUTTER" build web --release
echo "Flutter web output ready in build/web/"
