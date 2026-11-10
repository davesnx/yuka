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
- No web server dependency: `Yuka.Server.respond` writes through functions that your server gives, with a Dream example in the demo (@davesnx)
- Small client bundles: an app contains only the features it uses, templates are compiled to HTML and paths by the ppx, and `make size` checks the keyed benchmark app against a budget (@davesnx)
