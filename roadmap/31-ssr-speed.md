# SSR faster than Solid and server-reason-react

Type: wayfinder:task
Release: 0.5
Blocked by: 27
Claimed by: none

## Question

Build: on `make bench-ssr` (100-row issue list, one process, wrk -c32), Yuka serves more requests per second than both Solid on Node and server-reason-react. First numbers (ticket 27): Yuka streamed 4,163, server-reason-react 6,380, Solid 7,689 req/s.

## Resolution

Done (2026-11-10). On `make bench-ssr` (100 rows, one process, `wrk -t4 -c32 -d10s`), run with `--interleave --rounds 5` on the shared benchmark machine (load average 45 -> 54), Yuka's request cycle serves 11,429 req/s (median; min 11,178, max 11,466), Solid 7,545 (7,245 to 7,708) and server-reason-react 6,493 (6,399 to 6,567): Yuka is 1.51 times Solid and 1.76 times server-reason-react, and its slowest round beats the fastest of both. `Yuka.Server.document` serves 10,484. Before (main dbabadd, same run): 3,548 and 3,951.

What changed, in order of gain (in process, 100 rows: 225 -> 69 us and 67k -> 17k words per page through the cycle): escaping straight into the output buffer, attributes printed without a resolved list, a reused output buffer, templates compiled once on the server into static chunks and part slots, and one string instead of a stream when nothing is pending. The HTML is byte for byte the same: `bench/ssr/ocaml/golden.expected` and `demo/test/pages.expected` were written before the change and are compared on `dune build @runtest`. Profile and numbers per step: `.workplace/docs/31-ssr-profile.md`. `bench/ssr/run.ts` has `--interleave` and `--baseline-build-dir`.

The keyed client app grew by 10 B gzip (a field on templates), to 10,036 B of its 10,040 B budget.
