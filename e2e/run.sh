#!/bin/sh
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
port=${PORT:-8123}
build=${BUILD_DIR:-_build}
cd "$root" || exit 2
opam exec ${SWITCH:+--switch=$SWITCH} -- dune build --build-dir "$build" @demo/all || { echo "build failed"; exit 2; }
mode=modules
flags=
if [ "${BUNDLE:-}" = 1 ]; then
  BUILD_DIR="$build" "$root/demo/bundle.sh" || { echo "bundle failed"; exit 2; }
  mode=bundle
  flags=--bundle
fi
pidfile="${TMPDIR:-/tmp}/yuka_e2e_server_$port.pid"
log="${TMPDIR:-/tmp}/yuka_e2e_server_$port.log"
second=$((port + 1))
bus=${YUKA_E2E_BUS:-memory}
"$root/$build/default/demo/server/demo_server.exe" --port "$port" --second-node "$second" --bus "$bus" $flags >"$log" 2>&1 &
echo $! >"$pidfile"
trap 'kill $(cat "$pidfile") 2>/dev/null' EXIT INT TERM
i=0
until curl -s -o /dev/null "http://127.0.0.1:$port/" && curl -s -o /dev/null "http://127.0.0.1:$second/"; do
  i=$((i + 1))
  [ $i -gt 50 ] && { echo "server did not start"; exit 2; }
  sleep 0.1
done
YUKA_E2E_SECOND="http://127.0.0.1:$second" \
YUKA_E2E_SERVER="$root/$build/default/demo/server/demo_server.exe --port $port --second-node $second --bus $bus $flags" YUKA_E2E_PIDFILE="$pidfile" YUKA_E2E_LOG="$log" \
  node "$root/e2e/demo.ts" "http://127.0.0.1:$port" "$mode"
