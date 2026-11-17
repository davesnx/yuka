#!/bin/sh
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
build=${BUILD_DIR:-_build}
keyed="$root/bench/keyed"
site="$root/$build/bench-keyed"
mkdir -p "$site/yuka/dist" "$site/yuka-block/dist" "$site/solid/dist" "$site/vanillajs/src"
cp -R "$keyed/css" "$site/"

node "$root/scripts/bundle.ts" --entry "$root/$build/default/bench/keyed/yuka/out/bench/keyed/yuka/main.js" \
  --outdir "$site/yuka/dist"
cp "$keyed/yuka/index.html" "$site/yuka/"

node "$root/scripts/bundle.ts" --entry "$root/$build/default/bench/keyed/yuka-block/out/bench/keyed/yuka-block/main.js" \
  --outdir "$site/yuka-block/dist"
cp "$keyed/yuka-block/index.html" "$site/yuka-block/"

if [ ! -d "$keyed/solid/node_modules" ]; then
  npm ci --prefix "$keyed/solid" --no-audit --no-fund
fi
npm run --prefix "$keyed/solid" --silent build -- --file "$root/$build/bench-keyed-solid/main.js"
node "$root/scripts/bundle.ts" --entry "$root/$build/bench-keyed-solid/main.js" --outdir "$site/solid/dist"
cp "$keyed/solid/index.html" "$site/solid/"

cp "$keyed/vanillajs/index.html" "$site/vanillajs/"
cp "$keyed/vanillajs/src/Main.js" "$site/vanillajs/src/"
