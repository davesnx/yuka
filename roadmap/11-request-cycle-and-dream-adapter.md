# Request cycle and Dream adapter

Type: wayfinder:grilling
Release: 0.2
Blocked by: 09
Claimed by: none

## Question

Which parts of the request does Yuka own (routes, loaders, actions, assets, import map, preload, headers, 404), what is the adapter interface, and how does yuka.dream ship without making Dream a hard dependency?

## Notes

Decided (2026-11-10, from the Nitro study): Nitro is the model for this ticket, not for the page router. Take: one fixed request order; 405 with an `Allow` header when only the method is wrong; HEAD served by GET; cache-control headers from route rules; build-time prerender for exact routes plus pages found by following links. Not in v1: a server-side stale-while-revalidate cache, deploy presets, proxy rules, storage, tasks.

## Resolution

Done (2026-11-10), in increments 2 and 3 of `.workplace/docs/routes-spec.md`. Yuka owns the request in `Yuka.Server.handle`: actions, client JavaScript and public files under fixed prefixes, the trailing-slash 308, redirect nodes, 405 with `Allow`, `OPTIONS` 204, `HEAD` without rendering, guards, loaders started together, route headers and `cache-control`, the streamed page, 404 and 500 pages. A server implements `Yuka.Server.ADAPTER` (request fields, `respond`, `file`, `exists`, its promise type). Dream ships as a second opam package, `yuka-dream`, so `yuka` has no Dream dependency. Changes from the spec are in its section 8.
