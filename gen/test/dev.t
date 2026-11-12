Arguments:

  $ yuka
  yuka: no command
  usage: yuka COMMAND [OPTION]...
  
  commands:
    routes   Write the shared or the server module of a Routes.ml route tree
    islands  Write the island registry or manifest of the island libraries
    css      Write the module with the sheets of every [%yuka.css] declaration
    dev      Rebuild in watch mode, restart the server and reload the browser
  
  yuka COMMAND --help shows the options of a command.
  [2]
  $ yuka dev --build @x 2>&1 | head -1
  yuka dev: no server command; give it after --.
  $ yuka dev --kill-after soon -- ./server 2>&1 | head -1
  yuka dev: wrong argument 'soon'; option '--kill-after' expects a float.
  $ yuka dev --frobnicate -- ./server 2>&1 | head -1
  yuka dev: unknown option '--frobnicate'.
  $ yuka dev --watch-exe 2>&1 | head -1
  yuka dev: option '--watch-exe' needs an argument.

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
  > perl -e '$t = time + 1 * 3600; utime $t, $t, @ARGV' server
  > echo "Success, waiting for filesystem changes..."; step
  > kill -9 $(cat server.pid); sleep 0.2
  > echo "Success, waiting for filesystem changes..."; step
  > X
  $ chmod +x fake-dune
  $ yuka dev --build './fake-dune build --watch @x' --assets static --state deep/er/state -- ./server 2> err
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
  $ yuka dev --build './fake-dune build --watch @x' --assets static --state deep/er/state -- ./server 2> /dev/null
  $ test "$(grep -o '"session":"[0-9a-f]*"' first)" != "$(grep -o '"session":"[0-9a-f]*"' deep/er/state)" && echo different
  different

A command found through PATH is watched in PATH; --watch-exe names the file
to watch when the command is a wrapper:

  $ mkdir bin && cp server bin/myserver && rm -f log
  $ cat > fake-dune3 <<'X'
  > #!/bin/sh
  > echo "Success, waiting for filesystem changes..."; sleep 0.5
  > echo "Success, waiting for filesystem changes..."; sleep 0.5
  > perl -e '$t = time + 2 * 3600; utime $t, $t, @ARGV' bin/myserver
  > echo "Success, waiting for filesystem changes..."; sleep 0.5
  > X
  $ chmod +x fake-dune3
  $ PATH="$PWD/bin:$PATH" yuka dev --build './fake-dune3 build --watch' --state s3 -- myserver 2> /dev/null; grep -c start log
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
  $ yuka dev --build './fake-dune4 build --watch' --state s4 --watch-exe watched -- sh -c 'exec ./server' 2> /dev/null; grep -c start log
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
  $ yuka dev --build './fake-dune5 build --watch' --state s5dir/state -- ./server 2>&1 | grep -c "yuka dev: Sys_error"
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
  > perl -e '$t = time + 3 * 3600; utime $t, $t, @ARGV' stubborn
  > echo "Success, waiting for filesystem changes..."; sleep 0.3
  > kill -TERM $(cat yuka.pid)
  > sleep 3
  > X
  $ chmod +x fake-dune6
  $ sh -c 'echo $$ > yuka.pid; exec yuka dev --build "./fake-dune6 build --watch" --state s6 --kill-after 1 -- ./stubborn' 2>&1 | grep -v Success
  yuka dev: restarting the server
  yuka dev: the server did not stop after 1 s, killing it
  $ wc -l < slog | tr -d ' '
  1
  $ kill -0 $(cut -d' ' -f2 slog) 2>/dev/null || echo "server gone"
  server gone

The build is a full command, run by /bin/sh; the state file is in
DUNE_BUILD_DIR when no --state is given:

  $ rm -f log
  $ cat > fake-dune7 <<'X'
  > #!/bin/sh
  > echo "args: $*" >> log
  > echo "Success, waiting for filesystem changes..."; sleep 0.5
  > X
  $ chmod +x fake-dune7
  $ DUNE_BUILD_DIR=out yuka dev --build "./fake-dune7 build --watch --profile=dev '@a b'" -- ./server 2> /dev/null
  $ head -1 log
  args: build --watch --profile=dev @a b
  $ sed 's/"session":"[0-9a-f]*"/"session":S/' out/.yuka-dev
  {"session":S,"build":1,"page":1,"error":null}

The build command is any shell command: an assignment, a cd and a pipeline
work, and yuka dev stops every process of the command:

  $ rm -f log
  $ FOO=0 yuka dev --build 'FOO=1 ./fake-dune7 build --watch' --state s7 -- ./server 2> /dev/null; echo $?
  0
  $ grep -c args log
  1
  $ mkdir sub && cp fake-dune7 sub/
  $ yuka dev --build 'cd sub && ./fake-dune7 build --watch' --state s7 -- ./server 2> /dev/null; echo $?
  0
  $ grep -c args sub/log
  1
  $ cat > fake-dune8 <<'X'
  > #!/bin/sh
  > echo $$ > d8.pid
  > echo "Success, waiting for filesystem changes..."; sleep 0.5
  > kill -TERM $(cat yuka.pid)
  > sleep 5
  > X
  $ chmod +x fake-dune8
  $ sh -c 'echo $$ > yuka.pid; exec yuka dev --build "./fake-dune8 | cat" --state s8 -- ./server' > /dev/null 2>&1; echo $?
  143
  $ sleep 0.3; kill -0 $(cat d8.pid) 2>/dev/null || echo "build gone"
  build gone
