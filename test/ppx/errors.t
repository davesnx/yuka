  $ run() { mlx-pp $1.mlx > $1.ml && ./pp.exe --impl $1.ml; }

Unknown attribute:

  $ cat > a.mlx <<'X'
  > let x = <div href="/x" />
  > X
  $ run a
  File "a.mlx", line 1, characters 18-22:
  1 | let x = <div href="/x" />
                        ^^^^
  Error: [yuka] The attribute 'href' is not valid on a 'div' element.
  [1]

Unknown tag:

  $ cat > b.mlx <<'X'
  > let x = <blorp />
  > X
  $ run b
  File "b.mlx", line 1, characters 8-14:
  1 | let x = <blorp />
              ^^^^^^
  Error: [yuka] HTML tag 'blorp' does not exist.
  [1]

Lint, open:

  $ cat > c.mlx <<'X'
  > open Yuka.State
  > X
  $ run c
  File "c.mlx", line 1, characters 0-15:
  1 | open Yuka.State
      ^^^^^^^^^^^^^^^
  Error: [yuka] open Yuka.State is not allowed: reads must be written State.get so that the ppx can find holes (open Yuka is allowed: State.get still works).
  [1]

Lint, local open:

  $ cat > d.mlx <<'X'
  > let x = Yuka.State.(get s)
  > X
  $ run d
  File "d.mlx", line 1, characters 8-26:
  1 | let x = Yuka.State.(get s)
              ^^^^^^^^^^^^^^^^^^
  Error: [yuka] a local open of Yuka.State is not allowed: reads must be written State.get so that the ppx can find holes (open Yuka is allowed: State.get still works).
  [1]

Lint, let open:

  $ cat > e.mlx <<'X'
  > let x = let open Yuka.State in get s
  > X
  $ run e
  File "e.mlx", line 1, characters 8-36:
  1 | let x = let open Yuka.State in get s
              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: [yuka] a local open of Yuka.State is not allowed: reads must be written State.get so that the ppx can find holes (open Yuka is allowed: State.get still works).
  [1]

Lint, module alias:

  $ cat > f.mlx <<'X'
  > module S = Yuka.State
  > X
  $ run f
  File "f.mlx", line 1, characters 0-21:
  1 | module S = Yuka.State
      ^^^^^^^^^^^^^^^^^^^^^
  Error: [yuka] a module alias of Yuka.State is not allowed: reads must be written State.get so that the ppx can find holes (open Yuka is allowed: State.get still works).
  [1]

Allowed alias named State:

  $ cat > g.mlx <<'X'
  > module State = Yuka.State
  > X
  $ run g
  module State = Yuka.State

Polymorphic variant:

  $ cat > h0.mlx <<'X'
  > type t = [ `A | `B ] [@@deriving codec]
  > X
  $ run h0
  File "h0.mlx", line 1, characters 9-20:
  1 | type t = [ `A | `B ] [@@deriving codec]
               ^^^^^^^^^^^
  Error: [yuka] polymorphic variants are not supported
  [1]

GADT:

  $ cat > h1.mlx <<'X'
  > type 'a t = I : int -> int t [@@deriving codec]
  > X
  $ run h1
  File "h1.mlx", line 1, characters 12-28:
  1 | type 'a t = I : int -> int t [@@deriving codec]
                  ^^^^^^^^^^^^^^^^
  Error: [yuka] GADT constructors are not supported
  [1]

Module-level State:

  $ cat > s0.mlx <<'X'
  > let count = State.make 0
  > X
  $ run s0
  File "s0.mlx", line 1, characters 0-24:
  1 | let count = State.make 0
      ^^^^^^^^^^^^^^^^^^^^^^^^
  Error: [yuka] A module-level State.make is one value for the whole server process: every request would read and write the same State. Create the State inside a function. If only client code paths write it, mark the binding with [@@yuka.shared].
  [1]

  $ cat > s1.mlx <<'X'
  > let total = Yuka.State.memo (fun () -> 1)
  > X
  $ run s1
  File "s1.mlx", line 1, characters 0-41:
  1 | let total = Yuka.State.memo (fun () -> 1)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: [yuka] A module-level State.memo is one value for the whole server process: every request would read and write the same State. Create the State inside a function. If only client code paths write it, mark the binding with [@@yuka.shared].
  [1]

  $ cat > s2.mlx <<'X'
  > module M = struct let c : int Yuka.State.t = Yuka.State.make 0 end
  > X
  $ run s2
  File "s2.mlx", line 1, characters 18-62:
  1 | module M = struct let c : int Yuka.State.t = Yuka.State.make 0 end
                        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: [yuka] A module-level State.make is one value for the whole server process: every request would read and write the same State. Create the State inside a function. If only client code paths write it, mark the binding with [@@yuka.shared].
  [1]

Module-level State marked shared, and State inside a function:

  $ cat > s3.mlx <<'X'
  > let count = State.make 0 [@@yuka.shared]
  > let make () = State.make 0
  > X
  $ run s3
  let count = State.make 0[@@yuka.shared ]
  let make () = State.make 0

Unsupported type:

  $ cat > h2.mlx <<'X'
  > type t = int -> int [@@deriving codec]
  > X
  $ run h2
  File "h2.mlx", line 1, characters 9-19:
  1 | type t = int -> int [@@deriving codec]
               ^^^^^^^^^^
  Error: [yuka] cannot derive a codec for this type
  [1]

Slots:

  $ cat > h3.mlx <<'X'
  > let%client make ~(children : int) () = <p />
  > X
  $ run h3
  File "h3.mlx", line 1, characters 18-32:
  1 | let%client make ~(children : int) () = <p />
                        ^^^^^^^^^^^^^^
  Error: [yuka] ~children must be written ~(children : Yuka.slot)
  [1]

Missing annotation:

  $ cat > h4.mlx <<'X'
  > let%client make ~a () = <p />
  > X
  $ run h4
  File "h4.mlx", line 1, characters 17-18:
  1 | let%client make ~a () = <p />
                       ^
  Error: [yuka] the argument 'a' needs a type annotation
  [1]

Last parameter:

  $ cat > h5.mlx <<'X'
  > let%client make ~(a : int) = <p />
  > X
  $ run h5
  File "h5.mlx", line 1, characters 18-25:
  1 | let%client make ~(a : int) = <p />
                        ^^^^^^^
  Error: [yuka] the last parameter must be ()
  [1]

Yuka.Client with another prop:

  $ cat > h6.mlx <<'X'
  > let x = <Yuka.Client other=1><M a=1 /></Yuka.Client>
  > X
  $ run h6
  File "h6.mlx", line 1, characters 8-20:
  1 | let x = <Yuka.Client other=1><M a=1 /></Yuka.Client>
              ^^^^^^^^^^^^
  Error: [yuka] Yuka.Client takes no props except loading
  [1]

Yuka.Client without child:

  $ cat > h7.mlx <<'X'
  > let x = <Yuka.Client></Yuka.Client>
  > X
  $ run h7
  File "h7.mlx", line 1, characters 8-20:
  1 | let x = <Yuka.Client></Yuka.Client>
              ^^^^^^^^^^^^
  Error: [yuka] Yuka.Client needs exactly one child, a component tag such as <M a=1 />
  [1]

Yuka.Client with two children:

  $ cat > h8.mlx <<'X'
  > let x = <Yuka.Client><M /><N /></Yuka.Client>
  > X
  $ run h8
  File "h8.mlx", line 1, characters 8-20:
  1 | let x = <Yuka.Client><M /><N /></Yuka.Client>
              ^^^^^^^^^^^^
  Error: [yuka] Yuka.Client needs exactly one child, a component tag such as <M a=1 />
  [1]

Yuka.Client with a tag child:

  $ cat > h9.mlx <<'X'
  > let x = <Yuka.Client><p /></Yuka.Client>
  > X
  $ run h9
  File "h9.mlx", line 1, characters 8-20:
  1 | let x = <Yuka.Client><p /></Yuka.Client>
              ^^^^^^^^^^^^
  Error: [yuka] Yuka.Client needs exactly one child, a component tag such as <M a=1 />
  [1]

let%client with a reserved argument:

  $ cat > h10.mlx <<'X'
  > let%client make ~(loading : int) () = <p />
  > X
  $ run h10
  File "h10.mlx", line 1, characters 18-31:
  1 | let%client make ~(loading : int) () = <p />
                        ^^^^^^^^^^^^^
  Error: [yuka] the argument 'loading' is reserved for the start strategy
  [1]

SVG attribute on a tag that is not SVG:

  $ cat > h11.mlx <<'X'
  > let x = <div strokeDasharray="1" />
  > X
  $ run h11
  File "h11.mlx", line 1, characters 29-32:
  1 | let x = <div strokeDasharray="1" />
                                   ^^^
  Error: [yuka] The attribute 'strokeDasharray' is not valid on a 'div' element.
  [1]

Template ids depend on the file name, line and column, not on the directory:

  $ mkdir d1 d2
  $ printf 'let x = <ul><li>"a"</li><li>"b"</li></ul>\nlet y = <ol><li>"a"</li><li>"b"</li></ol>\n' > d1/t.mlx
  $ cp d1/t.mlx d2/t.mlx
  $ ids() { mlx-pp $1/t.mlx > $1/t.ml && ./pp.exe --impl $1/t.ml | grep -o 'template "[^"]*"'; }
  $ ids d1
  template "t:1:8"
  template "t:2:8"
  $ ids d2
  template "t:1:8"
  template "t:2:8"

Await without async:

  $ cat > w0.mlx <<'X'
  > let x = <Yuka.Await loading="l">(fun v -> <p />)</Yuka.Await>
  > X
  $ run w0
  File "w0.mlx", line 1, characters 8-19:
  1 | let x = <Yuka.Await loading="l">(fun v -> <p />)</Yuka.Await>
              ^^^^^^^^^^^
  Error: [yuka] Yuka.Await needs the prop 'async'
  [1]

Await without loading:

  $ cat > w1.mlx <<'X'
  > let x = <Yuka.Await async=a>(fun v -> <p />)</Yuka.Await>
  > X
  $ run w1
  File "w1.mlx", line 1, characters 8-19:
  1 | let x = <Yuka.Await async=a>(fun v -> <p />)</Yuka.Await>
              ^^^^^^^^^^^
  Error: [yuka] Yuka.Await needs the prop 'loading'
  [1]

Await with a child that is not a function:

  $ cat > w2.mlx <<'X'
  > let x = <Yuka.Await async=a loading="l"><p /></Yuka.Await>
  > X
  $ run w2
  File "w2.mlx", line 1, characters 8-19:
  1 | let x = <Yuka.Await async=a loading="l"><p /></Yuka.Await>
              ^^^^^^^^^^^
  Error: [yuka] Yuka.Await needs exactly one child, a function such as (fun value -> ...)
  [1]

Await without a child:

  $ cat > w3.mlx <<'X'
  > let x = <Yuka.Await async=a loading="l" />
  > X
  $ run w3
  File "w3.mlx", line 1, characters 8-19:
  1 | let x = <Yuka.Await async=a loading="l" />
              ^^^^^^^^^^^
  Error: [yuka] Yuka.Await needs exactly one child, a function such as (fun value -> ...)
  [1]

Await with two children:

  $ cat > w4.mlx <<'X'
  > let x = <Yuka.Await async=a loading="l">(fun v -> <p />) (fun v -> <p />)</Yuka.Await>
  > X
  $ run w4
  File "w4.mlx", line 1, characters 8-19:
  1 | let x = <Yuka.Await async=a loading="l">(fun v -> <p />) (fun v -> <p />)</Yuka.Await>
              ^^^^^^^^^^^
  Error: [yuka] Yuka.Await needs exactly one child, a function such as (fun value -> ...)
  [1]

Await with an unknown prop:

  $ cat > w5.mlx <<'X'
  > let x = <Yuka.Await async=a loading="l" other=1>(fun v -> <p />)</Yuka.Await>
  > X
  $ run w5
  File "w5.mlx", line 1, characters 8-19:
  1 | let x = <Yuka.Await async=a loading="l" other=1>(fun v -> <p />)</Yuka.Await>
              ^^^^^^^^^^^
  Error: [yuka] Yuka.Await takes async, loading and failed
  [1]

Nested let%client in a module:

  $ cat > n0.mlx <<'X'
  > module M = struct
  >   let%client make ~(a : int) () = <p />
  > end
  > X
  $ run n0
  File "n0.mlx", line 2, characters 2-39:
  2 |   let%client make ~(a : int) () = <p />
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: [yuka] let%client is allowed only at the top level of a file, not inside a module or a function
  [1]

Nested let%client in a local module:

  $ cat > n1.mlx <<'X'
  > let f () =
  >   let module M = struct
  >     let%client make ~(a : int) () = <p />
  >   end in
  >   ()
  > X
  $ run n1
  File "n1.mlx", line 3, characters 4-41:
  3 |     let%client make ~(a : int) () = <p />
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: [yuka] let%client is allowed only at the top level of a file, not inside a module or a function
  [1]

Unknown yuka attribute on let%client:

  $ cat > n2.mlx <<'X'
  > let%client[@yuka.eager] make ~(a : int) () = <p />
  > X
  $ run n2
  File "n2.mlx", line 1, characters 10-23:
  1 | let%client[@yuka.eager] make ~(a : int) () = <p />
                ^^^^^^^^^^^^^
  Error: [yuka] unknown attribute [@yuka.eager] on a let%client binding
  [1]

Unknown yuka attribute on the binding:

  $ cat > n3.mlx <<'X'
  > let%client make ~(a : int) () = <p /> [@@yuka.other]
  > X
  $ run n3
  File "n3.mlx", line 1, characters 38-52:
  1 | let%client make ~(a : int) () = <p /> [@@yuka.other]
                                            ^^^^^^^^^^^^^^
  Error: [yuka] unknown attribute [@yuka.other] on a let%client binding
  [1]
