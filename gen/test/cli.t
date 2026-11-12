One executable, yuka, with a command per tool. --help prints the options and
exits 0; a usage error exits 2; a failure on valid arguments exits 1.

  $ yuka --help | head -1
  usage: yuka COMMAND [OPTION]...
  $ yuka frobnicate 2>&1 | head -1
  yuka: unknown command frobnicate
  $ yuka frobnicate > /dev/null 2>&1; echo $?
  2
  $ for c in routes islands css dev; do yuka $c --help > help; echo "$c $? $(head -1 help)"; done
  routes 0 usage: yuka routes --source FILE --shared
  islands 0 usage: yuka islands [--manifest] --dir DIR [--dir DIR]...
  css 0 usage: yuka css --dir DIR [--dir DIR]...
  dev 0 usage: yuka dev [--build COMMAND] [--assets DIR]... [--state FILE] [--kill-after SECONDS] [--watch-exe FILE] -- SERVER [ARG]...

yuka routes reads the file given by --source, not stdin, with the flags in any
order:

  $ cat > Routes.ml <<'X'
  > Router.make [ Router.route Home ~path:"/" ~page:Pages.home ]
  > X
  $ yuka routes --shared --source Routes.ml < /dev/null > first.ml
  $ yuka routes --source Routes.ml --shared > second.ml
  $ cmp first.ml second.ml && grep -c "let find" first.ml
  1
  $ yuka routes --shared-module App.Routes --source Routes.ml --server | grep -c "let app"
  1
  $ yuka routes --shared > /dev/null 2>&1; echo $?
  2
  $ yuka routes --shared --server --source Routes.ml > /dev/null 2>&1; echo $?
  2
  $ yuka routes --server --source Routes.ml 2>&1 | head -1
  yuka routes: --server needs --shared-module MODULE.
  $ yuka routes --shared --shared-module Routes --source Routes.ml 2>&1 | head -1
  yuka routes: --shared-module is only for --server.
  $ yuka routes --shared --source Routes.ml extra 2>&1 | head -1
  yuka routes: unexpected argument extra.
  $ yuka routes --shared --source Missing.ml
  yuka routes: Missing.ml: No such file or directory
  [1]
  $ yuka routes --shared --source Missing.ml > /dev/null 2>&1; echo $?
  1

yuka islands and yuka css take --dir, once per directory:

  $ mkdir lib && printf '(library (name app))\n' > lib/dune && printf 'let[@client] make () = ()\n' > lib/counter.mlx
  $ yuka islands --dir lib --manifest
  {
    "App.Counter": "./lib/counter.js"
  }
  $ yuka islands --manifest 2>&1 | head -1
  yuka islands: give at least one --dir.
  $ yuka islands --manifest > /dev/null 2>&1; echo $?
  2
  $ yuka islands lib 2>&1 | head -1
  yuka islands: unexpected argument lib.
  $ yuka islands --library app lib > /dev/null 2>&1; echo $?
  2
  $ yuka css 2>&1 | head -1
  yuka css: give at least one --dir.
  $ yuka css lib > /dev/null 2>&1; echo $?
  2
  $ yuka css --dir lib
  let sheets = [
  ]
  $ yuka css --dir nope; echo $?
  yuka css: nope: No such file or directory
  1

yuka dev: usage errors exit 2:

  $ yuka dev > /dev/null 2>&1; echo $?
  2
  $ yuka dev --dune x -- ./server > /dev/null 2>&1; echo $?
  2
  $ yuka dev --kill-after -1 -- ./server 2>&1 | head -1
  yuka dev: --kill-after takes a number of seconds that is not negative.
