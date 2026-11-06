Eager island

  $ mkdir eager
  $ printf 'let%%client make () = ()\n' > eager/counter.ml
  $ yuka-islands --library app eager
  type m
  type entry = Yuka.Client.entry
  external import : string -> m Yuka.Client.promise = "import"
  external register : m -> entry = "register" [@@mel.get]
  
  let registry =
    Yuka.Client.registry
      [ App.Counter.register ]

Lazy island, path relative to the working directory

  $ mkdir -p up/shared up/client
  $ printf 'let%%client[@yuka.lazy] make () = ()\n' > up/shared/related.mlx
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
        [ Yuka.Client.lazy_entry ~name:"Demo_shared.Related" (fun () ->
                Yuka.Client.promise_map register (import "../shared/related.js")) ]
      [ Demo_shared.Counter.register ]
  $ cd ../..

Lazy attribute after a space, nested directory, file without island

  $ mkdir -p nested/deep
  $ printf '(include_subdirs unqualified)\n' > nested/dune
  $ printf 'let%%client [@yuka.lazy] make () = ()\n' > nested/deep/map.ml
  $ printf 'let%%client make () = ()\n' > nested/zed.ml
  $ printf 'let make () = ()\n(* let%%client in a comment line is not at line start *)\n' > nested/plain.ml
  $ printf '  let%%client make () = ()\n' > nested/indented.ml
  $ yuka-islands --library app nested
  type m
  type entry = Yuka.Client.entry
  external import : string -> m Yuka.Client.promise = "import"
  external register : m -> entry = "register" [@@mel.get]
  
  let registry =
    Yuka.Client.registry
      ~lazy_entries:
        [ Yuka.Client.lazy_entry ~name:"App.Map" (fun () ->
                Yuka.Client.promise_map register (import "./nested/deep/map.js")) ]
      [ App.Zed.register ]

Two libraries, sorted output

  $ mkdir lib_b lib_a
  $ printf 'let%%client make () = ()\n' > lib_b/same.ml
  $ printf 'let%%client make () = ()\n' > lib_a/same.ml
  $ yuka-islands --library b lib_b --library a lib_a
  type m
  type entry = Yuka.Client.entry
  external import : string -> m Yuka.Client.promise = "import"
  external register : m -> entry = "register" [@@mel.get]
  
  let registry =
    Yuka.Client.registry
      [ A.Same.register
      ; B.Same.register ]

No island at all

  $ mkdir empty
  $ printf 'let x = 1\n' > empty/x.ml
  $ yuka-islands --library e empty | tail -3
  let registry =
    Yuka.Client.registry
      []

include_subdirs qualified is rejected

  $ mkdir -p q/sub
  $ printf '(include_subdirs qualified)\n(library (name q))\n' > q/dune
  $ printf 'let%%client make () = ()\n' > q/sub/a.ml
  $ yuka-islands --library q q
  yuka-islands: q/dune: include_subdirs qualified is not supported; use include_subdirs unqualified
  [1]

  $ mkdir -p q2/sub
  $ printf '(include_subdirs unqualified)\n' > q2/dune
  $ printf '(include_subdirs\n qualified)\n' > q2/sub/dune
  $ yuka-islands --library q q2
  yuka-islands: q2/sub/dune: include_subdirs qualified is not supported; use include_subdirs unqualified
  [1]

include_subdirs unqualified is accepted

  $ mkdir u
  $ printf '(include_subdirs unqualified)\n' > u/dune
  $ printf 'let%%client make () = ()\n' > u/a.ml
  $ yuka-islands --library u u | tail -1
      [ U.A.register ]

Errors

  $ yuka-islands --library x missing
  yuka-islands: missing: no such directory
  [1]

  $ yuka-islands
  yuka-islands: usage: yuka-islands --library NAME DIR [--library NAME DIR ...]
  [1]

  $ yuka-islands --library x
  yuka-islands: unexpected argument "--library"; expected --library NAME DIR
  [1]

  $ yuka-islands --library x eager stray
  yuka-islands: unexpected argument "stray"; expected --library NAME DIR
  [1]

A let%client inside a comment or string is not an island

  $ mkdir text
  $ cat > text/comment.ml <<'EOT'
  > (* doc
  > let%client make () = 1
  >    (* nested "*)" *)
  > let%client make () = 2
  > *)
  > let x = 1
  > EOT
  $ cat > text/string.ml <<'EOT'
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
  $ cat > text/prefix.ml <<'EOT'
  > let%clientfoo make () = 1
  > EOT
  $ cat > text/real.ml <<'EOT'
  > (* c *) let x = "(*"
  > let%client make () = 1
  > EOT
  $ yuka-islands --library t text | tail -3
  let registry =
    Yuka.Client.registry
      [ T.Real.register ]

The lazy attribute may sit on the binding or on the next line

  $ mkdir attr
  $ cat > attr/trailing.ml <<'EOT'
  > let%client make () = 1 [@@yuka.lazy]
  > EOT
  $ cat > attr/nextline.ml <<'EOT'
  > let%client
  >   [@yuka.lazy]
  >   make () = 1
  > EOT
  $ cat > attr/commented.ml <<'EOT'
  > (* [@@yuka.lazy] *)
  > let%client make () = 1
  > EOT
  $ yuka-islands --library a attr | tail -7
    Yuka.Client.registry
      ~lazy_entries:
        [ Yuka.Client.lazy_entry ~name:"A.Nextline" (fun () ->
                Yuka.Client.promise_map register (import "./attr/nextline.js"))
        ; Yuka.Client.lazy_entry ~name:"A.Trailing" (fun () ->
                Yuka.Client.promise_map register (import "./attr/trailing.js")) ]
      [ A.Commented.register ]

Subdirectories belong to the library only with include_subdirs unqualified

  $ mkdir -p scope/own scope/sub
  $ printf '(library (name scope))\n' > scope/dune
  $ printf 'let%%client make () = 1\n' > scope/top.ml
  $ printf 'let%%client make () = 1\n' > scope/sub/other.ml
  $ yuka-islands --library s scope | tail -1
      [ S.Top.register ]
  $ printf '; (include_subdirs unqualified)\n(library (name scope))\n' > scope/dune
  $ yuka-islands --library s scope | tail -1
      [ S.Top.register ]
  $ printf '(include_subdirs unqualified)\n(library (name scope))\n' > scope/dune
  $ yuka-islands --library s scope | tail -2
      [ S.Other.register
      ; S.Top.register ]

A modules field is rejected

  $ mkdir mods
  $ printf '(library (name mods) (modules a))\n' > mods/dune
  $ printf 'let%%client make () = 1\n' > mods/a.ml
  $ yuka-islands --library m mods
  yuka-islands: mods/dune: (modules ...) is not supported
  [1]
  $ printf '(library (name mods) (modules_without_implementation a))\n' > mods/dune
  $ yuka-islands --library m mods | tail -1
      [ M.A.register ]
