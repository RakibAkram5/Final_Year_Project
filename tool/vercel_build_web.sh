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

# Netlify already builds and serves the Flutter web app. Set
# SKIP_FLUTTER_WEB_BUILD=1 in the Vercel project to deploy the API only
# (saves a full Flutter compile per deployment). vercel.json still needs an
# output directory, so a small page pointing to the web app is written.
if [ "${SKIP_FLUTTER_WEB_BUILD:-0}" = "1" ]; then
  WEB_APP_URL="${WEB_APP_URL:-}"
  rm -rf vercel_web
  mkdir -p vercel_web
  {
    echo '<!doctype html><html lang="en"><head><meta charset="utf-8">'
    echo '<meta name="viewport" content="width=device-width,initial-scale=1">'
    echo '<title>TaleemPlus API</title></head><body style="font-family:sans-serif;padding:24px">'
    echo '<h1>TaleemPlus API</h1><p>This deployment serves the REST API under <code>/api/v2</code>.</p>'
    if [ -n "$WEB_APP_URL" ]; then
      echo "<p>Open the app: <a href=\"$WEB_APP_URL\">$WEB_APP_URL</a></p>"
    fi
    echo '</body></html>'
  } > vercel_web/index.html
  echo "SKIP_FLUTTER_WEB_BUILD=1: API-only deployment (no Flutter web build)."
  exit 0
fi

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
