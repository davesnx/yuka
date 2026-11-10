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
  > let make ~x () = Yuka.text x
  > module Row = struct let make () = Yuka.text Css.row end
  > let helper () = 1
  > X
  $ run a
  module Css =
    struct
      let stylesheet = Yuka.stylesheet "/_yuka/css/a-705346f1.css"
      let row = "row_705346f1"
      let item = "item_705346f1"
      let done_ = "done_705346f1"
      let label = "label_705346f1"
      let wide_thing = "wide-thing_705346f1"
      let open_ = "open_705346f1"
    end
  let make ~x () = Yuka.use_css Css.stylesheet (Yuka.text x)
  module Row =
    struct let make () = Yuka.use_css Css.stylesheet (Yuka.text Css.row) end
  let helper () = 1

The generator writes the same names and the same file:

  $ yuka-css a.css
  let sheets = [
    ("a-705346f1.css", "/* .in-comment { } */\n.row_705346f1, div.item_705346f1:not(.done_705346f1) > .label_705346f1 { background: url(x.png); }\n.row_705346f1:hover { content: \".in-string\"; margin: .5em; }\n@media (max-width: 10px) { .wide-thing_705346f1 { display: none } }\n[data-x=\".in-attr\"] .open_705346f1 { }\n@keyframes spin { 12.5% { opacity: 1 } }\n");
  ]

The island of a let%client gets the sheet too:

  $ cat > b.mlx <<'X'
  > module Css = [%yuka.css "a.css"]
  > let%client make ~(n : int) () = Yuka.int n
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
  > let make () = Yuka.text Css.missing
  > X
  $ run c > c.pp.ml && ocamlfind ocamlc -c yuka.ml c.pp.ml 2>&1 | grep -v '^ *[0-9]* |\|^ *\^'
  File "c.pp.ml", line 11, characters 53-64:
  Error: Unbound value Css.missing

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
