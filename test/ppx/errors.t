  $ run() { mlx-pp $1.mlx > $1.ml && ./pp.exe --impl $1.ml; }

Unknown attribute:

  $ cat > attr.mlx <<'X'
  > let x = <div href="/x" />
  > X
  $ run attr
  File "attr.mlx", line 1, characters 18-22:
  1 | let x = <div href="/x" />
                        ^^^^
  Error: [yuka] The attribute 'href' is not valid on a 'div' element.
  [1]

Unknown tag:

  $ cat > tag.mlx <<'X'
  > let x = <blorp />
  > X
  $ run tag
  File "tag.mlx", line 1, characters 8-14:
  1 | let x = <blorp />
              ^^^^^^
  Error: [yuka] HTML tag 'blorp' does not exist.
  [1]

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

Children:

  $ cat > h3.mlx <<'X'
  > let[@client] make ~(children : Yuka.slot) () = <p />
  > X
  $ run h3
  File "h3.mlx", line 1, characters 18-41:
  1 | let[@client] make ~(children : Yuka.slot) () = <p />
                        ^^^^^^^^^^^^^^^^^^^^^^^
  Error: [yuka] write ~children: the children of a let[@client] component are a Yuka.client Yuka.element, not a Yuka.slot or an option
  [1]
  $ cat > h3b.mlx <<'X'
  > let[@client] make ?children () = <p />
  > X
  $ run h3b
  File "h3b.mlx", line 1, characters 18-27:
  1 | let[@client] make ?children () = <p />
                        ^^^^^^^^^
  Error: [yuka] write ~children: the children of a let[@client] component are a Yuka.client Yuka.element, not a Yuka.slot or an option
  [1]

Missing annotation:

  $ cat > h4.mlx <<'X'
  > let[@client] make ~a () = <p />
  > X
  $ run h4
  File "h4.mlx", line 1, characters 18-20:
  1 | let[@client] make ~a () = <p />
                        ^^
  Error: [yuka] the argument 'a' needs a type annotation
  [1]

Last parameter:

  $ cat > h5.mlx <<'X'
  > let[@client] make ~(a : int) = <p />
  > X
  $ run h5
  File "h5.mlx", line 1, characters 18-28:
  1 | let[@client] make ~(a : int) = <p />
                        ^^^^^^^^^^
  Error: [yuka] the last parameter must be ()
  [1]

Yuka.Client with another prop:

  $ cat > h6.mlx <<'X'
  > let x = <Yuka.Client other=1><Counter a=1 /></Yuka.Client>
  > X
  $ run h6
  File "h6.mlx", line 1, characters 8-20:
  1 | let x = <Yuka.Client other=1><Counter a=1 /></Yuka.Client>
              ^^^^^^^^^^^^
  Error: [yuka] Yuka.Client takes no props except start
  [1]

Yuka.Client without child:

  $ cat > h7.mlx <<'X'
  > let x = <Yuka.Client></Yuka.Client>
  > X
  $ run h7
  File "h7.mlx", line 1, characters 8-20:
  1 | let x = <Yuka.Client></Yuka.Client>
              ^^^^^^^^^^^^
  Error: [yuka] Yuka.Client needs exactly one child, a component tag such as <Counter a=1 />
  [1]

Yuka.Client with two children:

  $ cat > h8.mlx <<'X'
  > let x = <Yuka.Client><Counter /><Related /></Yuka.Client>
  > X
  $ run h8
  File "h8.mlx", line 1, characters 8-20:
  1 | let x = <Yuka.Client><Counter /><Related /></Yuka.Client>
              ^^^^^^^^^^^^
  Error: [yuka] Yuka.Client needs exactly one child, a component tag such as <Counter a=1 />
  [1]

Yuka.Client with a tag child:

  $ cat > h9.mlx <<'X'
  > let x = <Yuka.Client><p /></Yuka.Client>
  > X
  $ run h9
  File "h9.mlx", line 1, characters 8-20:
  1 | let x = <Yuka.Client><p /></Yuka.Client>
              ^^^^^^^^^^^^
  Error: [yuka] Yuka.Client needs exactly one child, a component tag such as <Counter a=1 />
  [1]

let[@client] with a reserved argument:

  $ cat > h10.mlx <<'X'
  > let[@client] make ~(start : int) () = <p />
  > X
  $ run h10
  File "h10.mlx", line 1, characters 18-32:
  1 | let[@client] make ~(start : int) () = <p />
                        ^^^^^^^^^^^^^^
  Error: [yuka] the argument 'start' is reserved for the start strategy
  [1]

SVG attribute on a tag that is not SVG:

  $ cat > h11.mlx <<'X'
  > let x = <div stroke_dasharray="1" />
  > X
  $ run h11
  File "h11.mlx", line 1, characters 30-33:
  1 | let x = <div stroke_dasharray="1" />
                                    ^^^
  Error: [yuka] The attribute 'stroke_dasharray' is not valid on a 'div' element.
  [1]

camelCase event on a DOM element:

  $ cat > p0.mlx <<'X'
  > let x = <button onClick=(fun _ -> ()) />
  > X
  $ run p0
  File "p0.mlx", line 1, characters 24-37:
  1 | let x = <button onClick=(fun _ -> ()) />
                              ^^^^^^^^^^^^^
  Error: [yuka] Write 'onClick' as 'on_click'.
  [1]

camelCase attribute on a DOM element:

  $ cat > p1.mlx <<'X'
  > let x = <svg viewBox="0 0 1 1" />
  > X
  $ run p1
  File "p1.mlx", line 1, characters 21-30:
  1 | let x = <svg viewBox="0 0 1 1" />
                           ^^^^^^^^^
  Error: [yuka] Write 'viewBox' as 'view_box'.
  [1]

Event without the underscore:

  $ cat > p2.mlx <<'X'
  > let x = <button onclick=(fun _ -> ()) />
  > X
  $ run p2
  File "p2.mlx", line 1, characters 24-37:
  1 | let x = <button onclick=(fun _ -> ()) />
                              ^^^^^^^^^^^^^
  Error: [yuka] The attribute 'onclick' is not valid on a 'button' element. Maybe you mean 'on_click'?
  [1]

Suggestion in snake case:

  $ cat > p3.mlx <<'X'
  > let x = <svg view_bx="0 0 1 1" />
  > X
  $ run p3
  File "p3.mlx", line 1, characters 21-30:
  1 | let x = <svg view_bx="0 0 1 1" />
                           ^^^^^^^^^
  Error: [yuka] The attribute 'view_bx' is not valid on a 'svg' element. Maybe you mean 'view_box'?
  [1]

Optional camelCase prop:

  $ cat > p4.mlx <<'X'
  > let x = <div ?onMouseDown />
  > X
  $ run p4
  File "p4.mlx", line 1, characters 14-25:
  1 | let x = <div ?onMouseDown />
                    ^^^^^^^^^^^
  Error: [yuka] Write 'onMouseDown' as 'on_mousedown'.
  [1]

Templates are values at the top of the module; their names carry the module name, not the directory:

  $ mkdir d1 d2
  $ printf 'let x = <ul><li>"a"</li><li>"b"</li></ul>\nlet y = <ol><li>"a"</li><li>"b"</li></ol>\n' > d1/view.mlx
  $ cp d1/view.mlx d2/view.mlx
  $ ids() { mlx-pp $1/view.mlx > $1/view.ml && ./pp.exe --impl $1/view.ml | grep -o '__yuka_template_[a-z0-9_]*'; }
  $ ids d1
  __yuka_template_view_0
  __yuka_template_view_0
  __yuka_template_view_1
  __yuka_template_view_1
  $ ids d2
  __yuka_template_view_0
  __yuka_template_view_0
  __yuka_template_view_1
  __yuka_template_view_1

Catch without fallback:

  $ cat > c0.mlx <<'X'
  > let x = <Yuka.Catch><p /></Yuka.Catch>
  > X
  $ run c0
  File "c0.mlx", line 1, characters 8-19:
  1 | let x = <Yuka.Catch><p /></Yuka.Catch>
              ^^^^^^^^^^^
  Error: [yuka] Yuka.Catch takes one prop, fallback
  [1]

Catch without children:

  $ cat > c1.mlx <<'X'
  > let x = <Yuka.Catch fallback=f />
  > X
  $ run c1
  File "c1.mlx", line 1, characters 8-19:
  1 | let x = <Yuka.Catch fallback=f />
              ^^^^^^^^^^^
  Error: [yuka] Yuka.Catch needs children
  [1]

Context.Provide without context:

  $ cat > p0.mlx <<'X'
  > let x = <Yuka.Context.Provide value=1><p /></Yuka.Context.Provide>
  > X
  $ run p0
  File "p0.mlx", line 1, characters 8-29:
  1 | let x = <Yuka.Context.Provide value=1><p /></Yuka.Context.Provide>
              ^^^^^^^^^^^^^^^^^^^^^
  Error: [yuka] Yuka.Context.Provide needs the prop 'context'
  [1]

Context.Provide without value:

  $ cat > p1.mlx <<'X'
  > let x = <Yuka.Context.Provide context=c><p /></Yuka.Context.Provide>
  > X
  $ run p1
  File "p1.mlx", line 1, characters 8-29:
  1 | let x = <Yuka.Context.Provide context=c><p /></Yuka.Context.Provide>
              ^^^^^^^^^^^^^^^^^^^^^
  Error: [yuka] Yuka.Context.Provide needs the prop 'value'
  [1]

Context.Provide with an unknown prop:

  $ cat > p2.mlx <<'X'
  > let x = <Yuka.Context.Provide context=c value=1 key="k"><p /></Yuka.Context.Provide>
  > X
  $ run p2
  File "p2.mlx", line 1, characters 8-29:
  1 | let x = <Yuka.Context.Provide context=c value=1 key="k"><p /></Yuka.Context.Provide>
              ^^^^^^^^^^^^^^^^^^^^^
  Error: [yuka] Yuka.Context.Provide takes context and value
  [1]

Context.Provide with a prop given twice:

  $ cat > pd.mlx <<'X'
  > let x = <Yuka.Context.Provide context=a context=b value=1><p /></Yuka.Context.Provide>
  > X
  $ run pd
  File "pd.mlx", line 1, characters 48-49:
  1 | let x = <Yuka.Context.Provide context=a context=b value=1><p /></Yuka.Context.Provide>
                                                      ^
  Error: [yuka] Yuka.Context.Provide takes the prop 'context' once
  [1]

Context.Provide without children:

  $ cat > p3.mlx <<'X'
  > let x = <Yuka.Context.Provide context=c value=1 />
  > X
  $ run p3
  File "p3.mlx", line 1, characters 8-29:
  1 | let x = <Yuka.Context.Provide context=c value=1 />
              ^^^^^^^^^^^^^^^^^^^^^
  Error: [yuka] Yuka.Context.Provide needs children
  [1]

Show without status:

  $ cat > s0.mlx <<'X'
  > let x = <Yuka.Show loading="l">(fun v -> <p />)</Yuka.Show>
  > X
  $ run s0
  File "s0.mlx", line 1, characters 8-18:
  1 | let x = <Yuka.Show loading="l">(fun v -> <p />)</Yuka.Show>
              ^^^^^^^^^^
  Error: [yuka] Yuka.Show needs the prop 'status'
  [1]

Show with async:

  $ cat > s1.mlx <<'X'
  > let x = <Yuka.Show async=a status=s loading="l">(fun v -> <p />)</Yuka.Show>
  > X
  $ run s1
  File "s1.mlx", line 1, characters 8-18:
  1 | let x = <Yuka.Show async=a status=s loading="l">(fun v -> <p />)</Yuka.Show>
              ^^^^^^^^^^
  Error: [yuka] Yuka.Show takes status, loading and failed
  [1]

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

Show without loading:

  $ cat > w1.mlx <<'X'
  > let x = <Yuka.Show status=s>(fun v -> <p />)</Yuka.Show>
  > X
  $ run w1
  File "w1.mlx", line 1, characters 8-18:
  1 | let x = <Yuka.Show status=s>(fun v -> <p />)</Yuka.Show>
              ^^^^^^^^^^
  Error: [yuka] Yuka.Show needs the prop 'loading'
  [1]

Pending without fallback:

  $ cat > pe0.mlx <<'X'
  > let x = <Yuka.Pending><p /></Yuka.Pending>
  > X
  $ run pe0
  File "pe0.mlx", line 1, characters 8-21:
  1 | let x = <Yuka.Pending><p /></Yuka.Pending>
              ^^^^^^^^^^^^^
  Error: [yuka] Yuka.Pending takes one prop, fallback
  [1]

Pending without children:

  $ cat > pe1.mlx <<'X'
  > let x = <Yuka.Pending fallback="f" />
  > X
  $ run pe1
  File "pe1.mlx", line 1, characters 8-21:
  1 | let x = <Yuka.Pending fallback="f" />
              ^^^^^^^^^^^^^
  Error: [yuka] Yuka.Pending needs children
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

Nested let[@client] in a module:

  $ cat > n0.mlx <<'X'
  > module Inner = struct
  >   let[@client] make ~(a : int) () = <p />
  > end
  > X
  $ run n0
  File "n0.mlx", line 2, characters 2-41:
  2 |   let[@client] make ~(a : int) () = <p />
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: [yuka] let[@client] is allowed only at the top level of a file, not inside a module or a function
  [1]

Nested let[@client] in a local module:

  $ cat > n1.mlx <<'X'
  > let f () =
  >   let module Inner = struct
  >     let[@client] make ~(a : int) () = <p />
  >   end in
  >   ()
  > X
  $ run n1
  File "n1.mlx", line 3, characters 4-43:
  3 |     let[@client] make ~(a : int) () = <p />
          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: [yuka] let[@client] is allowed only at the top level of a file, not inside a module or a function
  [1]

Unknown yuka attribute on let[@client]:

  $ cat > n2.mlx <<'X'
  > let[@client][@yuka.eager] make ~(a : int) () = <p />
  > X
  $ run n2
  File "n2.mlx", line 1, characters 12-25:
  1 | let[@client][@yuka.eager] make ~(a : int) () = <p />
                  ^^^^^^^^^^^^^
  Error: [yuka] unknown attribute [@yuka.eager] on a let[@client] binding
  [1]

let[@client] in a .ml file:

  $ cat > island.ml <<'X'
  > let[@client] make ~(a : int) () = Yuka.text (string_of_int a)
  > X
  $ ./pp.exe --impl island.ml
  File "island.ml", line 1, characters 0-61:
  1 | let[@client] make ~(a : int) () = Yuka.text (string_of_int a)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: [yuka] let[@client] is allowed only in .mlx files: rename island.ml to island.mlx
  [1]

let[@client] in a file with another extension (OCaml syntax in a .re name):

  $ cat > island.re <<'X'
  > let[@client] make ~(a : int) () = Yuka.text (string_of_int a)
  > X
  $ ./pp.exe --impl island.re
  File "island.re", line 1, characters 0-61:
  1 | let[@client] make ~(a : int) () = Yuka.text (string_of_int a)
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: [yuka] let[@client] is allowed only in .mlx files: rename island.re to island.mlx
  [1]

Unknown yuka attribute on the binding:

  $ cat > n3.mlx <<'X'
  > let[@client] make ~(a : int) () = <p /> [@@yuka.other]
  > X
  $ run n3
  File "n3.mlx", line 1, characters 40-54:
  1 | let[@client] make ~(a : int) () = <p /> [@@yuka.other]
                                              ^^^^^^^^^^^^^^
  Error: [yuka] unknown attribute [@yuka.other] on a let[@client] binding
  [1]

[@client] takes no payload:

  $ cat > p0.mlx <<'X'
  > let[@client { lazy_ = true }] make ~(a : int) () = <p />
  > X
  $ run p0
  File "p0.mlx", line 1, characters 3-29:
  1 | let[@client { lazy_ = true }] make ~(a : int) () = <p />
         ^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: [yuka] [@client] takes no options yet: write let[@client] make
  [1]

Nested [@client] on a local binding in a function:

  $ cat > p1.mlx <<'X'
  > let f () =
  >   let[@client] make ~(a : int) () = <p /> in
  >   make
  > X
  $ run p1
  File "p1.mlx", line 2, characters 2-41:
  2 |   let[@client] make ~(a : int) () = <p /> in
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: [yuka] let[@client] is allowed only at the top level of a file, not inside a module or a function
  [1]

[@client] on a binding not named make:

  $ cat > p2.mlx <<'X'
  > let[@client] view ~(a : int) () = <p />
  > X
  $ run p2
  File "p2.mlx", line 1, characters 0-39:
  1 | let[@client] view ~(a : int) () = <p />
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: [yuka] let[@client] must define 'make'
  [1]

[@client] on let rec and on several bindings:

  $ cat > p3.mlx <<'X'
  > let[@client] rec make ~(a : int) () = <p />
  > X
  $ run p3
  File "p3.mlx", line 1, characters 0-43:
  1 | let[@client] rec make ~(a : int) () = <p />
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: [yuka] let[@client] takes one non-recursive let binding
  [1]
  $ cat > p4.mlx <<'X'
  > let[@client] make ~(a : int) () = <p />
  > and other = 1
  > X
  $ run p4
  File "p4.mlx", lines 1-2, characters 0-13:
  1 | let[@client] make ~(a : int) () = <p />
  2 | and other = 1
  Error: [yuka] let[@client] takes one non-recursive let binding
  [1]

The old extension form is refused:

  $ cat > p5.mlx <<'X'
  > let%client make ~(a : int) () = <p />
  > X
  $ run p5
  File "p5.mlx", line 1, characters 4-10:
  1 | let%client make ~(a : int) () = <p />
          ^^^^^^
  Error: [yuka] let%client is now let[@client]
  [1]
  $ cat > p6.mlx <<'X'
  > let%yuka.client make ~(a : int) () = <p />
  > X
  $ run p6
  File "p6.mlx", line 1, characters 4-15:
  1 | let%yuka.client make ~(a : int) () = <p />
          ^^^^^^^^^^^
  Error: [yuka] let%yuka.client is now let[@yuka.client]
  [1]

The item attribute [@@client] is the same attribute:

  $ cat > p7.mlx <<'X'
  > let make ~(a : int) () = <p /> [@@client]
  > X
  $ run p7 | grep -c 'Yuka.runtime_entry'
  1

deriving form needs a record:

  $ cat > form1.mlx <<'X'
  > type t = A | B [@@deriving form]
  > X
  $ run form1
  File "form1.mlx", line 1, characters 0-32:
  1 | type t = A | B [@@deriving form]
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: [yuka] [@@deriving form] needs a record type
  [1]

deriving form refuses a field type it cannot read:

  $ cat > form2.mlx <<'X'
  > type t = { at : int * int } [@@deriving form]
  > X
  $ run form2
  File "form2.mlx", line 1, characters 16-25:
  1 | type t = { at : int * int } [@@deriving form]
                      ^^^^^^^^^
  Error: [yuka] a form field must be string, int, float, bool, an option or list of those, or Email.t with Email.of_string and Email.to_string
  [1]

deriving form refuses type parameters and labels that start with an underscore:

  $ cat > form3.mlx <<'X'
  > type 'a t = { x : string } [@@deriving form]
  > X
  $ run form3
  File "form3.mlx", line 1, characters 5-7:
  1 | type 'a t = { x : string } [@@deriving form]
           ^^
  Error: [yuka] [@@deriving form] needs a type with no parameter
  [1]

  $ cat > form4.mlx <<'X'
  > type t = { _hidden : string } [@@deriving form]
  > X
  $ run form4
  File "form4.mlx", line 1, characters 11-18:
  1 | type t = { _hidden : string } [@@deriving form]
                 ^^^^^^^
  Error: [yuka] a form field name cannot start with '_' (the form uses _yuka_ fields)
  [1]

String.t, Int.t, Float.t and Bool.t are the base kinds, not custom modules:

  $ cat > form5.mlx <<'X'
  > type t = { a : String.t; b : Int.t; c : Float.t; d : Bool.t } [@@deriving form]
  > X
  $ run form5 | grep -o 'Yuka.Form.[a-z]*' | sort -u
  Yuka.Form.bool
  Yuka.Form.float
  Yuka.Form.int
  Yuka.Form.string
  Yuka.Form.t

A literal script URL in a URL attribute is refused at build time:

  $ cat > url1.mlx <<'X'
  > let x = <a href=" JavaScript:alert(1)">"x"</a>
  > X
  $ run url1
  File "url1.mlx", line 1, characters 16-38:
  1 | let x = <a href=" JavaScript:alert(1)">"x"</a>
                      ^^^^^^^^^^^^^^^^^^^^^^
  Error: [yuka] href=" JavaScript:alert(1)" has a script URL; Yuka would print about:blank#blocked instead. Use an event handler.
  [1]
  $ cat > url2.mlx <<'X'
  > let x = <a href="https://example.com" title="javascript:x">"x"</a>
  > X
  $ run url2 | grep -c 'about:blank'
  0
  [1]

Attribute names are read in any case, and data: is refused only where it loads a document:

  $ cat > url3.mlx <<'X'
  > let x = <a href="data:text/html,x">"x"</a>
  > X
  $ run url3 2>&1 | grep -o 'has a script URL'
  has a script URL
  $ cat > url4.mlx <<'X'
  > let x = <img src="data:image/png;base64,iVBORw0KGgo=" />
  > X
  $ run url4 | grep -c 'about:blank'
  0
  [1]

<script> and <style> take only text:

  $ cat > raw1.mlx <<'X'
  > let x = <style>"a{}"<b>"x"</b></style>
  > X
  $ run raw1
  File "raw1.mlx", line 1, characters 20-30:
  1 | let x = <style>"a{}"<b>"x"</b></style>
                          ^^^^^^^^^^
  Error: [yuka] <style> takes only text: a string or (Yuka.text e), not an element, a component or an island.
  [1]
  $ cat > raw2.mlx <<'X'
  > let x = <script>(Yuka.text "a")(Comp.make ())</script>
  > X
  $ run raw2
  File "raw2.mlx", line 1, characters 31-45:
  1 | let x = <script>(Yuka.text "a")(Comp.make ())</script>
                                     ^^^^^^^^^^^^^^
  Error: [yuka] <script> takes only text: a string or (Yuka.text e), not an element, a component or an island.
  [1]

An attribute name that is not valid HTML is refused at build time:

  $ cat > name1.mlx <<'Y'
  > let x = <div data_x'="y" />
  > Y
  $ run name1
  File "name1.mlx", line 1, characters 21-24:
  1 | let x = <div data_x'="y" />
                           ^^^
  Error: [yuka] "data-x'" is not a valid attribute name.
  [1]
  $ cat > name2.mlx <<'Y'
  > let v = "y"
  > let x = <div data_x'=v />
  > Y
  $ run name2
  File "name2.mlx", line 2, characters 21-22:
  2 | let x = <div data_x'=v />
                           ^
  Error: [yuka] "data-x'" is not a valid attribute name.
  [1]

A literal srcdoc is kept:

  $ cat > srcdoc1.mlx <<'Y'
  > let x = <iframe srcdoc="<b>hi</b>" />
  > Y
  $ run srcdoc1 | grep -o 'srcdoc=[^ ]*'
  srcdoc=\"&lt;b>hi&lt;/b>\"></iframe>"

An event handler takes a function, not a string; only names the ppx knows are tags:

  $ cat > event1.mlx <<'Y'
  > let x = <button on_click="alert(1)">"x"</button>
  > Y
  $ run event1
  File "event1.mlx", line 1, characters 25-35:
  1 | let x = <button on_click="alert(1)">"x"</button>
                               ^^^^^^^^^^
  Error: [yuka] on_click takes a function, not a string: write on_click=(fun event -> ...).
  [1]
  $ cat > event2.mlx <<'Y'
  > let x = <button onclick="alert(1)">"x"</button>
  > Y
  $ run event2
  File "event2.mlx", line 1, characters 24-34:
  1 | let x = <button onclick="alert(1)">"x"</button>
                              ^^^^^^^^^^
  Error: [yuka] The attribute 'onclick' is not valid on a 'button' element. Maybe you mean 'on_click'?
  [1]
  $ cat > tag1.mlx <<'Y'
  > let x = <img_x />
  > Y
  $ run tag1
  File "tag1.mlx", line 1, characters 8-14:
  1 | let x = <img_x />
              ^^^^^^
  Error: [yuka] HTML tag 'img_x' does not exist.
  [1]

A literal base href is kept:

  $ cat > base1.mlx <<'Y'
  > let x = <base href="/app/" />
  > Y
  $ run base1 | grep -o 'href=[^ ]*'
  href=\"/app/\">"

The namespaced and the short names are the same: let[@yuka.client] and
let[@client]:

  $ cat > ns1.mlx <<'Y'
  > let[@yuka.client] make ~(n : int) () = <b>(Yuka.text (string_of_int n))</b>
  > Y
  $ run ns1 | grep -c 'Yuka.runtime_entry'
  1
  $ cat > ns2.ml <<'Y'
  > let[@yuka.client] make () = ()
  > Y
  $ ./pp.exe --impl ns2.ml
  File "ns2.ml", line 1, characters 0-30:
  1 | let[@yuka.client] make () = ()
      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: [yuka] let[@client] is allowed only in .mlx files: rename ns2.ml to ns2.mlx
  [1]

An island prop named make is refused:

  $ cat > mk.mlx <<'Y'
  > let[@client] make ~(make : int) () = <b>(Yuka.text (string_of_int make))</b>
  > Y
  $ run mk
  File "mk.mlx", line 1, characters 18-31:
  1 | let[@client] make ~(make : int) () = <b>(Yuka.text (string_of_int make))</b>
                        ^^^^^^^^^^^^^
  Error: [yuka] the argument 'make' would hide the component make; give the prop another name
  [1]

A bare ~islands is Yuka_islands.registry only when the file binds no islands;
after open Yuka, render is Yuka.render unless the file binds render:

  $ cat > is1.mlx <<'Y'
  > let main () = Yuka.render ~islands ()
  > Y
  $ run is1
  let main () = Yuka.render ~islands:Yuka_islands.registry ()
  $ cat > is2.mlx <<'Y'
  > let main mine = let islands = mine in Yuka.render ~islands ()
  > Y
  $ run is2
  let main mine = let islands = mine in Yuka.render ~islands ()
  $ cat > is3.mlx <<'Y'
  > let main ~islands = Yuka.render ~islands ()
  > Y
  $ run is3
  let main ~islands = Yuka.render ~islands ()
  $ cat > is4.mlx <<'Y'
  > open Yuka
  > let main () = render ~islands ()
  > Y
  $ run is4
  open Yuka
  let main () = render ~islands:Yuka_islands.registry ()
  $ cat > is5.mlx <<'Y'
  > open Yuka
  > let render ~islands () = islands
  > let main () = render ~islands ()
  > Y
  $ run is5
  open Yuka
  let render ~islands () = islands
  let main () = render ~islands ()
  $ cat > is6.mlx <<'Y'
  > let main () = render ~islands ()
  > Y
  $ run is6
  let main () = render ~islands ()

After open Yuka, Await, Show, Catch and Client need no Yuka. prefix, unless
the file defines a module of that name:

  $ cat > op1.mlx <<'Y'
  > open Yuka
  > let a x = <Await async=x loading=(text "l")>(fun v -> text v)</Await>
  > let s x = <Show status=x loading=(text "l")>(fun v -> text v)</Show>
  > let c () = <Catch fallback=(fun _ -> text "f")><b /></Catch>
  > let i () = <Client><Counter n=1 /></Client>
  > let p c = <Context.Provide context=c value=1>(text "v")</Context.Provide>
  > Y
  $ run op1
  open Yuka
  let a x =
    Yuka.Await.make ~async:x ~loading:(text "l") ~children:(fun v -> text v) ()
  let s x =
    Yuka.Show.make ~status:x ~loading:(text "l") ~children:(fun v -> text v) ()
  open
    struct
      let __yuka_template_op1_0 =
        Yuka.runtime_template "\001b\002\006" ~html:"<b></b>" ~walk:[||]
          ~kids:[||] ~attrs:[||] ~values:[||] ~clones:1
    end
  let c () =
    Yuka.Catch.make ~fallback:(fun _ -> text "f")
      ~children:(fun () -> Yuka.runtime_instance __yuka_template_op1_0 [||]) ()
  let i () = Counter.island ~n:1 ()
  let p c = Yuka.Context.provide c 1 (fun () -> text "v")
  $ cat > op2.mlx <<'Y'
  > open Yuka
  > module Show = struct let createElement ~children () = children end
  > let s () = <Show>"x"</Show>
  > Y
  $ run op2
  open Yuka
  module Show = struct let createElement ~children () = children end
  let s () = Show.make ~children:(Yuka.text "x") ()
  $ cat > op3.mlx <<'Y'
  > let a x = <Await async=x loading="l">(fun v -> v)</Await>
  > Y
  $ run op3
  let a x = Await.make ~async:x ~loading:"l" ~children:(fun v -> v) ()

The islands binding counts only where it is in scope:

  $ cat > sc1.mlx <<'Y'
  > let page ~islands = islands
  > let main () = Yuka.render ~islands ()
  > let after islands = Yuka.render ~islands ()
  > let cased = function Some islands -> Yuka.render ~islands () | None -> Yuka.render ~islands ()
  > let local () = (let islands = 1 in islands) + Yuka.render ~islands ()
  > let islands = 2
  > let last () = Yuka.render ~islands ()
  > Y
  $ run sc1
  let page ~islands = islands
  let main () = Yuka.render ~islands:Yuka_islands.registry ()
  let after islands = Yuka.render ~islands ()
  let cased =
    function
    | Some islands -> Yuka.render ~islands ()
    | None -> Yuka.render ~islands:Yuka_islands.registry ()
  let local () =
    (let islands = 1 in islands) +
      (Yuka.render ~islands:Yuka_islands.registry ())
  let islands = 2
  let last () = Yuka.render ~islands ()

open Yuka counts from its place to the next top-level open:

  $ cat > sc2.mlx <<'Y'
  > let early x = <Show status=x loading=(text "l")>(fun v -> v)</Show>
  > open Yuka
  > let late x = <Show status=x loading=(text "l")>(fun v -> v)</Show>
  > let r () = render ~islands ()
  > open Other
  > let other x = <Show status=x loading=(text "l")>(fun v -> v)</Show>
  > let r2 () = render ~islands ()
  > Y
  $ run sc2
  let early x =
    Show.make ~status:x ~loading:(text "l") ~children:(fun v -> v) ()
  open Yuka
  let late x =
    Yuka.Show.make ~status:x ~loading:(text "l") ~children:(fun v -> v) ()
  let r () = render ~islands:Yuka_islands.registry ()
  open Other
  let other x =
    Show.make ~status:x ~loading:(text "l") ~children:(fun v -> v) ()
  let r2 () = render ~islands ()

A State.get in a component body, outside markup, reads one time (form A):

  $ cat > ra1.mlx <<'Y'
  > let make ~count () =
  >   let n = Yuka.State.get count in
  >   <p>(Yuka.int n)</p>
  > Y
  $ run ra1
  File "ra1.mlx", line 2, characters 10-30:
  2 |   let n = Yuka.State.get count in
                ^^^^^^^^^^^^^^^^^^^^
  Error: Yuka: this State.get runs one time and never updates. Read it in markup, a memo or an effect, or use State.peek.
  [1]
  $ cat > ra2.mlx <<'Y'
  > open Yuka
  > let make ~count () =
  >   let n = State.get count in
  >   <p>(int n)</p>
  > Y
  $ run ra2
  File "ra2.mlx", line 3, characters 10-25:
  3 |   let n = State.get count in
                ^^^^^^^^^^^^^^^
  Error: Yuka: this State.get runs one time and never updates. Read it in markup, a memo or an effect, or use State.peek.
  [1]
  $ cat > ra3.mlx <<'Y'
  > module State = Yuka.State
  > let make ~count () =
  >   let n = State.get count in
  >   <p>(Yuka.int n)</p>
  > Y
  $ run ra3
  File "ra3.mlx", line 3, characters 10-25:
  3 |   let n = State.get count in
                ^^^^^^^^^^^^^^^
  Error: Yuka: this State.get runs one time and never updates. Read it in markup, a memo or an effect, or use State.peek.
  [1]
  $ cat > ra6.mlx <<'Y'
  > let make ~count () =
  >   let n = count |> Yuka.State.get in
  >   <p>(Yuka.int n)</p>
  > Y
  $ run ra6
  File "ra6.mlx", line 2, characters 10-33:
  2 |   let n = count |> Yuka.State.get in
                ^^^^^^^^^^^^^^^^^^^^^^^
  Error: Yuka: this State.get runs one time and never updates. Read it in markup, a memo or an effect, or use State.peek.
  [1]
  $ cat > ra7.mlx <<'Y'
  > let rec make ~count () =
  >   let n = Yuka.State.get count in
  >   <p>(view n)</p>
  > and view n = Yuka.int n
  > Y
  $ run ra7
  File "ra7.mlx", line 2, characters 10-30:
  2 |   let n = Yuka.State.get count in
                ^^^^^^^^^^^^^^^^^^^^
  Error: Yuka: this State.get runs one time and never updates. Read it in markup, a memo or an effect, or use State.peek.
  [1]
  $ cat > ra4.mlx <<'Y'
  > module Row = struct
  >   let make ~(count : int Yuka.State.t) ?(start = Yuka.State.get count) () = <p>(Yuka.int start)</p>
  > end
  > Y
  $ run ra4
  File "ra4.mlx", line 2, characters 49-69:
  2 |   let make ~(count : int Yuka.State.t) ?(start = Yuka.State.get count) () = <p>(Yuka.int start)</p>
                                                       ^^^^^^^^^^^^^^^^^^^^
  Error: Yuka: this State.get runs one time and never updates. Read it in markup, a memo or an effect, or use State.peek.
  [1]
  $ cat > ra5.mlx <<'Y'
  > let[@client] make ~(initial : int) () =
  >   let count = Yuka.State.make initial in
  >   let label = string_of_int (Yuka.State.get count) in
  >   <p>(Yuka.text label)</p>
  > Y
  $ run ra5
  File "ra5.mlx", line 3, characters 28-50:
  3 |   let label = string_of_int (Yuka.State.get count) in
                                  ^^^^^^^^^^^^^^^^^^^^^^
  Error: Yuka: this State.get runs one time and never updates. Read it in markup, a memo or an effect, or use State.peek.
  [1]
  $ cat > ra8.mlx <<'Y'
  > let make ~f () =
  >   let e = Yuka.Form.field_error (Yuka.State.get (Yuka.Form.errors f)) `Title in
  >   <p>(Yuka.text (Option.value ~default:"" e))</p>
  > Y
  $ run ra8
  File "ra8.mlx", line 2, characters 32-69:
  2 |   let e = Yuka.Form.field_error (Yuka.State.get (Yuka.Form.errors f)) `Title in
                                      ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: Yuka: this State.get runs one time and never updates. Read it in markup, a memo or an effect, or use State.peek.
  [1]

A State.get in the body result, outside markup (form C):

  $ cat > rc1.mlx <<'Y'
  > let make ~open_ () =
  >   if Yuka.State.get open_ then <A /> else <B />
  > Y
  $ run rc1
  File "rc1.mlx", line 2, characters 5-25:
  2 |   if Yuka.State.get open_ then <A /> else <B />
           ^^^^^^^^^^^^^^^^^^^^
  Error: Yuka: this State.get runs one time and never updates. Read it in markup, a memo or an effect, or use State.peek.
  [1]

A State.get in a component prop (form B), also the value of Context.Provide:

  $ cat > rb1.mlx <<'Y'
  > let make ~name () = <Label text=(Yuka.State.get name) />
  > Y
  $ run rb1
  File "rb1.mlx", line 1, characters 32-53:
  1 | let make ~name () = <Label text=(Yuka.State.get name) />
                                      ^^^^^^^^^^^^^^^^^^^^^
  Error: Yuka: a prop reads one time; pass the State (<Label text=name />), or use State.peek.
  [1]
  $ cat > rb2.mlx <<'Y'
  > let make ~theme () =
  >   <Yuka.Context.Provide context=Theme.context value=(Yuka.State.get theme)><p /></Yuka.Context.Provide>
  > Y
  $ run rb2
  File "rb2.mlx", line 2, characters 52-74:
  2 |   <Yuka.Context.Provide context=Theme.context value=(Yuka.State.get theme)><p /></Yuka.Context.Provide>
                                                          ^^^^^^^^^^^^^^^^^^^^^^
  Error: Yuka: a prop reads one time; pass the State (<Label text=name />), or use State.peek.
  [1]
  $ cat > rb3.mlx <<'Y'
  > let make ~start () =
  >   <Yuka.Client><Counter initial=(Yuka.State.get start) /></Yuka.Client>
  > Y
  $ run rb3
  File "rb3.mlx", line 2, characters 32-54:
  2 |   <Yuka.Client><Counter initial=(Yuka.State.get start) /></Yuka.Client>
                                      ^^^^^^^^^^^^^^^^^^^^^^
  Error: Yuka: a prop reads one time; pass the State (<Label text=name />), or use State.peek.
  [1]
  $ cat > rb4.mlx <<'Y'
  > let make ~query () =
  >   <Yuka.Await async=(Api.search (Yuka.State.get query)) loading=(Yuka.text "...")>(fun v -> Yuka.text v)</Yuka.Await>
  > Y
  $ run rb4
  File "rb4.mlx", line 2, characters 32-54:
  2 |   <Yuka.Await async=(Api.search (Yuka.State.get query)) loading=(Yuka.text "...")>(fun v -> Yuka.text v)</Yuka.Await>
                                      ^^^^^^^^^^^^^^^^^^^^^^
  Error: Yuka: a prop reads one time; pass the State (<Label text=name />), or use State.peek.
  [1]

A prop reads one time also when the tag is in a hole:

  $ cat > rb5.mlx <<'Y'
  > let make ~name () = <span><Label text=(Yuka.State.get name) /></span>
  > Y
  $ run rb5
  File "rb5.mlx", line 1, characters 38-59:
  1 | let make ~name () = <span><Label text=(Yuka.State.get name) /></span>
                                            ^^^^^^^^^^^^^^^^^^^^^
  Error: Yuka: a prop reads one time; pass the State (<Label text=name />), or use State.peek.
  [1]
  $ cat > rb6.mlx <<'Y'
  > let view name = Yuka.hole (fun () -> <Label text=(Yuka.State.get name) />)
  > Y
  $ run rb6
  File "rb6.mlx", line 1, characters 49-70:
  1 | let view name = Yuka.hole (fun () -> <Label text=(Yuka.State.get name) />)
                                                       ^^^^^^^^^^^^^^^^^^^^^
  Error: Yuka: a prop reads one time; pass the State (<Label text=name />), or use State.peek.
  [1]

A State.get at the top of a Yuka.each row function (form E), also in a hole:

  $ cat > re1.mlx <<'Y'
  > let make ~rows ~sel () =
  >   <ul>
  >     (Yuka.each ~key:(fun item -> item.id) (fun () -> Yuka.State.get rows) (fun item ->
  >        let on = Yuka.State.get sel = item.id in
  >        <li class_=(if on then "on" else "")>(Yuka.text item.title)</li>))
  >   </ul>
  > Y
  $ run re1
  File "re1.mlx", line 4, characters 16-34:
  4 |        let on = Yuka.State.get sel = item.id in
                      ^^^^^^^^^^^^^^^^^^
  Error: Yuka: this State.get runs one time and never updates. Read it in the row markup, a memo or an effect, or use State.peek.
  [1]
  $ cat > re2.mlx <<'Y'
  > let view rows sel =
  >   Yuka.hole (fun () ->
  >     Yuka.each ~key:(fun item -> item.id) rows (fun item ->
  >       <Row selected=(Yuka.State.get sel = item.id) />))
  > Y
  $ run re2
  File "re2.mlx", line 4, characters 21-39:
  4 |       <Row selected=(Yuka.State.get sel = item.id) />))
                           ^^^^^^^^^^^^^^^^^^
  Error: Yuka: a prop reads one time; pass the State (<Label text=name />), or use State.peek.
  [1]

Reads that run again, run later, or run one time at the top level compile:

  $ cat > rok.mlx <<'Y'
  > let initial = Yuka.State.get global
  > let label () = Yuka.text (Yuka.State.get name)
  > let make ~count ~name ~rows ~sel ~query () =
  >   let double = Yuka.State.memo (fun () -> Yuka.State.get count * 2) in
  >   Yuka.Effect.after (fun () -> Yuka.Console.log (string_of_int (Yuka.State.get count)));
  >   let result = Yuka.Remote.make Api.search (fun () -> Yuka.State.get query) in
  >   let once = Yuka.State.peek count in
  >   let local () = Yuka.State.get name in
  >   <div class_=(if Yuka.State.get count > 0 then "on" else "off")>
  >     <button on_click=(fun _ -> Yuka.State.set count (Yuka.State.get count + 1))>(Yuka.int once)</button>
  >     (Yuka.int (Yuka.State.get double))
  >     (Yuka.hole (fun () -> Yuka.text (local ())))
  >     (label ())
  >     <Label text=name on_pick=(fun () -> Yuka.State.get sel) />
  >     (Yuka.each ~key:(fun item -> item.id) (fun () -> Yuka.State.get rows) (fun item ->
  >        <li class_=(if Yuka.State.get sel = item.id then "on" else "")>(Yuka.text item.title)</li>))
  >     <Yuka.Await async=(Remote.async result) loading=(Yuka.text "...")>(fun v -> Yuka.text (v ^ Yuka.State.get name))</Yuka.Await>
  >   </div>
  > let view () = let n = Yuka.State.get count in <p>(Yuka.int n)</p>
  > Y
  $ run rok > /dev/null && echo compiles
  compiles

A module State that the file defines is not Yuka.State:

  $ cat > rst.mlx <<'Y'
  > module State = struct let make x = ref x let get r = !r end
  > let make ~s () = let n = State.get s in <p>(Yuka.int n)</p>
  > Y
  $ run rst > /dev/null && echo compiles
  compiles

Without open Yuka or module State = Yuka.State, State is the project's own module:

  $ cat > rst2.mlx <<'Y'
  > module C = struct
  >   let make () = let theme = State.get () in <p>(Yuka.text theme)</p>
  > end
  > Y
  $ run rst2 > /dev/null && echo compiles
  compiles

Only the binding named make is a component body, and only when its result has a tag:

  $ cat > rmk.mlx <<'Y'
  > let count = Yuka.State.make 1
  > module C = struct
  >   let rec make () = <p>(view ())</p>
  >   and view () = let n = Yuka.State.get count in Yuka.int n
  > end
  > module Doubled = struct
  >   let make s = Yuka.State.get s * 2
  > end
  > let d = Yuka.State.memo (fun () -> Doubled.make count)
  > Y
  $ run rmk > /dev/null && echo compiles
  compiles

A prop that passes State.get as a function compiles:

  $ cat > rfn.mlx <<'Y'
  > let name = Yuka.State.make "a"
  > module L = struct let make ~read () = <p>(Yuka.text (read name))</p> end
  > module C = struct
  >   let make () = <L read=Yuka.State.get />
  > end
  > Y
  $ run rfn > /dev/null && echo compiles
  compiles

Other names for Yuka.State hide State.get from the ppx:

  $ cat > lint_open.mlx <<'Y'
  > open Yuka.State
  > Y
  $ run lint_open
  File "lint_open.mlx", line 1, characters 0-15:
  1 | open Yuka.State
      ^^^^^^^^^^^^^^^
  Error: Yuka: open Yuka.State hides State.get from the ppx. The ppx optimizes and checks reads by the exact names Yuka.State.get and State.get, so a read through the open is not seen, and a read that runs one time is not reported. Write Yuka.State.get or State.get.
  [1]
  $ cat > local_open.mlx <<'Y'
  > let x = Yuka.State.(get s)
  > Y
  $ run local_open
  File "local_open.mlx", line 1, characters 8-26:
  1 | let x = Yuka.State.(get s)
              ^^^^^^^^^^^^^^^^^^
  Error: Yuka: a local open of Yuka.State hides State.get from the ppx. The ppx optimizes and checks reads by the exact names Yuka.State.get and State.get, so a read through the open is not seen, and a read that runs one time is not reported. Write Yuka.State.get or State.get.
  [1]
  $ cat > let_open.mlx <<'Y'
  > let x = let open Yuka.State in get s
  > Y
  $ run let_open
  File "let_open.mlx", line 1, characters 8-36:
  1 | let x = let open Yuka.State in get s
              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: Yuka: a local open of Yuka.State hides State.get from the ppx. The ppx optimizes and checks reads by the exact names Yuka.State.get and State.get, so a read through the open is not seen, and a read that runs one time is not reported. Write Yuka.State.get or State.get.
  [1]
  $ cat > alias.mlx <<'Y'
  > module S = Yuka.State
  > Y
  $ run alias
  File "alias.mlx", line 1, characters 0-21:
  1 | module S = Yuka.State
      ^^^^^^^^^^^^^^^^^^^^^
  Error: Yuka: module S = Yuka.State hides State.get from the ppx. The ppx optimizes and checks reads by the exact names Yuka.State.get and State.get, so a read through S is not seen, and a read that runs one time is not reported. Write Yuka.State.get or State.get.
  [1]
  $ cat > local_alias.mlx <<'Y'
  > let x = let module S = Yuka.State in S.get s
  > Y
  $ run local_alias
  File "local_alias.mlx", line 1, characters 8-44:
  1 | let x = let module S = Yuka.State in S.get s
              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  Error: Yuka: let module S = Yuka.State hides State.get from the ppx. The ppx optimizes and checks reads by the exact names Yuka.State.get and State.get, so a read through S is not seen, and a read that runs one time is not reported. Write Yuka.State.get or State.get.
  [1]
  $ cat > incl.mlx <<'Y'
  > module S = struct include Yuka.State end
  > Y
  $ run incl
  File "incl.mlx", line 1, characters 18-36:
  1 | module S = struct include Yuka.State end
                        ^^^^^^^^^^^^^^^^^^
  Error: Yuka: include Yuka.State hides State.get from the ppx. The ppx optimizes and checks reads by the exact names Yuka.State.get and State.get, so a read through the include is not seen, and a read that runs one time is not reported. Write Yuka.State.get or State.get.
  [1]
  $ cat > open_state.mlx <<'Y'
  > open Yuka
  > open State
  > Y
  $ run open_state
  File "open_state.mlx", line 2, characters 0-10:
  2 | open State
      ^^^^^^^^^^
  Error: Yuka: open State hides State.get from the ppx. The ppx optimizes and checks reads by the exact names Yuka.State.get and State.get, so a read through the open is not seen, and a read that runs one time is not reported. Write Yuka.State.get or State.get.
  [1]
  $ cat > alias_state.mlx <<'Y'
  > open Yuka
  > module S = State
  > Y
  $ run alias_state
  File "alias_state.mlx", line 2, characters 0-16:
  2 | module S = State
      ^^^^^^^^^^^^^^^^
  Error: Yuka: module S = State hides State.get from the ppx. The ppx optimizes and checks reads by the exact names Yuka.State.get and State.get, so a read through S is not seen, and a read that runs one time is not reported. Write Yuka.State.get or State.get.
  [1]
  $ cat > local_open_state.mlx <<'Y'
  > open Yuka
  > let x = State.(get s)
  > Y
  $ run local_open_state
  File "local_open_state.mlx", line 2, characters 8-21:
  2 | let x = State.(get s)
              ^^^^^^^^^^^^^
  Error: Yuka: a local open of State hides State.get from the ppx. The ppx optimizes and checks reads by the exact names Yuka.State.get and State.get, so a read through the open is not seen, and a read that runs one time is not reported. Write Yuka.State.get or State.get.
  [1]

Without open Yuka, open State and module S = State name the project's own State:

  $ cat > own_state.mlx <<'Y'
  > open State
  > module S = State
  > Y
  $ run own_state
  open State
  module S = State

An interface has no reads, so it can open Yuka.State:

  $ cat > sig_open.mli <<'Y'
  > open Yuka.State
  > Y
  $ ./pp.exe --intf sig_open.mli
  open Yuka.State

An alias named State keeps the name:

  $ cat > state_alias.mlx <<'Y'
  > module State = Yuka.State
  > Y
  $ run state_alias
  module State = Yuka.State
