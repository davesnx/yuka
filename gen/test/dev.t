Arguments:

  $ yuka
  yuka: no command
  usage: yuka dev [--build TARGET]... [--assets DIR]... [--state FILE] [--dune CMD] [--kill-after SECONDS] -- SERVER [ARG]...
  [2]
  $ yuka dev --build @x
  yuka: no server command; give it after --
  usage: yuka dev [--build TARGET]... [--assets DIR]... [--state FILE] [--dune CMD] [--kill-after SECONDS] -- SERVER [ARG]...
  [2]
  $ yuka dev --kill-after soon -- ./server
  yuka: --kill-after takes a number of seconds, not soon
  usage: yuka dev [--build TARGET]... [--assets DIR]... [--state FILE] [--dune CMD] [--kill-after SECONDS] -- SERVER [ARG]...
  [2]
  $ yuka dev --frobnicate -- ./server
  yuka: unknown argument --frobnicate
  usage: yuka dev [--build TARGET]... [--assets DIR]... [--state FILE] [--dune CMD] [--kill-after SECONDS] -- SERVER [ARG]...
  [2]

A fake dune prints build results and changes files between them; a fake
server logs its starts and stops:

  $ mkdir static
  $ echo 'body{}' > static/a.css
  $ echo 'js' > static/a.js
  $ cat > server <<'X'
  > #!/bin/sh
  > echo "start $YUKA_DEV $(cat $YUKA_DEV_FILE)" >> log
  > echo $$ > server.pid
  > trap 'echo stop >> log; exit 0' TERM
  > while true; do sleep 0.05; done
  > X
  $ chmod +x server
  $ cat > fake-dune <<'X'
  > #!/bin/sh
  > echo "args: $*" >> log
  > step() { sleep 0.5; printf 'state %s\n' "$(cat state)" >> log; }
  > echo "Success, waiting for filesystem changes..."; step
  > echo 'body{color:red}' > static/a.css
  > echo "Success, waiting for filesystem changes..."; step
  > echo 'js2' > static/a.js
  > echo "Success, waiting for filesystem changes..."; step
  > echo "Success, waiting for filesystem changes..."; step
  > echo "********** NEW BUILD (a.ml changed) **********"
  > echo 'File "a.ml", line 1:'
  > echo 'Error: "boom"'
  > echo "Had 1 error, waiting for filesystem changes..."; step
  > touch -d '+1 hour' server
  > echo "Success, waiting for filesystem changes..."; step
  > kill -9 $(cat server.pid); sleep 0.2
  > echo "Success, waiting for filesystem changes..."; step
  > X
  $ chmod +x fake-dune
  $ yuka dev --dune ./fake-dune --build @x --assets static --state state -- ./server 2> err
  $ cat log
  args: build --watch @x
  start 1 {"build":1,"page":1,"error":null}
  state {"build":1,"page":1,"error":null}
  state {"build":2,"page":1,"error":null}
  state {"build":3,"page":3,"error":null}
  state {"build":3,"page":3,"error":null}
  state {"build":3,"page":3,"error":"File \"a.ml\", line 1:\nError: \"boom\""}
  stop
  start 1 {"build":4,"page":4,"error":null}
  state {"build":4,"page":4,"error":null}
  start 1 {"build":5,"page":5,"error":null}
  state {"build":5,"page":5,"error":null}
  stop
  $ grep -c "restarting the server" err
  1

A server that ignores SIGTERM is killed after --kill-after:

  $ cat > stubborn <<'X'
  > #!/bin/sh
  > trap '' TERM
  > echo started >> slog
  > while true; do sleep 0.05; done
  > X
  $ chmod +x stubborn
  $ cat > fake-dune2 <<'X'
  > #!/bin/sh
  > echo "Success, waiting for filesystem changes..."; sleep 0.4
  > X
  $ chmod +x fake-dune2
  $ yuka dev --dune ./fake-dune2 --state state2 --kill-after 0.2 -- ./stubborn 2>&1 | grep -v Success
  yuka dev: the server did not stop after 0.2 s, killing it
  $ cat slog
  started
