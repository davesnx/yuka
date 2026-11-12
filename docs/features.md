# Features

- **Signals, no virtual DOM.** A component runs once; only the parts that read a signal update.
- **mlx syntax.** JSX for OCaml, checked at compile time.
- **Streaming.** Send the page shell first and fill in the rest when it is ready.
- **Islands.** Start on load, when idle, when visible or on interaction, and download only when needed.
- **Typed routes.** One route tree gives typed links on the server and the client, and loaders and guards on the server.
- **Actions and forms.** Declare once, run on the server, call from the browser. Forms work without JavaScript.
- **Remote and live data.** Queries with retry and optimistic updates; server state pushed over a WebSocket, also across server nodes through a bus (`yuka-live-pg` for Postgres).
- **Scoped CSS.** One stylesheet per module, with a compile error for a class that does not exist.
- **Client navigation.** Prefetch, cache and view transitions.
- **Prerender** pages to static files, and **`yuka dev`** to rebuild and reload on change.
