#!/bin/sh
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
port=${PORT:-8123}
build=${BUILD_DIR:-_build}
cd "$root" || exit 2
opam exec ${SWITCH:+--switch=$SWITCH} -- dune build --root . --build-dir "$build" @demo/all || { echo "build failed"; exit 2; }
[ -n "${YUKA_DEMO_DATABASE:-}" ] || echo "YUKA_DEMO_DATABASE is not set: each server keeps its own data in memory, and the checks fail"
second=$((port + 1))
server="$root/$build/default/demo/server/demo_server.exe"
log="${TMPDIR:-/tmp}/yuka_e2e_shared_$port"
"$server" --port "$port" >"$log.first.log" 2>&1 &
first_pid=$!
"$server" --port "$second" >"$log.second.log" 2>&1 &
second_pid=$!
trap 'kill $first_pid $second_pid 2>/dev/null' EXIT INT TERM
i=0
until curl -s -o /dev/null "http://127.0.0.1:$port/" && curl -s -o /dev/null "http://127.0.0.1:$second/"; do
  i=$((i + 1))
  [ $i -gt 50 ] && { echo "server did not start, see $log.first.log and $log.second.log"; exit 2; }
  sleep 0.1
done
node "$root/e2e/shared_store.ts" "http://127.0.0.1:$port" "http://127.0.0.1:$second"
