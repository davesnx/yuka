# Routes.mlx format and generator

Type: wayfinder:grilling
Release: 0.2
Blocked by: none
Claimed by: none

## Question

What does Routes.mlx look like in mlx syntax, and what does the generator emit for the server and the client: route type, typed href, typed search, layouts, loaders, not-found and error pages?

## Notes

Decided (2026-11-10, after the Nitro study, `.workplace/docs/09-nitro-router-study.md`): keep one `Routes.mlx` tree. No file-system routes: `[id].ml` and `hello.get.ml` are not valid OCaml module names, and params would stay untyped. Endpoint and action nodes, with a method, are declared in `Routes.mlx`. Route rules (headers, cache-control, redirect, prerender) are props on route nodes, and child routes inherit them. No glob rules such as `/blog/**`. The generator emits the matcher as OCaml code; no route list is tried one by one.

## Resolution

Done (2026-11-10), in three steps of `.workplace/docs/routes-spec.md`: the generator and the shared module (increment 1), the server module and the request cycle (increment 2), the demo on `demo/Routes.mlx` with the typed path GADT removed (increment 3). `Routes.mlx` holds `Router`, `Group`, `Route`, `Endpoint` and `Action` nodes; `yuka-routes --shared` writes the route type, `href` and `find`, and `yuka-routes --server` writes `Routes_server.app` with layouts, loaders, guards, handlers, not-found and error pages and the route rules. Changes from the spec are in its section 8. Navigation that keeps shared layouts is ticket 10.
