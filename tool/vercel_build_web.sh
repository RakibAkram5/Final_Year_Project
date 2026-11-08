#!/usr/bin/env bash
# Builds the Flutter web app into vercel_web/ (vercel.json "outputDirectory")
# for the taleemplus Vercel project. Git-triggered Vercel builds have no
# Flutter SDK, so when `flutter` is not already on PATH (local machine,
# GitHub Actions) a pinned SDK is installed into node_modules/.cache, which
# Vercel keeps in its build cache between deployments.
#
# The web build needs no --dart-define: on a non-localhost origin the app
# calls the API on the same origin (/api/v2), see lib/data/remote/api_client.dart.
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.9}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export CI=true
export FLUTTER_SUPPRESS_ANALYTICS=true

if command -v flutter >/dev/null 2>&1; then
  FLUTTER="flutter"
else
  CACHE_DIR="$ROOT/node_modules/.cache"
  SDK_DIR="$CACHE_DIR/flutter-$FLUTTER_VERSION"
  export PUB_CACHE="$CACHE_DIR/pub-cache"

  if [ ! -x "$SDK_DIR/flutter/bin/flutter" ]; then
    missing=""
    for tool in xz unzip git; do
      command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
    done
    if [ -n "$missing" ]; then
      echo "Installing build tools:$missing"
      dnf install -y $missing
    fi

    echo "Installing Flutter $FLUTTER_VERSION"
    rm -rf "$CACHE_DIR"/flutter-*
    mkdir -p "$SDK_DIR"
    curl -fsSL \
      "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
      | tar -xJ --no-same-owner -C "$SDK_DIR"
  fi

  # The SDK is a git checkout; the build user may not own it.
  git config --global --add safe.directory '*'
  FLUTTER="$SDK_DIR/flutter/bin/flutter"
fi

"$FLUTTER" --version
"$FLUTTER" config --no-analytics >/dev/null
"$FLUTTER" pub get
"$FLUTTER" build web --release

rm -rf vercel_web
cp -R build/web vercel_web
echo "Flutter web output staged in vercel_web/"
