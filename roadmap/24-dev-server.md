# Dev server with hot reload

Type: wayfinder:grilling
Release: 0.4
Blocked by: 11
Claimed by: none

## Question

A `yuka dev` command: rebuild on change with dune watch, restart the server, reload the browser, and keep island state where possible. Build it.

## Notes

Decided (user, 2026-11-10): the recommended option and every recommended answer in `.workplace/docs/app-spec.md`, section 24.

## Resolution

Done (2026-11-10): option A, level 1 (`.workplace/docs/app-spec.md`, section 24; build changes in "24: changes during build").

- `yuka dev [--build TARGET]... [--assets DIR]... [--state FILE] [--dune CMD] [--kill-after S] -- SERVER ARGS` runs `dune build --watch`. It restarts the server when its executable changes or it exited, with `SIGTERM` and then `SIGKILL`. A change of only CSS under `--assets` is swapped in the page; another asset change reloads it. A failed build keeps the server and shows the errors in an overlay.
- The server, with `YUKA_DEV=1`, serves `/_yuka/dev` (SSE of the state file) and puts the reload script in full pages. Without it, there is no route and no script.
- The browser reloads and keeps the scroll position; island state is lost.
- `make demo-dev` runs the demo this way. Run by hand:
  - an edit of `views.mlx` reloaded the page in 3.6 s with the new text, and scroll 200 was kept;
  - an edit of `style.css` changed the color with no reload;
  - a syntax error showed the overlay;
  - the fix removed it and reloaded.
- Tests: cram `gen/test/dev.t` (arguments; restart loop with a fake dune and a fake server; `SIGKILL` after `--kill-after`); cycle `dev` cases; jsdom dev cases in `test/navigation`.
- Production: no change in `make size` or `make measure-pages`.

Not built: level 2 (island remount without reload), dune RPC, and an e2e that edits files.
