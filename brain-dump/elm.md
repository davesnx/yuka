# Elm and Elm-like architectures: The Elm Architecture, elm/ui, Html.Lazy

Marks: "(src)" = from a source I read. "(mine)" = my own knowledge, not checked against a source in this session.

## Sources

- https://jfmengels.net/caching-behind-elm-lazy/ : read.
- https://jfmengels.net/beyond-elm-lazy-arguments/ : read. It covers only the 8-argument limit of `Html.Lazy`, not general argument choice.
- https://jfmengels.net/make-your-roots-lazy : read.
- https://guide.elm-lang.org/webapps/structure.html : read (components, reuse).
- https://github.com/mdgriffith/elm-ui (README, raw): read. The package page at package.elm-lang.org failed: it is an Elm app, so the fetch got only the HTML shell. The README does not describe `column`, `px`, `shrink`, or give formal guarantees.
- https://ocaml.org/p/vdom/latest/README.md.html : failed (HTTP 404). Read the raw README at https://raw.githubusercontent.com/LexiFi/ocaml-vdom/master/README.md instead : read.
- https://github.com/OvermindDL1/bucklescript-tea : read. The README says nothing about Cmd, Sub or components.
- https://sporto.github.io/elm-patterns/architecture/nested-tea.html and the 2016 elm-discuss thread "Design of Large Elm apps": seen only as search-result snippets, not opened. Treat as second-hand.
- Not fetched: Elm's own source for `Cmd`, `Sub`, `elm/html`. Those points are (mine).

## Key ideas

The Elm Architecture (TEA)
- State is one `Model`. `view : Model -> Html Msg` is pure. `update : Msg -> Model -> Model * Cmd Msg` is the only place state changes. `Sub` declares external event sources as data, as a function of the model. (mine)
- `Cmd` is a description of an effect (HTTP, focus, random). The runtime runs it and sends the result back as a `Msg`. Handlers never perform effects. (mine)
- Event handlers in `Html` produce `Msg` values. Views never hold callbacks that mutate. (mine)
- ocaml-vdom (LexiFi) follows this: one state type, `view`, `update`, commands that return messages. (src)

Components in Elm
- The official guide refuses them: "Actively trying to make components is a recipe for disaster in Elm." Reason given: "components = local state + methods" and "There are no objects in Elm!" (src: guide)
- Instead: plain functions. A `viewSidebar` takes what it needs. Small state goes into the existing `Model`. (src: guide)
- "Do not plan ahead": do not build reusable modules early. Extract after you see similar code twice. Build modules around one central type. (src: guide)
- Nested TEA (each child has its own Model/Msg/update, wired by the parent) exists as a pattern. Known cost: boilerplate. Community advice (second-hand): prefer a flat update, extract helpers with the narrowest arguments, split only the model record. (src: search snippets)

Html.Lazy
- `lazy f a b` builds a thunk node that stores `[f, a, b]`. It does not call `f` while building the view. (src: caching)
- On diff, each stored argument is compared with JS `===`. If all match, the old rendered subtree is reused and its diff is skipped. If any differ, `f` runs and the result is diffed. (src: caching)
- Only the last result is kept. A -> B -> A recomputes. Two copies of the same lazy node keep two caches. (src: caching)
- `===` gives false negatives: equal data with a new reference misses. It is cheap. (src: caching)
- The call to `f` happens during diff or render, not during `view`. Safe only because Elm is pure. (src: caching)
- Alternatives discussed but not in elm/html: deep equality (Gren's default), a small cache of several results, a global cache (memory risk). (src: caching)
- Max 8 arguments (`lazy8`). Packing arguments into a tuple or record defeats caching, because the record is always new. Workaround: patch the compiled JS so the thunk compares record fields, not the record. (src: beyond)
- Put `lazy` at the root of `view`. Elm does not skip `view` when `update` returns the same model, so root lazy gives nearly that effect: empty diff, no patches. (src: roots)
- Nested update like `{ model | x = X.update m model.x }` always builds a new record. Root lazy then always misses. Move `lazy` down to each page or sub-view, taking its sub-model. (src: roots)
- A freshly built config record passed next to the model also makes it miss. (src: roots)

elm-ui
- Goal: a replacement for HTML+CSS layout and styling. Stated aims: simple view code, "many common CSS layout errors are not possible to write", fast, style changes in one place. (src: README)
- Primitives: `el attrs child` (one child), `row attrs children`, `text`. Attributes are typed functions (`Background.color`, `Border.rounded`, `padding`, `width fill`) instead of CSS strings. (src: README)
- `column`, `px`, `shrink`, and the link between `Length` and layout rules: (mine, unverified).

ocaml-vdom (LexiFi)
- `Vdom` is pure and has no JS dependency, so it runs server-side or in tests. `Vdom_blit` does DOM rendering. (src)
- Event handlers live at the root (delegation). Reason given: comparing functions is "not well-defined in OCaml". (src)
- Each node has a key string, default = tag name. Children are grouped by key, then paired in order. (src)
- Redraws are batched with `requestAnimationFrame`. (src)
- Controlled `value`: if the handler does not update state, the input is effectively read-only. (src)
- In production at LexiFi since 2016. No interface stability promise. The README describes no component abstraction beyond functions over the model. (src)

bucklescript-tea
- Follows the Elm API closely. `update` takes model first, then msg (opposite of Elm), for easier matching on messages. Planned but undone: a WebComponent layer, a lower-allocation "OCamlized" API, a React backend, a "Binding" approach that builds the vdom once. (src)
- Licence is GPL/LGPL, which matters if the library borrows code. (src)

## What this means for the library

Goal: Elm guarantees (pure view, effects as data, lazy by physical equality) plus React-style local state and composition.

1. Pure view, enforced by types.
   - Make the render function return a pure tree: `props -> 'msg node`. Effects and state access happen through a separate handle created at definition time, not through calls inside the body. This removes hook order, because nothing is registered by call order.
   ```ocaml
   type ('props, 'state, 'msg) component = {
     init   : 'props -> 'state;
     update : 'props -> 'state -> 'msg -> 'state * 'msg Cmd.t;
     view   : 'props -> 'state -> 'msg Html.t;
     subs   : 'props -> 'state -> 'msg Sub.t;
   }
   ```
   This is TEA per component. The cost is boilerplate at each mount (see Tensions).

2. Local state without nested-update boilerplate.
   - Mount function turns a component into a child node and maps its messages to nothing visible to the parent. The runtime owns the child state in the tree, keyed by position or key. The parent sends props down, and receives only messages the child chooses to emit.
   ```ocaml
   val mount : ('p, 's, 'm) component -> 'p -> 'out Html.t   (* child msg stays inside *)
   val emit  : 'out -> 'm Cmd.t                              (* child tells the parent *)
   ```
   This replaces `Html.map` + `{ model with x = ... }` chains. It trades Elm's single visible model for hidden per-instance state. Elm refuses this. Name it as a deliberate choice.

3. Effects as data.
   - `Cmd.t` is a value (variant or record of closures plus a description). `update` returns it. Runtime runs it after commit.
   - Tie effects to renders: an effect is `Sub`-like, declared as a function of state, with an explicit `equal` on its key. The runtime starts, restarts, or stops it by diffing keys, as Elm does for `Sub`. This answers the notes' "why this effect runs": the reason is the key that changed.
   ```ocaml
   val Effect.sync : key:'k -> equal:('k -> 'k -> bool) -> ('k -> 'm Cmd.t) -> 'm Sub.t
   ```
   Default `equal` should be physical equality (`==`) as the notes' `~equal=???` suggests. See Tensions about Melange.

4. Lazy by physical equality.
   - `Html.lazy1 f a`, `lazy2 f a b`. OCaml has no arity limit, so offer `lazyN` over a record only if the compare walks fields. A plain record argument fails the same way as in Elm.
   - Alternative that avoids the 8-argument problem: a ppx generates a props record type with a field-wise `==` comparer. This is Jeroen's `lazyShallow` done properly at compile time, with no JS patching.
   - Store the last result per node, as Elm does. Optionally keep a few (cheap).
   - Apply at component roots by default: `mount` wraps `view` in lazy over `(props fields, state)`. Needs the update function to return the same `state` physically when nothing changed. Offer `update` returning `'state option`-like "no change" so the runtime keeps the old pointer.

5. Layout without CSS.
   - elm-ui style: `Ui.row`, `Ui.column`, `Ui.el` with typed attributes (`Length.fill`, `Length.px 10`) and a compile-time palette. Typed children (the notes' "Button only accepts Text") fit a GADT or polymorphic-variant child kind: `[< `Text ] node list`.
   - Server render: `Vdom` pure core, as LexiFi did, with the DOM blit separate. Native renders the pure tree to a string. Melange blits.

6. Events.
   - Handlers are `'msg`-producing values or closures. Without function equality, delegation at the root (LexiFi) avoids diffing handlers. Alternative: compare handler closures physically and re-attach when different.

## Tensions

- Elm bans components. This library wants them. The Elm guide's argument ("components = local state + methods") is exactly what React-style local state is. Choose: components as functions over a central type (Elm), or hidden per-instance state (React). The brief picks the second; the first remains available through option 1 plus flat state.
- Hidden local state breaks "view is a function of Model". Time travel, replay, SSR hydration, and tests of a whole page need all state to be serialisable and reachable. Keep local state as typed values the runtime can dump, not opaque closures.
- Lazy needs stable physical identity. Melange compiles some OCaml values in ways that break `===` for equal data: tuples, variants with payloads, records rebuilt each render, `int64`, and nested options (`Some None`, `Some ()`), which get a fresh box. `Some x` with `x` not an option compiles to `x` itself, so it keeps the identity of `x`. See the `melange-advanced` skill. A "no change" `update` that returns the old pointer is not enough if props are rebuilt in the parent's `view`.
- Native and JS have different `==` behaviour for some values. Lazy results on the server are useless (render once), so lazy there should be a no-op.
- Elm's laziness is safe because `view` is pure and may run late. If the library lets render code read state handles or run effects, deferred or skipped evaluation becomes observable.
- Hooks-order removal (notes) vs. declaring state inside `view`: both cannot be had. Declaring state in `init` fixes order by construction but separates state from view code, which React users like colocated.
- Nested TEA boilerplate vs. hidden state: the cost of the first is code, the cost of the second is lost visibility.
- bucklescript-tea licence (GPL/LGPL): do not copy code into a permissively licensed library.

## Open questions

- Is per-instance state owned by the runtime tree (React) or stored in one global model keyed by path (Elm-like, re-frame-like)? The second keeps one store and still gives local components. See `elm-likes.md`.
- Should `update` be per component with its own `Msg` type, or should components expose only `state` and `set`? How much of TEA do users have to write?
- What is the equality contract: `==` always, a user-given `equal`, or a ppx-derived shallow compare for props?
- Do effects return messages (Elm) or write to state directly (React)? Messages give replay; direct writes give less code.
- Does typed layout (elm-ui) replace CSS fully, or sit beside it? Not answered by the README.
- How would lazy interact with a fine-grained reactive design (lwd, signals from the notes)? Lazy in a vdom and signals solve the same problem differently; mixing both is probably wrong.
- Event delegation at the root or per-node handlers? LexiFi's choice avoids comparing functions but costs a search through the tree per event.
