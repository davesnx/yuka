#!/bin/sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
build=${BUILD_DIR:-_build}
out="$root/$build/default/demo/client"
rm -rf "$out/bundle"
"$root/node_modules/.bin/esbuild" "$out/out/demo/client/main.js" \
  --bundle --splitting --format=esm --minify --outdir="$out/bundle"
