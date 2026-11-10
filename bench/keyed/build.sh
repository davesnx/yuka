#!/bin/sh
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
build=${BUILD_DIR:-_build}
keyed="$root/bench/keyed"
site="$root/$build/bench-keyed"
mkdir -p "$site/yuka/dist" "$site/solid/dist" "$site/vanillajs/src"
cp -R "$keyed/css" "$site/"

"$root/node_modules/.bin/esbuild" "$root/$build/default/bench/keyed/yuka/out/bench/keyed/yuka/main.js" \
  --bundle --format=iife --minify --log-level=warning --outfile="$site/yuka/dist/main.js"
cp "$keyed/yuka/index.html" "$site/yuka/"

if [ ! -d "$keyed/solid/node_modules" ]; then
  npm ci --prefix "$keyed/solid" --no-audit --no-fund
fi
npm run --prefix "$keyed/solid" --silent build-prod -- --file "$site/solid/dist/main.js"
cp "$keyed/solid/index.html" "$site/solid/"

cp "$keyed/vanillajs/index.html" "$site/vanillajs/"
cp "$keyed/vanillajs/src/Main.js" "$site/vanillajs/src/"
