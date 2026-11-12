# Effect timing: `Effect.after` and `Effect.before`

Type: wayfinder:task
Release: 1.0
Blocked by: none
Claimed by: none

## Question

DOM bindings (holes, reactive attributes, keyed lists) and the bodies of `Effect.run` share one queue in `src/scheduler.ml`, ordered by depth, level and id. After a write, a user effect can run before the DOM update of the same change and read the old DOM, and the first run of `Effect.run` is in the component body, before the nodes of the component exist. Decided by the user (2026-11-12): replace `Effect.run` with `Effect.after` (the common case: first run after the mount, later runs after the DOM updates of the same change) and `Effect.before` (the old timing); `Effect.on_change` gets the timing of `after`; no timing parameter, no compatibility alias.

## Resolution

Done (2026-11-12). Design: DESIGN.md, "`Effect.after` and `Effect.before`".

- The scheduler has a second queue, `late`, for `after` effects. A flush round runs the pending DOM bindings and `before` effects while there are any, in the old order; then the pending `after` effects, parents first. A write in an `after` effect starts new rounds. The limit of 100 rounds, error routing to `Catch` and islands, cleanup order and disposal do not change.
- First run of `after`: inside a batch or a flush it waits for the end of that batch; else it is at once. `render` and hydration now run in a batch, and list rows and components in a hole that runs again are created inside a flush, so the first run finds the component's elements. At the top level of `Yuka.owner` it runs at once; in an event handler, at the end of the handler.
- Internal effects (holes, attributes, keyed lists, `Remote.use`, `Live.use`) keep the old timing. Demo: the two window `keydown` effects are `after`.
- Keyed app: 7,962 B gzip (-5 B; budget 7,981 B). The client calls `Base.run_effect` and no longer bundles `Base.Effect`; `flush` lost its empty-queue check. Pages that bundle `Base.Effect` grow: one-island pages +90 B (counter), +102 B (Codec props), +101 B (Remote); demo start +108 B; demo `/` and `/my` +124 B, `/new` and `/issue/YUK-1` +118 B.
- Tests: `test/cases/cases.ml` (`after:` cases, on native and in Melange), `test/melange/dom_cases.ml` (the DOM after a change, the first run finds its element, `on_change`, an effect created in a handler) and `catch_cases.ml` (first run raises, children that fail). The regression cases fail on the code before this change (`after sees the writes of before effects`: got `0/0 5/0`; `reads the DOM of the same change`: got `none 0`).
