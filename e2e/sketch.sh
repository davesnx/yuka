#!/bin/sh
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
port=${PORT:-8130}
build=${BUILD_DIR:-_build}
prefix=/demo/sketch
shots=${SHOTS:-$root/e2e/screenshots/sketch}
cd "$root" || exit 2
opam exec ${SWITCH:+--switch=$SWITCH} -- dune build --root . --build-dir "$build" @sketch/all || { echo "build failed"; exit 2; }
log="${TMPDIR:-/tmp}/yuka_sketch_e2e_$port.log"
"$root/$build/default/sketch/server/sketch_server.exe" --port "$port" --base "$prefix" >"$log" 2>&1 &
pid=$!
trap 'kill $pid 2>/dev/null' EXIT INT TERM
i=0
until curl -s -o /dev/null "http://127.0.0.1:$port$prefix"; do
  i=$((i + 1))
  [ $i -gt 50 ] && { echo "server did not start"; exit 2; }
  sleep 0.1
done
node "$root/e2e/sketch.ts" "http://127.0.0.1:$port$prefix" "$shots"
