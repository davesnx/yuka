  $ native() { ./pp.exe -cookie 'compilation-mode="ocaml"' "$@"; }
  $ browser() { ./pp.exe -cookie 'compilation-mode="melange"' "$@"; }

  $ cat > comment.ml <<'EOF'
  > let%action add =
  >   Yuka.Action.mutation ~input:input_codec ~output:codec
  >     (fun ctx input -> Store.add_comment ctx input)
  > 
  > let shared = "kept on both targets"
  > 
  > module Thread = struct
  >   let%action range =
  >     Yuka.Action.query ~output:(Yuka.Codec.list codec) ~input:range_codec
  >       (fun _ctx range -> Yuka.Async.return (Store.comments range))
  > end
  > EOF

The server gets the declaration with its name, and the registration of the
implementation. The name is the library, the module path and the binding:

  $ native -cookie 'library-name="demo_shared"' --impl comment.ml
  let add =
    (fun action implementation ->
       Yuka.Server.Action.implement action implementation; action)
      (Yuka.Action.mutation ~name:"demo_shared.Comment.add" ~input:input_codec
         ~output:codec) (fun ctx input -> Store.add_comment ctx input)
  let shared = "kept on both targets"
  module Thread =
    struct
      let range =
        (fun action implementation ->
           Yuka.Server.Action.implement action implementation; action)
          (Yuka.Action.query ~name:"demo_shared.Comment.Thread.range"
             ~input:range_codec ~output:(Yuka.Codec.list codec))
          (fun _ctx range -> Yuka.Async.return (Store.comments range))
    end

The browser gets the declaration only, with the same name:

  $ browser -cookie 'library-name="demo_shared"' --impl comment.ml
  let add =
    Yuka.Action.mutation ~name:"demo_shared.Comment.add" ~input:input_codec
      ~output:codec
  let shared = "kept on both targets"
  module Thread =
    struct
      let range =
        Yuka.Action.query ~name:"demo_shared.Comment.Thread.range"
          ~input:range_codec ~output:(Yuka.Codec.list codec)
    end

With no library-name cookie (an executable), the name is the module path:

  $ native --impl comment.ml | grep name
      (Yuka.Action.mutation ~name:"Comment.add" ~input:input_codec
          (Yuka.Action.query ~name:"Comment.Thread.range" ~input:range_codec

Open Yuka makes Action mean Yuka.Action:

  $ cat > opened.ml <<'EOF'
  > open Yuka
  > let%action stats = Action.query ~input:Codec.string ~output:Codec.int (fun _ s -> Async.return (String.length s))
  > EOF
  $ native --impl opened.ml
  open Yuka
  let stats =
    (fun action implementation ->
       Yuka.Server.Action.implement action implementation; action)
      (Action.query ~name:"Opened.stats" ~input:Codec.string ~output:Codec.int)
      (fun _ s -> Async.return (String.length s))

A file with no let%action needs no cookie:

  $ cat > plain.ml <<'EOF'
  > let x = Yuka.Action.mutation ~name:"x" ~input:Yuka.Codec.int ~output:Yuka.Codec.int
  > EOF
  $ ./pp.exe --impl plain.ml
  let x =
    Yuka.Action.mutation ~name:"x" ~input:Yuka.Codec.int ~output:Yuka.Codec.int

No compilation-mode cookie:

  $ ./pp.exe --impl comment.ml
  File "comment.ml", line 1, characters 4-10:
  1 | let%action add =
          ^^^^^^
  Error: [yuka] let%action needs the compilation-mode cookie to know if it compiles for the server or the browser: use (lang dune 3.26) or later in dune-project, or pass the cookie to the ppx: (preprocess (pps yuka.ppx -- --cookie "compilation-mode=\"ocaml\"")) and (melange.preprocess (pps yuka.ppx -- --cookie "compilation-mode=\"melange\""))
  [1]

A compilation-mode cookie that is not "ocaml" or "melange":

  $ ./pp.exe -cookie 'compilation-mode="js"' --impl comment.ml
  File "comment.ml", line 1, characters 4-10:
  1 | let%action add =
          ^^^^^^
  Error: [yuka] let%action: the compilation-mode cookie is "js"; it must be "ocaml" or "melange"
  [1]

  $ shape() { printf '%s\n' "$1" > shape.ml; native --impl shape.ml; }

No implementation:

  $ shape 'let%action a = Yuka.Action.mutation ~input:i ~output:o'
  File "shape.ml", line 1, characters 15-54:
  1 | let%action a = Yuka.Action.mutation ~input:i ~output:o
                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: [yuka] the implementation is missing. let%action takes the form: let%action <name> = Yuka.Action.mutation ~input:<codec> ~output:<codec> (fun ctx input -> ...), or the same with Yuka.Action.query
  [1]

The ppx sets the name:

  $ shape 'let%action a = Yuka.Action.mutation ~name:"a" ~input:i ~output:o (fun _ x -> x)'
  File "shape.ml", line 1, characters 42-45:
  1 | let%action a = Yuka.Action.mutation ~name:"a" ~input:i ~output:o (fun _ x -> x)
                                                ^^^
  Error: [yuka] let%action sets the name of the action: remove ~name. let%action takes the form: let%action <name> = Yuka.Action.mutation ~input:<codec> ~output:<codec> (fun ctx input -> ...), or the same with Yuka.Action.query
  [1]

Not mutation or query:

  $ shape 'let%action a = Yuka.Action.with_form ~input:i ~output:o (fun _ x -> x)'
  File "shape.ml", line 1, characters 15-36:
  1 | let%action a = Yuka.Action.with_form ~input:i ~output:o (fun _ x -> x)
                     ^^^^^^^^^^^^^^^^^^^^^
  Error: [yuka] Yuka.Action.with_form cannot be a let%action: use Yuka.Action.mutation or Yuka.Action.query. let%action takes the form: let%action <name> = Yuka.Action.mutation ~input:<codec> ~output:<codec> (fun ctx input -> ...), or the same with Yuka.Action.query
  [1]
  $ shape 'let%action a = Yuka.Form.action ~input:i ~output:o (fun _ x -> x)'
  File "shape.ml", line 1, characters 15-65:
  1 | let%action a = Yuka.Form.action ~input:i ~output:o (fun _ x -> x)
                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: [yuka] expected Yuka.Action.mutation or Yuka.Action.query. let%action takes the form: let%action <name> = Yuka.Action.mutation ~input:<codec> ~output:<codec> (fun ctx input -> ...), or the same with Yuka.Action.query
  [1]
  $ shape 'let%action a = 1'
  File "shape.ml", line 1, characters 15-16:
  1 | let%action a = 1
                     ^
  Error: [yuka] expected Yuka.Action.mutation or Yuka.Action.query. let%action takes the form: let%action <name> = Yuka.Action.mutation ~input:<codec> ~output:<codec> (fun ctx input -> ...), or the same with Yuka.Action.query
  [1]

Action without open Yuka, or with a local Action module:

  $ shape 'let%action a = Action.mutation ~input:i ~output:o (fun _ x -> x)'
  File "shape.ml", line 1, characters 15-30:
  1 | let%action a = Action.mutation ~input:i ~output:o (fun _ x -> x)
                     ^^^^^^^^^^^^^^^
  Error: [yuka] Action here is not Yuka.Action (the ppx knows only an open Yuka at the top of the file, and no module Action of the file): write Yuka.Action.mutation. let%action takes the form: let%action <name> = Yuka.Action.mutation ~input:<codec> ~output:<codec> (fun ctx input -> ...), or the same with Yuka.Action.query
  [1]
  $ shape 'open Yuka
  > module Action = struct end
  > let%action a = Action.mutation ~input:i ~output:o (fun _ x -> x)'
  File "shape.ml", line 3, characters 15-30:
  3 | let%action a = Action.mutation ~input:i ~output:o (fun _ x -> x)
                     ^^^^^^^^^^^^^^^
  Error: [yuka] Action here is not Yuka.Action (the ppx knows only an open Yuka at the top of the file, and no module Action of the file): write Yuka.Action.mutation. let%action takes the form: let%action <name> = Yuka.Action.mutation ~input:<codec> ~output:<codec> (fun ctx input -> ...), or the same with Yuka.Action.query
  [1]
  $ shape 'open Yuka
  > module M = struct
  >   module Action = struct let mutation ~input:_ ~output:_ f = f end
  >   let%action a = Action.mutation ~input:i ~output:o (fun _ x -> x)
  > end'
  File "shape.ml", line 4, characters 17-32:
  4 |   let%action a = Action.mutation ~input:i ~output:o (fun _ x -> x)
                       ^^^^^^^^^^^^^^^
  Error: [yuka] Action here is not Yuka.Action (the ppx knows only an open Yuka at the top of the file, and no module Action of the file): write Yuka.Action.mutation. let%action takes the form: let%action <name> = Yuka.Action.mutation ~input:<codec> ~output:<codec> (fun ctx input -> ...), or the same with Yuka.Action.query
  [1]

Missing, repeated and unknown labels; two implementations:

  $ shape 'let%action a = Yuka.Action.mutation ~output:o (fun _ x -> x)'
  File "shape.ml", line 1, characters 15-60:
  1 | let%action a = Yuka.Action.mutation ~output:o (fun _ x -> x)
                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: [yuka] ~input is missing. let%action takes the form: let%action <name> = Yuka.Action.mutation ~input:<codec> ~output:<codec> (fun ctx input -> ...), or the same with Yuka.Action.query
  [1]
  $ shape 'let%action a = Yuka.Action.mutation ~input:i ~input:i ~output:o (fun _ x -> x)'
  File "shape.ml", line 1, characters 52-53:
  1 | let%action a = Yuka.Action.mutation ~input:i ~input:i ~output:o (fun _ x -> x)
                                                          ^
  Error: [yuka] ~input is given twice. let%action takes the form: let%action <name> = Yuka.Action.mutation ~input:<codec> ~output:<codec> (fun ctx input -> ...), or the same with Yuka.Action.query
  [1]
  $ shape 'let%action a = Yuka.Action.mutation ~input:i ~output:o ~retry:true (fun _ x -> x)'
  File "shape.ml", line 1, characters 62-66:
  1 | let%action a = Yuka.Action.mutation ~input:i ~output:o ~retry:true (fun _ x -> x)
                                                                    ^^^^
  Error: [yuka] unexpected argument ~retry. let%action takes the form: let%action <name> = Yuka.Action.mutation ~input:<codec> ~output:<codec> (fun ctx input -> ...), or the same with Yuka.Action.query
  [1]
  $ shape 'let%action a = Yuka.Action.mutation ~input:i ~output:o f g'
  File "shape.ml", line 1, characters 57-58:
  1 | let%action a = Yuka.Action.mutation ~input:i ~output:o f g
                                                               ^
  Error: [yuka] let%action takes one implementation, a function of the context and the input. let%action takes the form: let%action <name> = Yuka.Action.mutation ~input:<codec> ~output:<codec> (fun ctx input -> ...), or the same with Yuka.Action.query
  [1]

Not one plain binding:

  $ shape 'let%action (a, b) = Yuka.Action.mutation ~input:i ~output:o f'
  File "shape.ml", line 1, characters 11-17:
  1 | let%action (a, b) = Yuka.Action.mutation ~input:i ~output:o f
                 ^^^^^^
  Error: [yuka] the name of a let%action must be a plain variable. let%action takes the form: let%action <name> = Yuka.Action.mutation ~input:<codec> ~output:<codec> (fun ctx input -> ...), or the same with Yuka.Action.query
  [1]
  $ shape 'let%action rec a = Yuka.Action.mutation ~input:i ~output:o f'
  File "shape.ml", line 1, characters 0-60:
  1 | let%action rec a = Yuka.Action.mutation ~input:i ~output:o f
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: [yuka] let%action cannot be recursive. let%action takes the form: let%action <name> = Yuka.Action.mutation ~input:<codec> ~output:<codec> (fun ctx input -> ...), or the same with Yuka.Action.query
  [1]
  $ shape 'let%action a = Yuka.Action.mutation ~input:i ~output:o f and b = 1'
  File "shape.ml", line 1, characters 57-66:
  1 | let%action a = Yuka.Action.mutation ~input:i ~output:o f and b = 1
                                                               ^^^^^^^^^
  Error: [yuka] let%action takes one binding. let%action takes the form: let%action <name> = Yuka.Action.mutation ~input:<codec> ~output:<codec> (fun ctx input -> ...), or the same with Yuka.Action.query
  [1]

Not in a module:

  $ shape 'let x = let%action a = Yuka.Action.mutation ~input:i ~output:o f in a'
  File "shape.ml", line 1, characters 12-18:
  1 | let x = let%action a = Yuka.Action.mutation ~input:i ~output:o f in a
                  ^^^^^^
  Error: [yuka] let%action must be in a module, not in an expression.
  [1]

Not in a functor, where each application would register the same name:

  $ shape 'module F (X : sig end) = struct let%action a = Yuka.Action.mutation ~input:i ~output:o f end'
  File "shape.ml", line 1, characters 32-88:
  1 | module F (X : sig end) = struct let%action a = Yuka.Action.mutation ~input:i ~output:o f end
                                      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: [yuka] let%action cannot be in a functor: each application would register the same action name.
  [1]

Not in an anonymous module, where the name would be the same as an action
outside it:

  $ shape 'module _ = struct let%action save = Yuka.Action.mutation ~input:i ~output:o f end'
  File "shape.ml", line 1, characters 18-77:
  1 | module _ = struct let%action save = Yuka.Action.mutation ~input:i ~output:o f end
                        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: [yuka] let%action cannot be in an anonymous module: its name would be the same as an action outside it.
  [1]

The implementation sees the bindings before the let%action, as in a plain
let: here count is the ref, not the action:

  $ cat > shadow.ml <<'EOF'
  > let count = ref 0
  > let%action count = Yuka.Action.mutation ~input:i ~output:o (fun _ x -> incr count; x)
  > EOF
  $ native --impl shadow.ml
  let count = ref 0
  let count =
    (fun action implementation ->
       Yuka.Server.Action.implement action implementation; action)
      (Yuka.Action.mutation ~name:"Shadow.count" ~input:i ~output:o)
      (fun _ x -> incr count; x)
