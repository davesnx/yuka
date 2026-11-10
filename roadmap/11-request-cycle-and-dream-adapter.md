# Request cycle and Dream adapter

Type: wayfinder:grilling
Release: 0.2
Blocked by: 09
Claimed by: none

## Question

Which parts of the request does Yuka own (routes, loaders, actions, assets, import map, preload, headers, 404), what is the adapter interface, and how does yuka.dream ship without making Dream a hard dependency?

## Notes

Decided (2026-11-10, from the Nitro study): Nitro is the model for this ticket, not for the page router. Take: one fixed request order; 405 with an `Allow` header when only the method is wrong; HEAD served by GET; cache-control headers from route rules; build-time prerender for exact routes plus pages found by following links. Not in v1: a server-side stale-while-revalidate cache, deploy presets, proxy rules, storage, tasks.
