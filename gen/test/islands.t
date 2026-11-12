Every island is a lazy entry

  $ mkdir one
  $ printf '(library (name app))\n' > one/dune
  $ printf 'let[@client] make () = ()\n' > one/counter.mlx
  $ yuka islands --dir one
  type m
  type entry = Yuka.runtime_entry
  external import : string -> m Yuka.runtime_promise = "import"
  external register : m -> entry = "register" [@@mel.get]
  external router : m -> Yuka.runtime_router = "router" [@@mel.get]
  
  let registry =
    Yuka.runtime_registry
      ~navigation:(fun () -> Yuka.runtime_promise_map router (import "yuka/navigation.js"))
      ~lazy_entries:
        [ Yuka.runtime_lazy_entry ~name:"App.Counter" (fun () ->
                Yuka.runtime_promise_map register (import "./one/counter.js")) ]
      []

  $ yuka islands --manifest --dir one
  {
    "App.Counter": "./one/counter.js"
  }

Two islands, path relative to the working directory

  $ mkdir -p up/shared up/client
  $ printf '(library (name demo_shared))\n' > up/shared/dune
  $ printf 'let[@client] make () = ()\n' > up/shared/related.mlx
  $ printf 'let[@client] make () = ()\n' > up/shared/counter.mlx
  $ cd up/client
  $ yuka islands --dir ../shared
  type m
  type entry = Yuka.runtime_entry
  external import : string -> m Yuka.runtime_promise = "import"
  external register : m -> entry = "register" [@@mel.get]
  external router : m -> Yuka.runtime_router = "router" [@@mel.get]
  
  let registry =
    Yuka.runtime_registry
      ~navigation:(fun () -> Yuka.runtime_promise_map router (import "yuka/navigation.js"))
      ~lazy_entries:
        [ Yuka.runtime_lazy_entry ~name:"Demo_shared.Counter" (fun () ->
                Yuka.runtime_promise_map register (import "../shared/counter.js"))
        ; Yuka.runtime_lazy_entry ~name:"Demo_shared.Related" (fun () ->
                Yuka.runtime_promise_map register (import "../shared/related.js")) ]
      []
  $ yuka islands --manifest --dir ../shared
  {
    "Demo_shared.Counter": "../shared/counter.js",
    "Demo_shared.Related": "../shared/related.js"
  }
  $ cd ../..

The manifest path is the import path of the same island

  $ yuka islands --dir up/shared | grep -o 'import "\.[^"]*"' | sed 's/import //' | sort > imports
  $ yuka islands --manifest --dir up/shared | grep -o '"[^"]*\.js"' | sort > paths
  $ cat imports
  "./up/shared/counter.js"
  "./up/shared/related.js"
  $ diff imports paths

Nested directory with include_subdirs unqualified, file without island

  $ mkdir -p nested/deep
  $ printf '(include_subdirs unqualified)\n(library (name app))\n' > nested/dune
  $ printf 'let[@client] make () = ()\n' > nested/deep/map.mlx
  $ printf 'let[@client] make () = ()\n' > nested/zed.mlx
  $ printf 'let make () = ()\n(* let[@client] in a comment line is not at line start *)\n' > nested/plain.mlx
  $ printf '  let[@client] make () = ()\n' > nested/indented.mlx
  $ yuka islands --manifest --dir nested
  {
    "App.Map": "./nested/deep/map.js",
    "App.Zed": "./nested/zed.js"
  }

Two libraries, sorted output

  $ mkdir lib_b lib_a
  $ printf '(library (name beta))\n' > lib_b/dune
  $ printf '(library (name alpha))\n' > lib_a/dune
  $ printf 'let[@client] make () = ()\n' > lib_b/same.mlx
  $ printf 'let[@client] make () = ()\n' > lib_a/same.mlx
  $ yuka islands --manifest --dir lib_b --dir lib_a
  {
    "Alpha.Same": "./lib_a/same.js",
    "Beta.Same": "./lib_b/same.js"
  }
  $ yuka islands --dir lib_b --dir lib_a | grep -c lazy_entry
  2

Only .mlx files are scanned

  $ mkdir plain
  $ printf '(library (name plain))\n' > plain/dune
  $ printf 'let[@client] make () = ()\n' > plain/old.ml
  $ printf 'let[@client] make () = ()\n' > plain/new.mlx
  $ yuka islands --manifest --dir plain
  {
    "Plain.New": "./plain/new.js"
  }

No island at all

  $ mkdir empty
  $ printf '(library (name empty))\n' > empty/dune
  $ printf 'let x = 1\n' > empty/blank.mlx
  $ yuka islands --dir empty | tail -2
      ~navigation:(fun () -> Yuka.runtime_promise_map router (import "yuka/navigation.js"))
      []
  $ yuka islands --manifest --dir empty
  {}

include_subdirs qualified is rejected

  $ mkdir -p q/sub
  $ printf '(include_subdirs qualified)\n(library (name qualified))\n' > q/dune
  $ printf 'let[@client] make () = ()\n' > q/sub/counter.mlx
  $ yuka islands --dir q
  yuka islands: q/dune: include_subdirs qualified is not supported; use include_subdirs unqualified
  [1]
  $ yuka islands --manifest --dir q
  yuka islands: q/dune: include_subdirs qualified is not supported; use include_subdirs unqualified
  [1]

  $ mkdir -p q2/sub
  $ printf '(include_subdirs unqualified)\n(library (name qualified))\n' > q2/dune
  $ printf '(include_subdirs\n qualified)\n' > q2/sub/dune
  $ yuka islands --dir q2
  yuka islands: q2/sub/dune: include_subdirs qualified is not supported; use include_subdirs unqualified
  [1]

Errors

  $ yuka islands --dir missing
  yuka islands: missing: no such directory
  [1]

The library name comes from the dune file of the directory:

  $ mkdir nodune && printf 'let[@client] make () = ()\n' > nodune/counter.mlx
  $ yuka islands --dir nodune
  yuka islands: nodune/dune: no dune file; yuka islands reads the library name from it
  [1]
  $ mkdir two && printf '(library (name alpha))\n(library (name beta))\n' > two/dune
  $ yuka islands --dir two
  yuka islands: two/dune: yuka islands needs one library stanza in this file, not 2
  [1]
  $ mkdir noname && printf '(library (modes native))\n' > noname/dune
  $ yuka islands --dir noname
  yuka islands: noname/dune: the library has no (name ...)
  [1]

Like dune, a library without (name ...) takes its public_name when that is a
library name:

  $ mkdir pub && printf '(library (public_name app))\n' > pub/dune
  $ printf 'let[@client] make () = ()\n' > pub/counter.mlx
  $ yuka islands --manifest --dir pub
  {
    "App.Counter": "./pub/counter.js"
  }
  $ printf '(library (public_name my-app.sub))\n' > pub/dune
  $ yuka islands --manifest --dir pub
  yuka islands: pub/dune: the library has no (name ...), and its public_name my-app.sub is not a library name
  [1]
  $ mkdir comments && printf '; (library (name wrong))\n#| (library (name wrong)) |#\n#;(library (name wrong))\n(rule (targets x) (action (with-stdout-to x (echo "(library (name wrong))"))))\n(library\n (name right))\n' > comments/dune
  $ printf 'let[@client] make () = ()\n' > comments/counter.mlx
  $ yuka islands --manifest --dir comments
  {
    "Right.Counter": "./comments/counter.js"
  }
Block strings end at the end of the line, and can hold ( and ":

  $ mkdir block && printf 'let[@client] make () = ()\n' > block/counter.mlx
  $ cat > block/dune <<'X'
  > (rule (with-stdout-to x.txt (echo "\| a ( " (library (name wrong))
  >   "\> b )
  > )))
  > (library (name right))
  > X
  $ yuka islands --manifest --dir block
  {
    "Right.Counter": "./block/counter.js"
  }

  $ mkdir broken && printf '(library (name broken)\n' > broken/dune
  $ yuka islands --dir broken
  yuka islands: broken/dune: a ( has no )
  [1]

A let[@client] inside a comment or string is not an island

  $ mkdir text
  $ printf '(library (name text))\n' > text/dune
  $ cat > text/comment.mlx <<'EOT'
  > (* doc
  > let[@client] make () = 1
  >    (* nested "*)" *)
  > let[@client] make () = 2
  > *)
  > let x = 1
  > EOT
  $ cat > text/string.mlx <<'EOT'
  > let doc = "
  > let[@client] make () = 1
  > "
  > let quote = '"'
  > let quoted = {id|
  > let[@client] make () = 1
  > |id}
  > let plain = {|
  > let[@client] make () = 1
  > |}
  > EOT
  $ cat > text/prefix.mlx <<'EOT'
  > let[@clientfoo] make () = 1
  > EOT
  $ cat > text/real.mlx <<'EOT'
  > (* c *) let x = "(*"
  > let[@client] make () = 1
  > EOT
  $ yuka islands --manifest --dir text
  {
    "Text.Real": "./text/real.js"
  }

Subdirectories belong to the library only with include_subdirs unqualified

  $ mkdir -p scope/sub
  $ printf '(library (name scope))\n' > scope/dune
  $ printf 'let[@client] make () = 1\n' > scope/top.mlx
  $ printf 'let[@client] make () = 1\n' > scope/sub/other.mlx
  $ yuka islands --manifest --dir scope
  {
    "Scope.Top": "./scope/top.js"
  }
  $ printf '; (include_subdirs unqualified)\n(library (name scope))\n' > scope/dune
  $ yuka islands --manifest --dir scope
  {
    "Scope.Top": "./scope/top.js"
  }
  $ printf '(include_subdirs unqualified)\n(library (name scope))\n' > scope/dune
  $ yuka islands --manifest --dir scope
  {
    "Scope.Other": "./scope/sub/other.js",
    "Scope.Top": "./scope/top.js"
  }

A modules field limits the islands to the listed modules

  $ mkdir mods
  $ printf 'let[@client] make () = 1\n' > mods/alpha.mlx
  $ printf 'let[@client] make () = 1\n' > mods/beta.mlx
  $ printf 'let[@client] make () = 1\n' > mods/gamma.mlx
  $ printf '(library (name mods) (modules alpha gamma))\n' > mods/dune
  $ yuka islands --manifest --dir mods
  {
    "Mods.Alpha": "./mods/alpha.js",
    "Mods.Gamma": "./mods/gamma.js"
  }
  $ printf '(library (name mods) (modules :standard \\ beta))\n' > mods/dune
  $ yuka islands --manifest --dir mods
  {
    "Mods.Alpha": "./mods/alpha.js",
    "Mods.Gamma": "./mods/gamma.js"
  }
  $ printf '(library (name mods) (modules (:standard \\ alpha) \\ gamma))\n' > mods/dune
  $ yuka islands --manifest --dir mods
  {
    "Mods.Beta": "./mods/beta.js"
  }
  $ printf '(library (name mods) (modules_without_implementation alpha))\n' > mods/dune
  $ yuka islands --manifest --dir mods
  {
    "Mods.Alpha": "./mods/alpha.js",
    "Mods.Beta": "./mods/beta.js",
    "Mods.Gamma": "./mods/gamma.js"
  }
  $ printf '(library (name mods) (modules (:include mods.sexp)))\n' > mods/dune
  $ yuka islands --dir mods
  yuka islands: mods/dune: (:include ...) in (modules ...) is not supported; list the modules
  [1]

The manifest is valid JSON for non-ASCII and space characters

  $ mkdir "café dir"
  $ printf '(library (name cafe))\n' > "café dir/dune"
  $ printf 'let[@client] make () = 1\n' > "café dir/uno.mlx"
  $ yuka islands --manifest --dir "café dir"
  {
    "Cafe.Uno": "./café dir/uno.js"
  }
  $ yuka islands --manifest --dir "café dir" | node -e 'console.log(JSON.stringify(JSON.parse(require("fs").readFileSync(0,"utf8"))))'
  {"Cafe.Uno":"./café dir/uno.js"}

  $ mkdir "$(printf 'a\tb\\c')"
  $ printf '(library (name escaped))\n' > "$(printf 'a\tb\\c')/dune"
  $ printf 'let[@client] make () = 1\n' > "$(printf 'a\tb\\c')/widget.mlx"
  $ yuka islands --manifest --dir "$(printf 'a\tb\\c')"
  {
    "Escaped.Widget": "./a\u0009b\\c/widget.js"
  }
  $ yuka islands --manifest --dir "$(printf 'a\tb\\c')" | node -e 'console.log(JSON.parse(require("fs").readFileSync(0,"utf8"))["Escaped.Widget"] === "./a\tb\\c/widget.js")'
  true

let[@yuka.client] is an island too:

  $ mkdir ns && printf '(library (name ns))\n' > ns/dune
  $ printf 'let[@yuka.client] make () = ()\n' > ns/counter.mlx
  $ printf 'let[@yuka.clientx] make () = ()\n' > ns/other.mlx
  $ yuka islands --manifest --dir ns
  {
    "Ns.Counter": "./ns/counter.js"
  }
