#!/bin/sh
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
port=${PORT:-8123}
build=${BUILD_DIR:-_build}
cd "$root" || exit 2
opam exec --switch=/home/me/workplace/davesnx/utopia -- dune build --build-dir "$build" @demo/all || { echo "build failed"; exit 2; }
mode=modules
flags=
if [ "${BUNDLE:-}" = 1 ]; then
  BUILD_DIR="$build" "$root/demo/bundle.sh" || { echo "bundle failed"; exit 2; }
  mode=bundle
  flags=--bundle
fi
"$root/$build/default/demo/server/demo_server.exe" --port "$port" $flags >"${TMPDIR:-/tmp}/yuka_e2e_server.log" 2>&1 &
server=$!
trap 'kill $server 2>/dev/null' EXIT INT TERM
i=0
until curl -s -o /dev/null "http://127.0.0.1:$port/"; do
  i=$((i + 1))
  [ $i -gt 50 ] && { echo "server did not start"; exit 2; }
  sleep 0.1
done
node "$root/e2e/demo.ts" "http://127.0.0.1:$port" "$mode"
