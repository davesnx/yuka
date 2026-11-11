# Mount path an app pays only for what it uses

Type: wayfinder:task
Release: 0.5
Blocked by: 29
Claimed by: none

## Question

Build: a render-only app does not carry hydration and slot code, and the `Curry`, `List`, `Array` and option helpers leave the client path, so the keyed app reaches Solid's size (5 KB gzip).

## Resolution

Partly done (2026-11-10). The keyed benchmark app went from 30,578 B, 10,388 B gzip, to 27,296 B, 9,748 B gzip (Solid: 5,006 B gzip). The demo, all chunks, went from 35,264 B to 35,186 B gzip. After the merge with main (navigation, error boundaries, remote data, prefetch, forms), the keyed app is 28,124 B, 10,028 B gzip, and the demo, all chunks, is 43,241 B gzip; those features add about 900 B minified to the keyed app. The budget in `bench/size/budget.json` is 10,040 B gzip.

What changed:

- `Client` is a virtual module: `src/client.mli`, the browser code in `dom/js/client.ml`, and a native stub in `dom/native/client.ml`. The browser code compiles next to `web.ml`, so its DOM calls have known arity and most are inlined. Before, 108 `Curry._1` calls in the client went through `Curry`.
- The mount path uses JavaScript `null`, arrays and `Map` in place of OCaml options and lists. `List`, `Option` and `caml_option` helpers are no longer on the client path of the library. The `List`, `Array` and `Stdlib` code that is left in the keyed app is called by the app itself.
- Each dev check is the raw `__YUKA_DEV__` test in place, so esbuild drops the dev branches before tree shaking. This removes `Curry._3` (392 B). The client no longer reads `Dev.on`.

Steps (`make size`, keyed app, gzip): virtual `Client` 10,250 B; JS mount path 10,087 B; no `List`/`Option` in the core and templates 9,991 B; handler and `each` lookups without options 9,932 B; dev checks 9,828 B; delegation without options 9,748 B.

Not done: a render-only app still links the hydration and slot code. The cause is not a module-level side effect. `yuka.mli` declares `module Client : sig ... end`, so `yuka.js` builds a `Client` object that holds `hydrate`, and esbuild cannot drop one field of an object. Two fixes exist, and each is a public API change:

- `module Client = Client` in `yuka.mli`. This needs `element` to be the manifest of an abstract type in a lower module, which is a refactor across the library.
- A top-level `Yuka.render`.

Either fix saves about 1.5 KB minified.

Done with the second fix (2026-11-11): `Yuka.render` replaces `Yuka.mount` and `Yuka.Client.render` (DESIGN.md, "`Yuka.render`, one client start"). The keyed app went from 30,767 B, 10,886 B gzip (main abe450a) to 30,688 B, 10,846 B gzip; the budget is now 10,860 B gzip. The estimate of 1.5 KB was wrong: `hydrate` itself is small, and the code that adopts server DOM is in the functions that render also runs (`mount_node`, `take`, `mount_slot`, `drop_to_end` test `pos.adopt` at run time), so esbuild keeps it. To drop it, the adopt paths must be reached through a value that only `hydrate` sets.

What is left to reach 5 KB, in minified bytes of the keyed app:

- `client.js`: 9.2 KB, including hydration.
- The reactive core: 6.2 KB.
- Template shapes in the app: about 3 KB of the 4.6 KB of app code. Hydration and the fallback for a failed parse check still need them.
- `curry.js`: 1.0 KB. The app's own calls to closures need it.
- Exceptions: 0.6 KB.
- Load-time code of `Sys`, `Int` and `Obj`: 0.36 KB. It stays while `yuka.js` imports `Json`.

Speed: `bench/keyed/run.ts`, yuka and solid, 10 runs per benchmark. Base (42d990f) and new were run alternately, 5 times each, and the numbers are medians. The load average was 79 to 228. The yuka/solid ratio was 1.069 before and 1.045 after. "Update every 10th" was 27.2 ms before and 27.5 ms after, with script time 2.51 ms before and 1.95 ms after. In the same runs, Solid moved from 31.4 ms to 24.0 ms, so this difference is noise.
