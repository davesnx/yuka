#!/bin/sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
build=${BUILD_DIR:-_build}
out="$root/$build/default/demo/client"
cd "$out/out/demo/client"
rm -rf bundle "$out/meta.json"
"$root/node_modules/.bin/esbuild" main.js \
  --bundle --splitting --format=esm --minify --metafile="$out/meta.json" --outdir=bundle
