Arguments:

  $ yuka
  yuka: no command
  usage: yuka dev [--build TARGET]... [--assets DIR]... [--state FILE] [--dune CMD] [--kill-after SECONDS] [--watch-exe FILE] -- SERVER [ARG]...
  [2]
  $ yuka dev --build @x 2>&1 | head -1
  yuka: no server command; give it after --
  $ yuka dev --kill-after soon -- ./server 2>&1 | head -1
  yuka: --kill-after takes a number of seconds, not soon
  $ yuka dev --frobnicate -- ./server 2>&1 | head -1
  yuka: unknown argument --frobnicate
  $ yuka dev --watch-exe 2>&1 | head -1
  yuka: --watch-exe needs a value

A fake dune prints build results and changes files between them; a fake
server logs its starts and stops. The session is random per run:

  $ mkdir static
  $ echo 'body{}' > static/a.css
  $ echo 'js' > static/a.js
  $ cat > server <<'X'
  > #!/bin/sh
  > echo "start $YUKA_DEV $(sed 's/"session":"[0-9a-f]*"/"session":S/' $YUKA_DEV_FILE)" >> log
  > echo $$ > server.pid
  > trap 'echo stop >> log; exit 0' TERM
  > while true; do sleep 0.05; done
  > X
  $ chmod +x server
  $ cat > fake-dune <<'X'
  > #!/bin/sh
  > echo "args: $*" >> log
  > step() { sleep 0.5; printf 'state %s\n' "$(sed 's/"session":"[0-9a-f]*"/"session":S/' deep/er/state)" >> log; }
  > echo "Success, waiting for filesystem changes..."; step
  > echo 'body{color:red}' > static/a.css
  > echo "Success, waiting for filesystem changes..."; step
  > echo 'js2' > static/a.js
  > echo "Success, waiting for filesystem changes..."; step
  > rm static/a.js
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
  $ yuka dev --dune ./fake-dune --build @x --assets static --state deep/er/state -- ./server 2> err
  $ cat log
  args: build --watch @x
  start 1 {"session":S,"build":1,"page":1,"error":null}
  state {"session":S,"build":1,"page":1,"error":null}
  state {"session":S,"build":2,"page":1,"error":null}
  stop
  start 1 {"session":S,"build":3,"page":3,"error":null}
  state {"session":S,"build":3,"page":3,"error":null}
  stop
  start 1 {"session":S,"build":4,"page":4,"error":null}
  state {"session":S,"build":4,"page":4,"error":null}
  state {"session":S,"build":4,"page":4,"error":null}
  state {"session":S,"build":4,"page":4,"error":"File \"a.ml\", line 1:\u000aError: \"boom\""}
  stop
  start 1 {"session":S,"build":5,"page":5,"error":null}
  state {"session":S,"build":5,"page":5,"error":null}
  start 1 {"session":S,"build":6,"page":6,"error":null}
  state {"session":S,"build":6,"page":6,"error":null}
  stop
  $ grep -c "restarting the server" err
  3

Each run has its own session:

  $ cp deep/er/state first
  $ yuka dev --dune ./fake-dune --build @x --assets static --state deep/er/state -- ./server 2> /dev/null
  $ test "$(grep -o '"session":"[0-9a-f]*"' first)" != "$(grep -o '"session":"[0-9a-f]*"' deep/er/state)" && echo different
  different

A command found through PATH is watched in PATH; --watch-exe names the file
to watch when the command is a wrapper:

  $ mkdir bin && cp server bin/myserver && rm -f log
  $ cat > fake-dune3 <<'X'
  > #!/bin/sh
  > echo "Success, waiting for filesystem changes..."; sleep 0.5
  > echo "Success, waiting for filesystem changes..."; sleep 0.5
  > touch -d '+2 hours' bin/myserver
  > echo "Success, waiting for filesystem changes..."; sleep 0.5
  > X
  $ chmod +x fake-dune3
  $ PATH="$PWD/bin:$PATH" yuka dev --dune ./fake-dune3 --state s3 -- myserver 2> /dev/null; grep -c start log
  2
  $ rm -f log; echo exe > watched
  $ cat > fake-dune4 <<'X'
  > #!/bin/sh
  > echo "Success, waiting for filesystem changes..."; sleep 0.5
  > echo "Success, waiting for filesystem changes..."; sleep 0.5
  > echo changed > watched
  > echo "Success, waiting for filesystem changes..."; sleep 0.5
  > X
  $ chmod +x fake-dune4
  $ yuka dev --dune ./fake-dune4 --state s4 --watch-exe watched -- sh -c 'exec ./server' 2> /dev/null; grep -c start log
  2

An error after the server started stops it and dune:

  $ rm -f log
  $ cat > fake-dune5 <<'X'
  > #!/bin/sh
  > echo "Success, waiting for filesystem changes..."; sleep 0.5
  > rm -r s5dir
  > echo "Success, waiting for filesystem changes..."; sleep 2
  > echo "dune still running" >> log
  > X
  $ chmod +x fake-dune5
  $ yuka dev --dune ./fake-dune5 --state s5dir/state -- ./server 2>&1 | grep -c "yuka dev: Sys_error"
  1
  $ sleep 2.5; cat log
  start 1 {"session":S,"build":1,"page":1,"error":null}
  stop

A server that ignores SIGTERM is killed after --kill-after, also when the
CLI gets SIGTERM in the middle of a restart:

  $ cat > stubborn <<'X'
  > #!/bin/sh
  > trap '' TERM
  > echo "started $$" >> slog
  > while true; do sleep 0.05; done
  > X
  $ chmod +x stubborn
  $ cat > fake-dune6 <<'X'
  > #!/bin/sh
  > echo "Success, waiting for filesystem changes..."; sleep 0.4
  > touch -d '+3 hours' stubborn
  > echo "Success, waiting for filesystem changes..."; sleep 0.3
  > kill -TERM $PPID
  > sleep 3
  > X
  $ chmod +x fake-dune6
  $ yuka dev --dune ./fake-dune6 --state s6 --kill-after 1 -- ./stubborn 2>&1 | grep -v Success
  yuka dev: restarting the server
  yuka dev: the server did not stop after 1 s, killing it
  $ wc -l < slog
  1
  $ kill -0 $(cut -d' ' -f2 slog) 2>/dev/null || echo "server gone"
  server gone
