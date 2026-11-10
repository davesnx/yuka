# Runtime size budget

Type: wayfinder:grilling
Blocked by: 03, 04
Claimed by: none

## Question

With the stdlib replaced, what is the next step to reach 5 KB gzip, and which budget does CI enforce?

## Resolution

Done for this round (2026-11-10). The keyed benchmark app went from 25,294 B to 11,015 B gzip (Solid: 5,006 B); the demo, all chunks, from 41,429 B to 36,319 B gzip. `make size` prints the sizes and fails above the budget in `bench/size/budget.json` (11,345 B gzip for the keyed app); CI runs it.

What made the difference: no module-level side effects, so unused features drop out; template HTML and paths emitted by the ppx; a JS `Map` in place of `Hashtbl`; no `sprintf` on the client. Yuka no longer depends on melange-tiny.

Not reached: 5 KB. What is left in the keyed app: the reactive core (8.6 KB minified; needs a simpler graph than the one adapted from reativa), the mount path (9.5 KB; a render-only app carries hydration and slot code), template shapes in app code, and about 4.5 KB of `Curry`, `List`, `Array` and option helpers. Each needs a new ticket.
