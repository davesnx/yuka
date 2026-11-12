# Changes

## Unreleased

### yuka

- A page with islands loads the client navigation code (fetch, swap, cache, prefetch, history) with a dynamic `import()` on the first click on a link, `popstate`, `Browser.navigate`, or pointer, focus or touch on a link, instead of at start: about 2.3 KB gzip less on a one-island page and 1.3 KB on the demo start. The first navigation waits for that module; a click is still prevented at once and is not lost. If the load fails or takes more than 3 s, the waiting navigations and every later one until the next page load are full page loads, with one `console.error`. `~navigation:false` never loads it. `Yuka.Client` is now a module alias, and `Yuka.server` and `Yuka.client` show their equation to internal types (@davesnx)
- A page with islands loads the code of `Codec`, `Status`, `Remote`, `Live` and `Form` only in the chunks of the islands that use them, and the action transport only when an island calls an action; `scripts/bundle.ts` marks the library files as free of side effects. `make size` prints the JavaScript that a one-island page, the demo start and each demo page load (@davesnx)
- Breaking: `Yuka.render` is the one client start and replaces `Yuka.mount` and `Yuka.Client.render`. `Yuka.render ~islands ()` starts the islands and navigation (`yuka.ppx` rewrites a bare `~islands` into `~islands:Yuka_islands.registry`); `Yuka.render ~root:(container, app) ()` builds a client-only tree; `Yuka.unmount ()` stops both (@davesnx)
- Security: a form redirect to an absolute URL must be `http:` or `https:` as well as on the request `Host` (`javascript://HOST/...` and `data://HOST/...` were accepted) (@davesnx)
- Breaking: props on lowercase tags are snake_case: `on_click`, `on_mousedown`, `view_box`, `stroke_width`, `xlink_href`; a camelCase prop such as `onClick` is a compile error that gives the snake name (@davesnx)
- Client navigation replaces only the content below the deepest shared layout: islands in shared layouts keep their state; `aria-current` follows the path; a new build id (`Yuka-Build`) makes a full page load (@davesnx)
- Breaking: `Yuka.Server.modules` takes `~digest` (use `Yuka_dream.tree_digest dir`), so a deploy that changes client code changes the build id; `Yuka.Server.layer` has a `data` field, and a layout that takes a loader result is rendered again on each navigation (@davesnx)
- Leaving a page stops the action calls of the islands it removes (@davesnx)
- Remote data: `Action.query`, `Remote.use` (a `Status.t` signal with retry, abort and `enabled`), `Remote.refetch`, `Remote.invalidate`, `Remote.mutate` with `Optimistic`; server renders embed the answers so hydration sends no request (@davesnx)
- Breaking: `Action.t` has a third type parameter, the kind (`[ `Mutation ]` for `declare`, `[ `Query ]` for `query`) (@davesnx)
- Error boundaries and loading states: `<Yuka.Catch fallback=(fun ~error ~reset -> ...)>` catches exceptions in its children (render, effects, memos, holes, event handlers), also during server rendering; `<Yuka.Show>` shows a `Yuka.Status.t`; `Yuka.render ~on_error` gets the errors that no `Catch` caught (@davesnx)
- Breaking: an island with no `Catch` now stops at its first exception after it started and keeps its DOM; the error goes to `console.error` and `on_error` (@davesnx)
- Forms: `[@@deriving form]`, `Form.action`, `Server.Form.implement` and `<Yuka.Form>`; a form posts to the page URL with no JavaScript (303 on success, 422 with the sent values and errors), and inside an island it submits through `Action.call` with a pending state and the same decoder (@davesnx)
- Live data: `Topic.declare`, `Live.use` (a `Status.t` signal with `stale` while the socket reconnects), `Live.mutate`, and `Server.Live.serve` and `publish`; one WebSocket per page (`GET /_yuka/live`), full state on each change, reconnect with backoff, origin and CSRF checks with token renewal (`GET /_yuka/csrf`), `Server.Live.revoke` and connection limits; server renders embed the state (@davesnx)
- Breaking: `Yuka.Server.ADAPTER` has `csrf_token`, and `Yuka.Server.request` a `csrf_token` field; it is called only when a page renders a `Live.use` (@davesnx)
- Breaking: the action call (`POST /_yuka/action/<name>`) and `Action` routes refuse (403) a request with no `Origin` unless it has `Sec-Fetch-Site: same-origin`; the action call checks the origin, the name and the content type before it reads the body (@davesnx)
- Prefetch, navigation cache and view transitions: links are prefetched on hover, focus or pointer down (`Yuka.render ~prefetch`, `data-yuka-prefetch="visible"` or `"off"`, header `Yuka-Prefetch: 1`); answers are reused by their `Cache-Control` (`max-age`, or once within 10 s for a `no-store` prefetch); a successful action call empties the cache; `~transitions:true` runs each client navigation in a view transition with `data-yuka-nav` on `<html>` (@davesnx)
- Breaking: `Yuka.Async.resolved` is now `Yuka.Async.return` (@davesnx)
- Security: a URL attribute (any case) with a `javascript:` or `vbscript:` URL, or a `data:` URL where it opens or loads a document or a script, is printed and set as `about:blank#blocked` (data: images and media are kept); a literal one in `.mlx` is a build error. A `srcdoc` of `iframe` or `href` of `base` that is not a literal in `.mlx` is printed and set as `""`. An attribute name that starts with `on` or has a space, a control character, a quote, `<`, `>`, `/` or `=`, or an empty one, raises (a build error in `.mlx`, where a string event handler does not build either). A tag name that is not a letter followed by letters, digits and `-` raises. `Yuka.Template.make` is for the ppx only. In the browser the URL check runs where the attribute is set, with the element, as on the server. `Yuka.Browser.navigate` does nothing with a `javascript:`, `vbscript:` or `data:` URL, and a form follows only a `redirect` on this site. `<script>` and `<style>` text is escaped inside `<select>`. `Yuka.template_of_shape` makes a hand-written template and checks its fixed attributes. `<script>` and `<style>` take one text: in HTML it is printed raw with every `</` and, in JavaScript, `<!--` made safe (every `<` as `\u003c` in a non-JavaScript script); inside `svg` and `math` (MathML all the way down) it is escaped as before. Breaking: an element, component or island inside `<script>` or `<style>` is a build error, and two children raise `Invalid_argument`, in any namespace (@davesnx)
- Breaking: the route tree is `Routes.ml`, one OCaml expression `Router.make [ Router.route Home ~path:"/" ~page:Pages.home; ... ]` with no `open` or `let`, instead of `Routes.mlx`; `yuka-routes` reads it from stdin with `--source FILE` (no `mlx-pp` step), and attachments must be value paths (@davesnx)
- Faster server rendering, with the same HTML: about three times the requests per second on `make bench-ssr`, ahead of Solid and server-reason-react on the benchmark machine. A page with nothing pending after its shell is sent as one response with `Content-Length` instead of a stream; a `HEAD` on a page renders it and sends the same headers as `GET` (before: no page body call and `Content-Length: 0`) (@davesnx)
- Live data on more than one server node: `Server.Live.use_bus ~node bus` joins a bus that carries "this key changed"; other nodes load the key again for their subscribers (one load per key at a time, coalesced), every subscribed key loads again after the bus reconnects, and `Live.mutate` settles on the socket's node only after it loaded the action's change (the action answer carries a `live` mark, `sync` carries `after`). `Server.Live.changed`, `instance`, `mark`, and an in-memory bus for tests; `Yuka_dream.handler ?live` serves a second node in one process (@davesnx)
- New package `yuka-live-pg`: a `Server.Live.bus` over Postgres `LISTEN`/`NOTIFY` (postgresql-ocaml, waits on the socket with Lwt, reconnects and calls `on_restart`) (@davesnx)
- `yuka dev`: runs `dune build --watch`, restarts the server when its executable changes and reloads the browser keeping the scroll position, swaps changed stylesheets with no reload, and shows build errors in an overlay; the cycle serves `/_yuka/dev` and the dev script only with `YUKA_DEV=1` (@davesnx)
- CSS per module: `module Css = [%yuka.css "file.css"]` gives one scoped class name per class of the file; the server prints each sheet once, before its first use (an island's sheets before the island), the browser adds missing sheets to `<head>` and moves new ones there after a client navigation; `yuka-css` writes the sheets for `Yuka.Server.config ~css`, served at `/_yuka/css/` and written by a prerender (@davesnx)
- `Yuka.suspend ~loading ?failed el`: a server element that arrives later (an `Async.t`), shown and streamed as `<Yuka.Await>` (@davesnx)

### yuka-dream

- `Yuka_dream.handler` serves `GET /_yuka/live` (live data); it needs Dream sessions that every server process shares and that survive a restart (`Dream.cookie_sessions` with `Dream.set_secret`) (@davesnx)

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
