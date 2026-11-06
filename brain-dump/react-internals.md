# React internals: one merged model

## Sources

- https://pomb.us/build-your-own-react: read (Didact: fibers, work loop, commit, hooks).
- https://github.com/retrogtx/unreacted: read, README only. It lists files (`vdom.ts`, `renderer.ts`, `hooks.ts`) and says nothing about algorithms. I did not read the source files.
- https://www.rob.directory/blog/react-from-scratch: read (view tree, dependency tree, position matching, hooks, effects).
- https://github.com/tigerabrodi/arwaal/: read, README only. It lists fibers, a work loop, five hooks and "batched" updates. No detail on how they work.
- https://tchayen.com/understanding-react-by-implementing-it: read (nodes, positional zip, hooks array, effect queue).
- https://github.com/JoeS51/React-lite/blob/main/ReactLite.js: read (as summarised by the fetch tool).
- https://geekpaul.medium.com/lets-build-a-react-from-scratch-part-1-virtualdom-and-renderer-14f4f716de62: failed (HTTP 403). Nothing taken from it.
- https://romgrk.com/posts/react-functional-components: read. It argues for classes over hooks, so it is a critique, not a model.
- https://www.deepintodev.com/blog/how-to-create-your-own-simple-use-state-hook: read.
- https://github.com/jsdotlua/react-lua: read, README only. It says little about the reconciler and scheduler changes. The port's differences come from the README, not the code.

## Key ideas

The model, in the order the work happens.

1. **Element tree.** An element is plain data: `type` (tag or component function) and `props` with children. It is a description, not an instance. (pomb.us; tchayen: COMPONENT / HOST / TEXT kinds)
2. **Instance tree.** A second tree holds the live things: DOM node, hook slots, parent link. React calls it fibers. Tutorials call it nodes. (pomb.us, tchayen)
3. **Render phase is pure.** Run component functions, compare with the previous tree, build a work-in-progress tree. Do not touch the DOM. An interrupted render shows nothing wrong. (pomb.us; React 18 post, see async-react.md)
4. **Work loop.** Each fiber is one unit of work. It has `child`, `sibling`, `parent`. The loop does a depth-first walk and checks "time left?" between units. This makes render pausable. (pomb.us)
5. **Reconciliation.** Match new children to old children. Same type: reuse and update. Different type: replace. Missing: delete. Extra: create. Matching is by position, or by key when present. (all sources)
6. **Keys.** Position matching gives state to the wrong item when a list reorders. A key matches by identity instead. Tutorials mostly skip it. React-lite does a key map. tchayen says outright that insert and reorder rebuild everything after the change point. (rob.directory, tchayen, React-lite)
7. **Empty slots.** `null` and `false` must still occupy a position, or later siblings shift and lose state. This is a cost of position-based matching without a compiler. (rob.directory)
8. **Commit phase.** One synchronous pass applies the effect list: placements, updates, deletions. Deletions need their own list because the new tree no longer contains them. Function components have no DOM node, so commit climbs to find a parent node and descends to find child nodes. (pomb.us)
9. **Hook storage.** A global "current component" pointer and a per-component array of slots. The Nth hook call reads slot N. There are no names or ids, so the order must not change between renders. (deepintodev, tchayen, rob.directory, pomb.us)
10. **Setter.** A closure over the component and the slot index. In pomb.us it pushes onto the slot's action queue and schedules a render. Queued actions are applied during the next render. That is why `set` does not change the value in the running code.
11. **Effects.** The slot stores callback, deps and cleanup. During render, compare deps by position. After commit, run the old cleanup, then the new callback. tchayen's first version ran effects during render and had to move them to a queue after the update loop. React-lite runs them in a microtask. Layout effects run synchronously after reconciliation. (tchayen, React-lite, rob.directory)
12. **Context needs no slot.** `useContext` walks parent pointers to find a provider. It stores nothing, so it could be called conditionally. (rob.directory)
13. **Who re-renders.** Simplest: whole tree on any change (deepintodev, React-lite). Better: only the component that set state, plus its subtree (tchayen). rob.directory keeps a separate dependency tree (which component created which element) to decide when to reuse old output. Real React skips unchanged subtrees and bails out on `Object.is`-equal state.
14. **What a port must change.** react-lua keeps the scheduler (cooperative) and reconciler but drops `react-dom`. It builds a separate host renderer (`react-roblox`) on the same interface. The tree and scheduler are portable. The host is what changes. (react-lua README)
15. **Critique.** Each render allocates a state array, closures and dep arrays. Hook-wrapped handlers are anonymous in stack traces. Classes avoid both. This is a cost of the closure model, small for most apps. (romgrk)

Where sources differ or add something unique:

- Only pomb.us has fibers, interruptible work and an alternate-tree. Others reconcile in one recursive pass with no commit phase (tchayen mutates the DOM during diff).
- Only rob.directory separates the dependency tree from the view tree.
- Only tchayen documents the bug of effects running during render.
- Known gaps in the tutorials: unmount cleanup is missing (tchayen); `undefined` as state value collides with "unset" (deepintodev); the global hook array is not per component (deepintodev, React-lite).

## What this means for the library

**Must keep**

- Element as data, separate from live instance. It gives SSR and diffing a common input.
- Pure render phase, then one commit. Effects only after commit, never during render. This is the one thing tchayen learned the hard way.
- Cleanup on unmount, in reverse order of setup.
- Keyed identity for lists. In OCaml the key can be required by the type (see below).
- A host interface, so one core drives DOM (Melange), string output (native SSR) and tests.

**Can drop**

- Call-order hook storage. Its only job is to give a stateful call a stable identity without a name. Alternatives:
  - Name the slot at creation. A ppx or a functor produces a typed key:
    ```ocaml
    (* state is a value created once per component instance, not found by index *)
    let counter = Component.make (fun ctx ->
      let count = State.create ctx 0 in         (* slot allocated here, once *)
      fun props ->
        button ~on_click:(fun _ -> State.update count succ)
          [ text (string_of_int (State.get count)) ])
    ```
    The outer function runs once per instance (setup). The inner function runs per render. Setup and render are two stages, like Elm's `init` and `view`, and like Solid or Vue's `setup`. There is no hook order because setup has no loop and no condition around it.
  - Cost: the "closure per render" cost romgrk names goes away, since the setup closure is allocated once. The price is a two-stage component type. It reads less like React.
  - Option B keeps the React shape. Slots are typed `'a State.t` in a heterogeneous store keyed by a ppx-generated id per call site. This removes the order rule but not the "hook only in components" rule.
- The dependency array. Effects can take the value they depend on as a typed argument and compare with an explicit `equal` (see the sketch at the end of the notes: `Effect.xxx a (fun prev next -> ...)`). The compiler and the lint rule both go away.
- Empty-slot placeholders. In OCaml, a child list is `node list` built with `if ... then [x] else []` or `Option.to_list`, or a variant `Empty`. Make `Empty` a first-class node so positions stay stable by construction.

**Can do differently**

- Keys: make the list helper `keyed : ('a -> string) -> 'a list -> ('a -> node) -> node`. Then an unkeyed dynamic list is not expressible. Static children (a fixed tuple or list literal) need no key.
- Children types: a phantom type on `node` (`[ `Text ] node`, `[ `Flow ] node`) can encode "Button accepts only text". This is a type-level check on the element tree. Costs more complex signatures.
- Re-render scope: a state cell holds its subscribers, as in Lwd or Incremental. A write marks only the readers dirty. That replaces "re-render the component and its subtree" with "recompute the readers". It is closer to the notes' interest in mobx/Incremental. It is also a different model from React, so decide it early (see Tensions).
- Component identity for matching: use a variant or a first-class module id instead of comparing function pointers. Function pointer equality in OCaml is unreliable (closures, structural compare raises). Match on a unique id per component definition.

**Melange vs native**

- Work loop and time slicing: needs a scheduler primitive (`requestIdleCallback`, `MessageChannel`, `setTimeout`). Native SSR has no need to yield. Render to string in one pass. Put the scheduler behind the host interface and make it a no-op on native.
- Effects never run on the server. With a render/commit split this is free: SSR runs render only, and effects are queued only by commit.
- Global "current component" pointer: fine on JS (single thread). On native with threads or OCaml 5 domains it must be per-domain or passed explicitly (as `ctx` above). Passing it explicitly is also what removes the hook order issue.
- Value equality: Melange compiles records, options and variants to JS objects, so `==` identity differs from OCaml structural equality. For dep comparison use explicit `equal` functions (see the `melange-advanced` skill).
- Concurrency (OCaml 5 effects) can be used for a "suspend": the component performs an effect that the renderer handles. That does not exist on the Melange side, because JS has no effect handlers. A Melange design must use exceptions or a returned `Pending` variant.

## Tensions

- **React shape vs setup/render split.** Keeping `fun props -> ...` with hooks is familiar and portable for users. Removing hook order needs two-stage components. Pick one first; the rest follows.
- **Component re-render vs fine-grained signals.** The tutorials all re-run component functions. A signal model makes interruptible, pure-render scheduling harder, because dependencies are discovered by running code.
- **Interruptible render needs a pure render.** Any hidden mutation in the render function breaks it. OCaml does not enforce purity, so the contract is by convention, as in React.
- **Position vs identity.** Position matching is simple, small and fast. Keys add API surface. Type-required keys add more types.
- **No compiler vs allocation cost.** Per-render closures and arrays (romgrk) are the reason for React Compiler. A setup stage avoids the allocation by design. That is a real advantage, but it moves complexity to the user.
- **Test claims.** The tutorials are simplified, and some do things real React does not (tchayen's DOM writes during diff). Treat them as a minimal model, not behaviour to copy.

## Open questions

- One stage (React-like, call-site ids by ppx) or two stages (setup then render)?
- Where does state live: on the component instance, or in standalone cells that components subscribe to?
- Is a fiber-like structure (pausable work) wanted at all in v1, or only a pure render plus a single commit, with the host able to add yielding later?
- How are component ids made without function-pointer equality: ppx, first-class modules, or a `Component.make` that mints an id?
- Do effects get explicit `equal`, or a default (`==` on JS, structural on native)? The two differ for the same OCaml value.
- Is the SSR native runtime the same code as the Melange runtime (shared core, host interface), or a second implementation?
- I did not read the unreacted and arwaal sources. If those matter, read `src/hooks.ts` and `fiber.ts` directly.
