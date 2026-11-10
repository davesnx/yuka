# Routes.mlx format and generator

Type: wayfinder:grilling
Blocked by: none
Claimed by: none

## Question

What does Routes.mlx look like in mlx syntax, and what does the generator emit for the server and the client: route type, typed href, typed search, layouts, loaders, not-found and error pages?

## Notes

Decided (2026-11-10, after the Nitro study, `.workplace/docs/09-nitro-router-study.md`): keep one `Routes.mlx` tree. No file-system routes: `[id].ml` and `hello.get.ml` are not valid OCaml module names, and params would stay untyped. Endpoint and action nodes, with a method, are declared in `Routes.mlx`. Route rules (headers, cache-control, redirect, prerender) are props on route nodes, and child routes inherit them. No glob rules such as `/blog/**`. The generator emits the matcher as OCaml code; no route list is tried one by one.
