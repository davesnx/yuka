# Islands

An island is a component that runs in the browser. The server renders its
HTML, then the browser downloads its code and makes it interactive. The
rest of the page is plain HTML. A page with no island downloads no
JavaScript.

```ocaml
(* shared/counter.mlx *)
let[@client] make ~(initial : int) () =
  let count = Yuka.State.make initial in
  <button on_click=(fun _ -> Yuka.State.update count succ)>
    "Clicks: "
    (Yuka.int (Yuka.State.get count))
  </button>
```

```ocaml
(* server/pages.mlx *)
let home () =
  Yuka.Server.page ~title:"Home" (fun () ->
      <main><Yuka.Client><Counter initial=0 /></Yuka.Client></main>)
```

## Define an island

- Write `let[@client] make ... = ...` at the top level of an `.mlx` file,
  in the shared library that compiles to native and to JavaScript. The
  file is the component: `counter.mlx` gives `<Counter />`.
- The function is named `make`. A file has one island.
- Each argument is labelled and has a type: `~(initial : int)`. An
  optional argument has a default, `?(limit : int = 3)`, or an option
  type, `?(note : string option)`.
- The last parameter is `()`.
- `start` and `make` cannot be argument names.
- Children are written `~children`, with no type. They are a
  `Yuka.client Yuka.element`.

## Use an island

Put the component in `<Yuka.Client>`. It takes exactly one child, a
component tag, and one optional prop, `start`.

Without `<Yuka.Client>`, a component is a plain function call: the server
prints its HTML and the browser gets no code for it. This compiles only
when the component has no event handler and no hole:

```ocaml
(* shared/greeting.mlx *)
let[@client] make ~(name : string) () = <p>(Yuka.text ("Hello, " ^ name))</p>

(* server/pages.mlx *)
<Greeting name="static" />                         (* HTML only *)
<Yuka.Client><Greeting name="island" /></Yuka.Client>  (* an island *)
```

## Props

The server sends the props to the browser as JSON, so each prop type needs
a codec:

- `int`, `float`, `string`, `bool`, `unit`, tuples, and `list`,
  `array`, `option` and `result` of types with a codec.
- `Issue.t` uses `Issue.codec`, and a type `foo` uses `foo_codec`.
  `[@@deriving codec]` on a record or a variant writes them.
- `'a Yuka.Async.t`: the server sends the value when it is ready, in the
  same streamed response. Show it with `<Yuka.Await>`.

A function, a polymorphic variant or a type parameter cannot be a prop:
the ppx reports "cannot derive a codec for this type" or a similar error.

```ocaml
(* shared/model.ml *)
module Tag = struct
  type t = { name : string; count : int } [@@deriving codec]
end
```

```ocaml
(* shared/tags.mlx *)
let[@client] make ~(tags : Model.Tag.t list) ?(limit : int = 3) () =
  let all = Yuka.State.make false in
  let shown () =
    if Yuka.State.get all then tags else List.filteri (fun index _ -> index < limit) tags
  in
  <div>
    <ul>
      (Yuka.hole (fun () ->
         Yuka.fragment
           (List.map (fun (tag : Model.Tag.t) -> <li>(Yuka.text tag.name)</li>) (shown ()))))
    </ul>
    <button hidden=(Yuka.State.get all) on_click=(fun _ -> Yuka.State.set all true)>
      "Show all"
    </button>
  </div>
```

## State, events and holes

- `Yuka.State.make value` makes a State. `Yuka.State.get` reads it,
  `Yuka.State.set` and `Yuka.State.update` write it.
- An event handler is a function: `on_click=(fun event -> ...)`.
  `Yuka.Event` reads the event: `target_value`, `target_checked`,
  `target_tag`, `key`, the modifier keys (`shift_key`, `ctrl_key`,
  `alt_key`, `meta_key`) and the pointer position in the viewport
  (`client_x`, `client_y`). `prevent_default` and `stop_propagation`
  act on it.
- A hole is a part of the markup that updates when a State it reads
  changes. The ppx makes a hole of each child or attribute of an HTML tag
  whose expression contains `Yuka.State.get`: `hidden=(Yuka.State.get all)`
  above. It does not see a read inside another function, such as
  `shown ()`; write `Yuka.hole (fun () -> ...)` for it.
- Make a State inside `make`. A State made at the top level of a module is
  a ppx error, because every request of the server would share it.

[`state.md`](state.md) explains State, memos and effects.

## Start strategies

The `start` prop says when the browser downloads and starts the island:

| `start` | Download | Start |
|---|---|---|
| `` `Load `` (default) | when the page opens | when the page opens |
| `` `Idle `` | when the page opens | when the browser is idle |
| `` `Visible `` | when the page opens | when the island is visible |
| `` `Interaction `` | when the page opens | at the first pointer, focus or touch event inside it |
| `` `Lazy trigger `` | at `trigger` | at `trigger` |

```ocaml
<Yuka.Client start=`Idle><Counter initial=0 /></Yuka.Client>
<Yuka.Client start=(`Lazy `Visible)><Counter initial=0 /></Yuka.Client>
```

`` `Lazy `` records the events before the start and replays them.

A user can type, tick or choose in an island before it starts. The control
keeps what the user did. When the island starts, Yuka sends `input` and
`change` to that control, so your `on_input` and `on_change` handlers update
the State. A click before the script runs is lost.

## Children

A component takes children with `~children` and places them as any other
element:

```ocaml
(* shared/panel.mlx *)
let[@client] make ~(title : string) ~children () =
  let open_ = Yuka.State.make true in
  <section>
    <button on_click=(fun _ -> Yuka.State.update open_ not)>(Yuka.text title)</button>
    (if Yuka.State.get open_ then children else Yuka.empty)
  </section>

(* server/pages.mlx *)
<Yuka.Client>
  <Panel title="Details">
    <p>"Rendered on the server."</p>
    <Yuka.Client><Counter initial=0 /></Yuka.Client>
  </Panel>
</Yuka.Client>
```

Children work the same in an island, with one difference: children that
come from the server are rendered by the server. The client keeps their DOM
nodes. It can place them, move them and hide them, but it does not render
them again. Place them in one position: the client keeps track of one set
of nodes.

Children from client code, such as `<Panel title="Notes"> <p>"x"</p> </Panel>`
inside another island, are rendered by the client as usual.

A `<Yuka.Client>` in the children is its own island.

## Limitations

- An event handler or a hole outside an island does not compile: "Type
  Yuka.client is not compatible with type Yuka.server".
- An island cannot contain `<Yuka.Client>` in its own markup; that is a
  type error. Pass the inner island as children, as above.
- An island cannot read the current route or search params as a State.
  Pass what it needs as props.

## Build

`yuka islands` finds every file with a `let[@client]` line and writes the
island registry for the client. `Yuka.render ~islands ()` in the client
entry starts the islands of the page. [`getting-started.md`](getting-started.md)
has the dune rules.
