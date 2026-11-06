# Type safety

Scope: what OCaml's type system can enforce in a view library: keys, children, attributes, hook order, Suspense and error boundaries.

## Sources

No URL was assigned for this topic. The notes were read (/home/me/workplace/davesnx/yuka/brain-dump/00-original-notes.md). Everything below about other libraries comes from memory and was NOT checked against their code. Marked "(memory)".

- https://raw.githubusercontent.com/ocsigen/tyxml/master/README.md — read. It says only that TyXML "provides a set of combinators which use the OCaml type system to ensure the validity of the generated document". It does not describe the mechanism. The mechanism below is from memory.
- tyxml, reason-react, server-reason-react, ocaml-vdom, Brr, Note, brisk-reconciler, Elm `Html.Keyed` — not fetched. Memory only.

## Key ideas

- TyXML (memory): elements are `'a elt` where `'a` is a phantom polymorphic variant naming the element, for example `[> `Div] elt`. Children lists are typed by a content-model alias such as `Html_types.div_content_fun elt list`. Attributes are `'a attrib`, with the phantom naming the attribute (`a_href : uri -> [> `Href] attrib`), and each element function takes `?a:<element>_attrib attrib list`. Result: wrong child or attribute is a compile error. Cost: long, hard-to-read error messages, and users need `Html_types` aliases when writing helper functions.
- reason-react (memory): `ReactDOM.props` is one large record or object type shared by all tags. A bad attribute on a given tag is not caught per tag. Children are `React.element`, one type, so no child restrictions.
- server-reason-react (memory): same shape as reason-react so code is shared. Attribute names are checked by the ppx per tag at compile time, not by the type system. Treat as unverified; read the ppx before relying on it.
- ocaml-vdom (memory): attribute and node types are generic. Safety comes from Elm-like message typing: `'msg Vdom.vdom`, event handlers produce `'msg`.
- Brr (memory): typed bindings to DOM. `El.t` is one type; attributes are `At.t` built from strings. Safety is about the DOM API, not HTML content models.
- Note (memory): FRP with typed signals (`'a signal`) and events (`'a event`). No view layer rules; type safety is about time-varying values.
- Elm (memory): `Html.Keyed.node : String -> List (Attribute msg) -> List ( String, Html msg ) -> Html msg`. Keys are required by the type: you cannot build a keyed list without a string per child.
- brisk-reconciler (memory): hooks tracked in the type as a heterogeneous list of slots, so the sequence of hooks is part of the component's type.

## What this means for the library

### Keys

Options, from most to least type-enforced:

1. **Two list constructors.** Static children are `node list`. Dynamic lists use a keyed constructor where the key function is a required argument.
   ```ocaml
   val each : key:('a -> string) -> 'a list -> ('a -> node) -> node
   ```
   You cannot forget the key because there is no keyless version for a dynamic list. This is Elm's design. Trade-off: users can pass a bad key (`fun _ -> "0"`) and the type system cannot prevent it; add a dev-mode duplicate-key check.
2. **Key from the data's identity.** `each` takes a module with `key`.
   ```ocaml
   module type Keyed = sig type t val key : t -> string end
   val each : (module Keyed with type t = 'a) -> 'a list -> ('a -> node) -> node
   ```
   Types force the item type to declare how it is identified. Heavier to write.
3. **No keys: positional diff only.** Fine for static lists; wrong for reordering (state moves to a different item). Only acceptable if list items have no local state and no focus, which cannot be proven in types.
4. **Signal-based lists.** If the library is signal-based, `map` over a list of signals gives each item an identity by construction (like Solid's `For`, which keys by reference). On Melange, reference identity of OCaml values is `===`, which differs from structural equality; document it.

Recommended: option 1 as the default. A phantom could mark list kind (`static` vs `dynamic`) so that `div [ ... ]` with a `list.map` result is a type error; but OCaml's `List.map` returns a plain `node list`, so the check needs a distinct node-list type, which hurts ergonomics. Not recommended unless JSX (mlx) can hide it.

### Typed children

Give nodes a small phantom kind, not a full HTML content model.

```ocaml
type 'kind node
type text and element

val text : string -> text node
val div : element node list -> element node
val button : text node list -> element node     (* Button accepts text only *)
```

For mixed content use subtyping with polymorphic variants:

```ocaml
type +'k node
val text : string -> [> `Text ] node
val div : [< `Text | `Element ] node list -> [> `Element ] node
val button : [< `Text ] node list -> [> `Element ] node
```

Notes:
- Component props can carry this too: `children : [< `Text ] node list` in the prop type. With mlx, the JSX children are passed as a typed list, so the check applies.
- Lists in OCaml are homogeneous. `[ text "a"; icon () ]` fails if the two have different closed kinds. Open variants `[> ...]` usually let this unify, but errors get long.
- Keep the kinds few (`Text`, `Element`, `Fragment`, `Component`). Full HTML content models (TyXML-style: no `<a>` in `<a>`, `<li>` only in lists) are valuable for a validator but hurt the wrapper-component story, since a component returning `element node` loses which element it returns.
- Server and client share the types, so this costs nothing at run time on either target.

### Attributes

Three levels:
1. **Per-tag attribute types (TyXML).** `a_href` only fits `<a>`. Strongest. Compile errors name the offending attribute but are long. Requires generated code for all tags.
2. **Single attribute type, ppx checks per tag.** Weaker types, better messages (the ppx can say "`href` is not an attribute of `div`"). This is the reason-react direction. Works at compile time on both targets because the check is in the ppx.
3. **Typed values only.** Attributes are `string`-keyed but values are typed (`tabindex : int -> attr`, `disabled : bool -> attr`). Catches wrong value types, not wrong names. This is the "minimum safety ala tyxml" the notes mention.

The notes say "same errors as React I would say". Level 3 plus a ppx that checks names covers the errors React (with TypeScript) would catch, with simpler types than level 1. Level 1 is better only if the library wants to enforce HTML validity.

### Hooks and call order

Four ways to remove the rule, in rising distance from React:

1. **Setup/render split.** A component is `props -> (unit -> node)`: setup runs once and creates state and effects; the returned closure renders. State is lexical, so order and conditions do not matter. Used by Solid, Vue, and the old ReasonReact stateful components (memory). Also fits "components are functions with props".
   ```ocaml
   let counter ~initial = Component.make (fun _props ->
     let count = State.make initial in
     fun () -> button ~on_click:(fun _ -> State.update count succ) [ text (string_of_int (State.get count)) ])
   ```
   Trade-off: props change between renders, so the setup closure must read props through a getter (`props ()`) or the library must re-run setup. This is the main design problem of the split.
2. **Hooks indexed in the type.** An indexed monad or applicative (brisk-reconciler style, memory): the hook sequence is a type, `('slots, 'a) Hooks.t`. A conditional hook gives a different type per branch, which is a compile error. Strongest guarantee; syntax needs binding operators (`let*`, `let+`) or a ppx, and error messages are heavy.
3. **Stable identity per call site.** A ppx assigns a unique id to each `let%state` at its source location. Order stops mattering. Hooks in loops or in helper functions called twice need an extra scope id.
4. **State outside render.** Signals (Lwd, derivable). No hook slots at all.

Recommendation: option 1 or 4 (structure, no types needed) if the project wants to drop the rule outright; option 2 if it wants to keep React-like `use_state` calls and have the compiler enforce order. Option 3 is a cheap middle path with ppx cost.

Native note: option 1 and 4 avoid a global "current component", which also helps concurrent server renders. See effects.md.

### Suspense and error boundaries

React throws a promise (Suspense) or an exception (error boundary) from deep in render. OCaml exceptions and OCaml 5 effects are not in types, so a thrown version cannot be type-safe. Make pending and failure part of the values.

```ocaml
type ('a, 'e) Resource.state = Pending | Ready of 'a | Failed of 'e
val Resource.read : ('a, 'e) Resource.t -> ('a, 'e) Resource.state
```

Explicit style: the component matches on the state. Type safe; verbose; no waterfalls hidden.

Phantom style: mark nodes that may suspend.

```ocaml
type (+'s) node
val Resource.use : ('a, 'e) Resource.t -> ('a -> [> `Suspends ] node) -> [> `Suspends ] node
val Suspense.boundary : fallback:node -> [< `Suspends | `Ready ] node -> [> `Ready ] node
val render : [ `Ready ] node -> unit      (* root requires everything handled *)
```

Wrong code (a suspending node without a boundary) fails to type-check at the root. Errors can be typed the same way: `[`Fails of 'e]` in the phantom, with `Boundary.catch : ('e -> node) -> ... -> node`, which removes `'e` from the type. This needs row-polymorphic errors, giving long messages. A simpler variant: one error type per app (`Boundary.catch : (App_error.t -> node)`).

Binding operators give parallel fetches (and no waterfalls):
```ocaml
let+ user = Resource.use user_r
and+ posts = Resource.use posts_r in
...
```

Server (native): the same types describe streaming. The boundary decides what to flush first. Without Melange effects, there is no non-local suspension anyway, so this explicit design is the only one that works on both targets.

## Tensions

- Strong types (TyXML) vs. simple wrappers: precise child types mean components need type annotations or aliases.
- Dropping hook order by setup/render split means props access becomes a getter, which goes against "props are plain function arguments".
- Hook order in types (option 2) uses an indexed monad, which conflicts with the notes' wish to "remove need for compiler/ppx, keep things simple".
- Phantom `Suspends` flows up the tree. Every component above a suspending one gets a `Suspends` type until a boundary. Polymorphic variants with `[> ]` hide this but give hard errors.
- Typed errors need row polymorphism, which hurts message quality. React-like untyped boundaries are simpler but lose the safety the notes ask for.
- Typed list keys: Elm-style forced keys are safe but conflict with "avoid keys entirely"; signal lists avoid keys but add the `===` identity problem on Melange.
- Effects.md: direct-style suspension needs effect handlers, which Melange lacks, so explicit pending states are forced.

## Open questions

- Render-based (React-like) or signal-based (Lwd, derivable)? Hook-order and key answers differ.
- How strict for children: kinds only (Text / Element), or full HTML content model?
- Will mlx (JSX) hide polymorphic-variant kinds well enough for error messages to stay readable? Test with real error output.
- Per-tag attribute types (generated) or ppx name checks?
- One error type per app, or row-typed errors?
- Verify from code, not memory: how server-reason-react validates attributes; how brisk-reconciler types its hooks; how TyXML's `Html_types` aliases read in error messages.
