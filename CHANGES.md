# Changes

## Unreleased

### yuka

- Client navigation replaces only the content below the deepest shared layout: islands in shared layouts keep their state; `aria-current` follows the path; a new build id (`Yuka-Build`) makes a full page load (@davesnx)
- Breaking: `Yuka.Server.modules` takes `~digest` (use `Yuka_dream.tree_digest dir`), so a deploy that changes client code changes the build id; `Yuka.Server.layer` has a `data` field, and a layout that takes a loader result is rendered again on each navigation (@davesnx)
- Leaving a page stops the action calls of the islands it removes (@davesnx)
- Error boundaries and loading states: `<Yuka.Catch fallback=(fun ~error ~reset -> ...)>` catches exceptions in its children (render, effects, memos, holes, event handlers), also during server rendering; `<Yuka.Show>` shows a `Yuka.Status.t`; `Yuka.mount ~on_error` gets the errors that no `Catch` caught (@davesnx)
- Breaking: an island with no `Catch` now stops at its first exception after it started and keeps its DOM; the error goes to `console.error` and `on_error` (@davesnx)
- Prefetch, navigation cache and view transitions: links are prefetched on hover, focus or pointer down (`Yuka.mount ~prefetch`, `data-yuka-prefetch="visible"` or `"off"`, header `Yuka-Prefetch: 1`); answers are reused by their `Cache-Control` (`max-age`, or once within 10 s for a `no-store` prefetch); a successful action call empties the cache; `~transitions:true` runs each client navigation in a view transition with `data-yuka-nav` on `<html>` (@davesnx)

## 0.2 (YYYY-MM-DD)

First release on opam.

### yuka

- Signals: `State.make`, `State.get`, `State.set`, `State.memo` and `Effect`; a component runs once and only the parts that read a signal update (@davesnx)
- No virtual DOM: only holes and keyed lists update (@davesnx)
- mlx syntax through the `yuka.ppx` ppx, with attribute checks (@davesnx)
- Server rendering and hydration from one element tree, on native and on Melange (@davesnx)
- Streaming with `<Yuka.Await>`: send the page shell first, fill in the rest later (@davesnx)
- Islands with `let%client`: a start strategy (`Load`, `Idle`, `Visible`, `Interaction`) and lazy loading chosen where the island is used (@davesnx)
- Codecs with `[@@deriving codec]` for props and action data (@davesnx)
- Actions: declare once, call from the client, run on the server (@davesnx)
- `Routes.mlx` and the `yuka-routes` generator: one route tree gives a shared `Routes` module with the route type, a typed `href` and the matcher `find`; overlapping routes fail the build with a location in `Routes.mlx` (@davesnx)
- Request cycle in `Yuka.Server`: `yuka-routes --server` writes `Routes_server.app`, and `Yuka.Server.handle` answers a request in a fixed order (assets, trailing-slash 308, redirects, 405 with `Allow`, `OPTIONS` 204, guards, loaders started together, route headers and `cache-control`, `HEAD` without rendering, the streamed page, 404 and 500 pages); a server implements `Yuka.Server.ADAPTER` and calls `Yuka.Server.Make` (@davesnx)
- A page loads no JavaScript unless it has an island or a pending `Await`: the module script is written before the first island, and the fill script only when an `Await` is still pending after the shell (@davesnx)
- `Yuka.Server.page` is now the page value of a route; the full HTML document function is `Yuka.Server.document` (@davesnx)
- No web server dependency in `yuka`; the `yuka-dream` package runs an app on Dream (`Yuka_dream.handler`), and another server implements `Yuka.Server.ADAPTER` (@davesnx)
- Removed: the typed path GADT of `Yuka.Router` (use `Routes.mlx`), and `Yuka.Server.respond`, `stream`, `render_settled`, `handle_action`, `preload_urls` and `import_map` (the request cycle does their work) (@davesnx)
- Components and islands are written in `.mlx`: `let%client` in any file that is not `.mlx` is a compile error, and `yuka-islands` scans only `.mlx` files (@davesnx)
- A memo is read-only: `State.memo` returns `'a State.read`, and `State.set` or `State.update` on it is a compile error instead of an `Invalid_argument` at run time (@davesnx)
- In a dev build, hydration logs one `console.warn` per mismatch between the server HTML and the client tree, with the island name, the expected and found node, and a short path; a production bundle built with `--define:__YUKA_DEV__=false` has no log code (@davesnx)
- Small client bundles: an app contains only the features it uses, templates are compiled to HTML and paths by the ppx, and `make size` checks the keyed benchmark app against a budget (@davesnx)
- A smaller reactive core, adapted from Solid's `signal.ts` (MIT): an effect keeps updating after a memo it reads raises or after the 100-round limit drops work, and a parent effect runs before the children it disposes (@davesnx)
- Breaking: a `not_found` page gets the params of the path of the node that declares it and `~target`, and an `error` page gets them and `~status`; an existing `not_found` or `error` page under a route with params must take those params, and a param named `target` or `status` (for the page that takes it) fails the build (@davesnx)

### yuka-dream

- `Yuka_dream.handler` runs the request cycle of `yuka` on Dream; `Yuka_dream.to_async` and `to_lwt` convert between `Lwt.t` and `Yuka.Async.t` (@davesnx)
- Prerender: `Yuka_dream.prerender` writes the pages marked `prerender=true` and the pages they link to, `404.html` and the client and public files; `Yuka.Server.config ~prerendered` serves them (@davesnx)
