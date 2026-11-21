#!/bin/sh
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
build=${BUILD_DIR:-_build}
app=${1:-demo}
out="$root/$build/default/$app/client"
cd "$out/out/$app/client"
rm -rf bundle "$out/meta.json"
node "$root/scripts/bundle.ts" --entry main.js --format esm --splitting --metafile "$out/meta.json" --outdir bundle
