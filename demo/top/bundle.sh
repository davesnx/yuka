#!/bin/sh
set -eu
root=$(cd "$(dirname "$0")/../.." && pwd)
build=${BUILD_DIR:-_build}
out="$root/$build/default/demo/top/client"
cd "$out/out/demo/top/client"
rm -rf bundle "$out/meta.json"
node "$root/scripts/bundle.ts" --entry main.js --format esm --splitting --metafile "$out/meta.json" --outdir bundle
