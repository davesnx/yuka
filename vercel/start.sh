#!/bin/bash
set -eu
mkdir -p /tmp/nginx
sed "s/@PORT@/${PORT:-8080}/" /app/nginx.conf > /tmp/nginx/nginx.conf
/app/demo/server/demo_server.exe --bundle --interface 127.0.0.1 --port 8081 --base /demo/mini-linear --prerendered /app/demo/prerendered &
nginx -e stderr -c /tmp/nginx/nginx.conf -g 'daemon off;' &
trap 'kill $(jobs -p) 2>/dev/null; exit 143' TERM INT
set +e
wait -n
status=$?
kill $(jobs -p) 2>/dev/null
exit $status
