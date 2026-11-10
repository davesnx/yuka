# Docs for 0.2

Type: wayfinder:task
Release: 0.2
Blocked by: 09, 11, 16
Claimed by: none

## Question

Build: the README getting started uses `Routes.mlx` and `yuka.dream`. odoc builds with no warnings, and every public value has a doc comment.

## Resolution

- README "Getting started" is now a new project from `opam install yuka
  yuka-dream mlx`: `Routes.mlx`, a shared library with the `Routes` module
  and one island, a server on `yuka-dream`, a Melange client. The files were
  copied from the README into an empty directory outside the repository and
  built against `yuka` and `yuka-dream` installed with `dune install -p`;
  in headless Chromium the page renders, the island hydrates and counts
  clicks, with no console error. The demo instructions moved to "The demo".
- Fixed on that path: the import map needs every directory under
  `out/node_modules` (`melange.js` and `yuka.js` too; with only `melange`
  and `yuka` the island does not start), also in "With Dream". A route tree
  where no function takes the request gives `Routes_server.app` a weak type
  variable; the README adds `routes_server.mli` with
  `val app : Dream.request Yuka.Server.app`.
- Every value in `src/yuka.mli` and `dream/yuka_dream.mli` has a doc
  comment (checked on the odoc HTML: 0 values without one). Some types and
  modules still have none.
- `dune build @doc` prints no warnings, also from an empty build directory
  with the dune cache off.
- README says `href` raises `Invalid_argument` for a `""`, `"."` or `".."`
  segment. The reativa credit is still true: the signal core is unchanged.
