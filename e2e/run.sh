#!/bin/sh
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
port=${PORT:-8123}
build=${BUILD_DIR:-_build}
cd "$root" || exit 2
opam exec ${SWITCH:+--switch=$SWITCH} -- dune build --root . --build-dir "$build" @demo/all || { echo "build failed"; exit 2; }
mode=modules
flags=
if [ "${BUNDLE:-}" = 1 ]; then
  BUILD_DIR="$build" "$root/demo/mini-linear/bundle.sh" || { echo "bundle failed"; exit 2; }
  BUILD_DIR="$build" "$root/demo/async-feed/bundle.sh" || { echo "bundle failed"; exit 2; }
  BUILD_DIR="$build" "$root/demo/posters/bundle.sh" || { echo "bundle failed"; exit 2; }
  mode=bundle
  flags=--bundle
fi
pidfile="${TMPDIR:-/tmp}/yuka_e2e_server_$port.pid"
log="${TMPDIR:-/tmp}/yuka_e2e_server_$port.log"
second=$((port + 1))
bus=${YUKA_E2E_BUS:-memory}
"$root/$build/default/demo/mini-linear/server/demo_server.exe" --port "$port" --second-node "$second" --bus "$bus" $flags >"$log" 2>&1 &
echo $! >"$pidfile"
based=$((port + 2))
proxy=$((port + 3))
prefix=/mini-linear
basepid="${TMPDIR:-/tmp}/yuka_e2e_base_server_$based.pid"
baselog="${TMPDIR:-/tmp}/yuka_e2e_base_server_$based.log"
"$root/$build/default/demo/mini-linear/server/demo_server.exe" --port "$based" --base "$prefix" $flags >"$baselog" 2>&1 &
echo $! >"$basepid"
trap 'kill $(cat "$pidfile") $(cat "$basepid") 2>/dev/null' EXIT INT TERM
i=0
until curl -s -o /dev/null "http://127.0.0.1:$port/" && curl -s -o /dev/null "http://127.0.0.1:$second/" && curl -s -o /dev/null "http://127.0.0.1:$based$prefix"; do
  i=$((i + 1))
  [ $i -gt 50 ] && { echo "server did not start"; exit 2; }
  sleep 0.1
done
YUKA_E2E_SECOND="http://127.0.0.1:$second" \
YUKA_E2E_SERVER="$root/$build/default/demo/mini-linear/server/demo_server.exe --port $port --second-node $second --bus $bus $flags" YUKA_E2E_PIDFILE="$pidfile" YUKA_E2E_LOG="$log" \
  node "$root/e2e/demo.ts" "http://127.0.0.1:$port" "$mode"
status=$?
node "$root/e2e/base.ts" "http://127.0.0.1:$based" "$proxy" "$prefix" || status=1
node "$root/e2e/async-feed.ts" "http://127.0.0.1:$based/async-feed" || status=1
node "$root/e2e/posters.ts" "http://127.0.0.1:$based/posters" || status=1
exit $status
