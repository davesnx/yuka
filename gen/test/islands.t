Every island is a lazy entry

  $ mkdir one
  $ printf 'let%%client make () = ()\n' > one/counter.mlx
  $ yuka-islands --library app one
  type m
  type entry = Yuka.Client.entry
  external import : string -> m Yuka.Client.promise = "import"
  external register : m -> entry = "register" [@@mel.get]
  
  let registry =
    Yuka.Client.registry
      ~lazy_entries:
        [ Yuka.Client.lazy_entry ~name:"App.Counter" (fun () ->
                Yuka.Client.promise_map register (import "./one/counter.js")) ]
      []

  $ yuka-islands --manifest --library app one
  {
    "App.Counter": "./one/counter.js"
  }

Two islands, path relative to the working directory

  $ mkdir -p up/shared up/client
  $ printf 'let%%client make () = ()\n' > up/shared/related.mlx
  $ printf 'let%%client make () = ()\n' > up/shared/counter.mlx
  $ cd up/client
  $ yuka-islands --library demo_shared ../shared
  type m
  type entry = Yuka.Client.entry
  external import : string -> m Yuka.Client.promise = "import"
  external register : m -> entry = "register" [@@mel.get]
  
  let registry =
    Yuka.Client.registry
      ~lazy_entries:
        [ Yuka.Client.lazy_entry ~name:"Demo_shared.Counter" (fun () ->
                Yuka.Client.promise_map register (import "../shared/counter.js"))
        ; Yuka.Client.lazy_entry ~name:"Demo_shared.Related" (fun () ->
                Yuka.Client.promise_map register (import "../shared/related.js")) ]
      []
  $ yuka-islands --manifest --library demo_shared ../shared
  {
    "Demo_shared.Counter": "../shared/counter.js",
    "Demo_shared.Related": "../shared/related.js"
  }
  $ cd ../..

The manifest path is the import path of the same island

  $ yuka-islands --library demo_shared up/shared | grep -o 'import "[^"]*"' | sed 's/import //' | sort > imports
  $ yuka-islands --manifest --library demo_shared up/shared | grep -o '"[^"]*\.js"' | sort > paths
  $ cat imports
  "./up/shared/counter.js"
  "./up/shared/related.js"
  $ diff imports paths

Nested directory with include_subdirs unqualified, file without island

  $ mkdir -p nested/deep
  $ printf '(include_subdirs unqualified)\n' > nested/dune
  $ printf 'let%%client make () = ()\n' > nested/deep/map.mlx
  $ printf 'let%%client make () = ()\n' > nested/zed.mlx
  $ printf 'let make () = ()\n(* let%%client in a comment line is not at line start *)\n' > nested/plain.mlx
  $ printf '  let%%client make () = ()\n' > nested/indented.mlx
  $ yuka-islands --manifest --library app nested
  {
    "App.Map": "./nested/deep/map.js",
    "App.Zed": "./nested/zed.js"
  }

Two libraries, sorted output

  $ mkdir lib_b lib_a
  $ printf 'let%%client make () = ()\n' > lib_b/same.mlx
  $ printf 'let%%client make () = ()\n' > lib_a/same.mlx
  $ yuka-islands --manifest --library b lib_b --library a lib_a
  {
    "A.Same": "./lib_a/same.js",
    "B.Same": "./lib_b/same.js"
  }
  $ yuka-islands --library b lib_b --library a lib_a | grep -c lazy_entry
  2

Only .mlx files are scanned

  $ mkdir plain
  $ printf 'let%%client make () = ()\n' > plain/old.ml
  $ printf 'let%%client make () = ()\n' > plain/new.mlx
  $ yuka-islands --manifest --library p plain
  {
    "P.New": "./plain/new.js"
  }

No island at all

  $ mkdir empty
  $ printf 'let x = 1\n' > empty/x.mlx
  $ yuka-islands --library e empty | tail -2
    Yuka.Client.registry
      []
  $ yuka-islands --manifest --library e empty
  {}

include_subdirs qualified is rejected

  $ mkdir -p q/sub
  $ printf '(include_subdirs qualified)\n(library (name q))\n' > q/dune
  $ printf 'let%%client make () = ()\n' > q/sub/a.mlx
  $ yuka-islands --library q q
  yuka-islands: q/dune: include_subdirs qualified is not supported; use include_subdirs unqualified
  [1]
  $ yuka-islands --manifest --library q q
  yuka-islands: q/dune: include_subdirs qualified is not supported; use include_subdirs unqualified
  [1]

  $ mkdir -p q2/sub
  $ printf '(include_subdirs unqualified)\n' > q2/dune
  $ printf '(include_subdirs\n qualified)\n' > q2/sub/dune
  $ yuka-islands --library q q2
  yuka-islands: q2/sub/dune: include_subdirs qualified is not supported; use include_subdirs unqualified
  [1]

Errors

  $ yuka-islands --library x missing
  yuka-islands: missing: no such directory
  [1]

  $ yuka-islands
  yuka-islands: usage: yuka-islands [--manifest] --library NAME DIR [--library NAME DIR ...]
  [1]

  $ yuka-islands --manifest
  yuka-islands: usage: yuka-islands [--manifest] --library NAME DIR [--library NAME DIR ...]
  [1]

  $ yuka-islands --library x
  yuka-islands: unexpected argument "--library"; expected [--manifest] --library NAME DIR
  [1]

  $ yuka-islands --library x one stray
  yuka-islands: unexpected argument "stray"; expected [--manifest] --library NAME DIR
  [1]

A let%client inside a comment or string is not an island

  $ mkdir text
  $ cat > text/comment.mlx <<'EOT'
  > (* doc
  > let%client make () = 1
  >    (* nested "*)" *)
  > let%client make () = 2
  > *)
  > let x = 1
  > EOT
  $ cat > text/string.mlx <<'EOT'
  > let doc = "
  > let%client make () = 1
  > "
  > let quote = '"'
  > let quoted = {id|
  > let%client make () = 1
  > |id}
  > let plain = {|
  > let%client make () = 1
  > |}
  > EOT
  $ cat > text/prefix.mlx <<'EOT'
  > let%clientfoo make () = 1
  > EOT
  $ cat > text/real.mlx <<'EOT'
  > (* c *) let x = "(*"
  > let%client make () = 1
  > EOT
  $ yuka-islands --manifest --library t text
  {
    "T.Real": "./text/real.js"
  }

Subdirectories belong to the library only with include_subdirs unqualified

  $ mkdir -p scope/sub
  $ printf '(library (name scope))\n' > scope/dune
  $ printf 'let%%client make () = 1\n' > scope/top.mlx
  $ printf 'let%%client make () = 1\n' > scope/sub/other.mlx
  $ yuka-islands --manifest --library s scope
  {
    "S.Top": "./scope/top.js"
  }
  $ printf '; (include_subdirs unqualified)\n(library (name scope))\n' > scope/dune
  $ yuka-islands --manifest --library s scope
  {
    "S.Top": "./scope/top.js"
  }
  $ printf '(include_subdirs unqualified)\n(library (name scope))\n' > scope/dune
  $ yuka-islands --manifest --library s scope
  {
    "S.Other": "./scope/sub/other.js",
    "S.Top": "./scope/top.js"
  }

A modules field is rejected

  $ mkdir mods
  $ printf '(library (name mods) (modules a))\n' > mods/dune
  $ printf 'let%%client make () = 1\n' > mods/a.mlx
  $ yuka-islands --library m mods
  yuka-islands: mods/dune: (modules ...) is not supported
  [1]
  $ printf '(library (name mods) (modules_without_implementation a))\n' > mods/dune
  $ yuka-islands --manifest --library m mods
  {
    "M.A": "./mods/a.js"
  }

The manifest is valid JSON for non-ASCII and space characters

  $ mkdir "café dir"
  $ printf 'let%%client make () = 1\n' > "café dir/uno.mlx"
  $ yuka-islands --manifest --library l "café dir"
  {
    "L.Uno": "./café dir/uno.js"
  }
  $ yuka-islands --manifest --library l "café dir" | node -e 'console.log(JSON.stringify(JSON.parse(require("fs").readFileSync(0,"utf8"))))'
  {"L.Uno":"./café dir/uno.js"}

  $ mkdir "$(printf 'a\tb\\c')"
  $ printf 'let%%client make () = 1\n' > "$(printf 'a\tb\\c')/x.mlx"
  $ yuka-islands --manifest --library l "$(printf 'a\tb\\c')"
  {
    "L.X": "./a\u0009b\\c/x.js"
  }
  $ yuka-islands --manifest --library l "$(printf 'a\tb\\c')" | node -e 'console.log(JSON.parse(require("fs").readFileSync(0,"utf8"))["L.X"] === "./a\tb\\c/x.js")'
  true
