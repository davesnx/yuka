  $ run() { ./pp.exe --impl $1.ml; }

Class names are scoped with a hash of the file, one value per class:

  $ cat > a.css <<'X'
  > /* .in-comment { } */
  > .row, div.item:not(.done) > .label { background: url(x.png); }
  > .row:hover { content: ".in-string"; margin: .5em; }
  > @media (max-width: 10px) { .wide-thing { display: none } }
  > [data-x=".in-attr"] .open { }
  > @keyframes spin { 12.5% { opacity: 1 } }
  > X
  $ cat > a.ml <<'X'
  > module Css = [%yuka.css "a.css"]
  > let make ~x () : Yuka.client Yuka.element = Yuka.text x
  > X
  $ run a
  module Css =
    struct
      let stylesheet = Yuka.runtime_stylesheet "/_yuka/css/a-705346f1.css"
      let row = "row_705346f1"
      let item = "item_705346f1"
      let done_ = "done_705346f1"
      let label = "label_705346f1"
      let wide_thing = "wide-thing_705346f1"
      let open_ = "open_705346f1"
    end
  let make ~x () : Yuka.client Yuka.element=
    Yuka.use_css Css.stylesheet (Yuka.text x)

The generator finds the declarations in the sources and writes the same file:

  $ yuka css --dir .
  let sheets = [
    ("a-705346f1.css", "/* .in-comment { } */\n.row_705346f1, div.item_705346f1:not(.done_705346f1) > .label_705346f1 { background: url(x.png); }\n.row_705346f1:hover { content: \".in-string\"; margin: .5em; }\n@media (max-width: 10px) { .wide-thing_705346f1 { display: none } }\n[data-x=\".in-attr\"] .open_705346f1 { }\n@keyframes spin { 12.5% { opacity: 1 } }\n");
  ]

Escapes, quoted url(), @scope and @supports selector():

  $ mkdir e && cat > e/e.css <<'X'
  > .md\:flex:hover { } .\31 0 { } .x\.y { }
  > .u { background: url("a).png"); } .v { background: url( 'b).png' ) }
  > @scope (.card) to (.content) { .title { } }
  > @supports selector(:has(.kid)) { .p { } }
  > @supports (display: grid) { .q { } }
  > X
  $ cat > e/e.ml <<'X'
  > module Css = [%yuka.css "e.css"]
  > X
  $ run e/e
  module Css =
    struct
      let stylesheet = Yuka.runtime_stylesheet "/_yuka/css/e-25e1fa53.css"
      let md_flex = "md:flex_25e1fa53"
      let _10 = "10_25e1fa53"
      let x_y = "x.y_25e1fa53"
      let u = "u_25e1fa53"
      let v = "v_25e1fa53"
      let card = "card_25e1fa53"
      let content = "content_25e1fa53"
      let title = "title_25e1fa53"
      let kid = "kid_25e1fa53"
      let p = "p_25e1fa53"
      let q = "q_25e1fa53"
    end
  $ yuka css --dir e
  let sheets = [
    ("e-25e1fa53.css", ".md\\:flex_25e1fa53:hover { } .\\31 0_25e1fa53 { } .x\\.y_25e1fa53 { }\n.u_25e1fa53 { background: url(\"a).png\"); } .v_25e1fa53 { background: url( 'b).png' ) }\n@scope (.card_25e1fa53) to (.content_25e1fa53) { .title_25e1fa53 { } }\n@supports selector(:has(.kid_25e1fa53)) { .p_25e1fa53 { } }\n@supports (display: grid) { .q_25e1fa53 { } }\n");
  ]

A class that cannot be an OCaml name:

  $ mkdir n && printf '.caf\303\251 { }\n' > n/n.css && echo 'module Css = [%yuka.css "n.css"]' > n/n.ml
  $ run n/n
  File "n/n.ml", line 1, characters 13-32:
  1 | module Css = [%yuka.css "n.css"]
                   ^^^^^^^^^^^^^^^^^^^
  Error: [yuka] n.css: the class "caf\195\169" has characters an OCaml name cannot have; rename it
  [1]

Only functions that return an element get the sheet; a component make
that is not a function gets a warning, another make is left alone:

  $ cat > w.ml <<'X'
  > module Css = [%yuka.css "a.css"]
  > type t = A | B
  > let make = function A -> (Yuka.text "a" : _ Yuka.element) | B -> Yuka.text "b"
  > module Typed = struct
  >   let make : unit -> Yuka.client Yuka.element = fun () -> Yuka.text "x"
  > end
  > module Model = struct let make a b = (a, b) end
  > module Alias = struct let make = Typed.make end
  > module Typed_alias = struct let make : unit -> Yuka.client Yuka.element = Typed.make end
  > X
  $ run w | sed -n '/^type t/,$p'
  type t =
    | A 
    | B 
  let make =
    function
    | A -> Yuka.use_css Css.stylesheet (Yuka.text "a" : _ Yuka.element)
    | B -> Yuka.use_css Css.stylesheet (Yuka.text "b")
  module Typed =
    struct
      let make : unit -> Yuka.client Yuka.element =
        fun () -> Yuka.use_css Css.stylesheet (Yuka.text "x")
    end
  module Model = struct let make a b = (a, b) end
  module Alias = struct let make = Typed.make end
  module Typed_alias =
    struct
      let make : unit -> Yuka.client Yuka.element = Typed.make[@@ocaml.ppwarning
                                                                "[yuka] this make is not a function, so [%yuka.css] cannot add its sheet; call Yuka.use_css Css.stylesheet in the component"]
    end

The island of a let[@client] gets the sheet:

  $ cat > b.mlx <<'X'
  > module Css = [%yuka.css "a.css"]
  > let[@client] make ~(n : int) () = Yuka.int n
  > X
  $ mlx-pp b.mlx > b.ml && run b | grep -c "Yuka.use_css Css.stylesheet"
  1

A class that the file does not have is a compile error:

  $ cat > yuka.ml <<'X'
  > type 'k element = string
  > let text s = s
  > let use_css _ e = e
  > let stylesheet s = s
  > X
  $ cat > c.ml <<'X'
  > module Css = [%yuka.css "a.css"]
  > let make () = (Yuka.text Css.missing : _ Yuka.element)
  > X
  $ run c > c.pp.ml && ocamlfind ocamlc -c yuka.ml c.pp.ml 2>&1 | grep -v '^ *[0-9]* |\|^ *\^'
  File "c.pp.ml", line 3, characters 21-44:
  Error: Unbound value Yuka.runtime_stylesheet

Errors:

  $ cat > d.ml <<'X'
  > module Css = [%yuka.css "nope.css"]
  > X
  $ run d
  File "d.ml", line 1, characters 13-35:
  1 | module Css = [%yuka.css "nope.css"]
                   ^^^^^^^^^^^^^^^^^^^^^^
  Error: [yuka] cannot read nope.css; list it in the dune file of this library: (preprocessor_deps nope.css)
  [1]
  $ mkdir m && cp d.ml m/ && yuka css --dir m
  yuka css: m/d.ml: [%yuka.css "nope.css"]: cannot read m/nope.css
  [1]

Preprocessed copies that dune leaves in the build directory are skipped:

  $ mkdir pp && echo 'module Css = [%yuka.css "gone.css"]' > pp/v.mlx.pp.ml && yuka css --dir pp
  let sheets = [
  ]

Comments and strings that mention [%yuka.css] are not declarations:

  $ mkdir k && cp a.css k/ && cat > k/k.ml <<'X'
  > (** Use [%yuka.css "doc.css"] (* nested [%yuka.css "nested.css"] *) *)
  > let s = "[%yuka.css \"str.css\"]"
  > let q = {|[%yuka.css "quoted.css"]|}
  > module Css = [%yuka.css "a.css"]
  > X
  $ yuka css --dir k | cut -c1-24
  let sheets = [
    ("a-705346f1.css", "/*
  ]

  $ cat > e.ml <<'X'
  > module Css = [%yuka.css 1]
  > X
  $ run e
  File "e.ml", line 1, characters 13-26:
  1 | module Css = [%yuka.css 1]
                   ^^^^^^^^^^^^^
  Error: [yuka] [%yuka.css] takes a file name: module Css = [%yuka.css "file.css"]
  [1]

  $ cat > f.css <<'X'
  > .a-b { } .a_b { }
  > X
  $ cat > f.ml <<'X'
  > module Css = [%yuka.css "f.css"]
  > X
  $ run f
  File "f.ml", line 1, characters 13-32:
  1 | module Css = [%yuka.css "f.css"]
                   ^^^^^^^^^^^^^^^^^^^
  Error: [yuka] f.css: two classes have the OCaml name a_b; rename one of them
  [1]

  $ cat > g.ml <<'X'
  > module Css = [%yuka.css "a.css"]
  > module Other = [%yuka.css "f.css"]
  > X
  $ run g
  File "g.ml", line 2, characters 0-34:
  2 | module Other = [%yuka.css "f.css"]
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: [yuka] only one [%yuka.css] per file
  [1]

Only [%yuka.css] is a declaration: [%css "..."] (for example from styled-ppx)
is left alone by the ppx and by yuka css:

  $ mkdir short && cat > short/s.ml <<'X'
  > let cls = [%css "display: block"]
  > let other = [%yuka.cssx "no.css"]
  > X
  $ ./pp.exe --impl short/s.ml
  let cls = [%css "display: block"]
  let other = [%yuka.cssx "no.css"]
  $ yuka css --dir short
  let sheets = [
  ]
