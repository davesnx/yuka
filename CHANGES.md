# Changes

## Unreleased

- Signals: `State.make`, `State.get`, `State.set`, `State.memo` and `Effect`; a component runs once and only the parts that read a signal update (@davesnx)
- No virtual DOM: only holes and keyed lists update (@davesnx)
- mlx syntax through the `yuka.ppx` ppx, with attribute checks (@davesnx)
- Server rendering and hydration from one element tree, on native and on Melange (@davesnx)
- Streaming with `<Yuka.Await>`: send the page shell first, fill in the rest later (@davesnx)
- Islands with `let%client`: a start strategy (`Load`, `Idle`, `Visible`, `Interaction`) and lazy loading chosen where the island is used (@davesnx)
- Codecs with `[@@deriving codec]` for props and action data (@davesnx)
- Actions: declare once, call from the client, run on the server (@davesnx)
- Router: typed paths shared by the server and the client (`Yuka.Router`) (@davesnx)
- `Routes.mlx` and the `yuka-routes` generator: one route tree gives a shared `Routes` module with the route type, a typed `href` and the matcher `find`; overlapping routes fail the build with a location in `Routes.mlx` (@davesnx)
- No web server dependency: `Yuka.Server.respond` writes through functions that your server gives, with a Dream example in the demo (@davesnx)
- Components and islands are written in `.mlx`: `let%client` in any file that is not `.mlx` is a compile error, and `yuka-islands` scans only `.mlx` files (@davesnx)
- A memo is read-only: `State.memo` returns `'a State.read`, and `State.set` or `State.update` on it is a compile error instead of an `Invalid_argument` at run time (@davesnx)
- In a dev build, hydration logs one `console.warn` per mismatch between the server HTML and the client tree, with the island name, the expected and found node, and a short path; a production bundle built with `--define:__YUKA_DEV__=false` has no log code (@davesnx)
- Small client bundles: an app contains only the features it uses, templates are compiled to HTML and paths by the ppx, and `make size` checks the keyed benchmark app against a budget (@davesnx)
