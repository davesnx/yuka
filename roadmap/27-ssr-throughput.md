# SSR throughput and its reference

Type: wayfinder:grilling
Release: 0.3
Blocked by: none
Claimed by: none

## Question

Which reference does Yuka's server render speed compare against, and what is the benchmark (pages, concurrency, machine)? Build the benchmark and record the first numbers.

## Notes

Benchmark built (2026-11-10): `make bench-ssr`, sources and rerun steps in `bench/ssr/README.md`. Same page for each candidate: an HTML document with a list of 100 issues, escaped text, no islands. `wrk -t4 -c32 -d10s`, 3 rounds after 5 s warm-up, median. One process per server. Shared 512-core machine, load average 86 -> 45 during the run.

| candidate | req/s | p50 ms | p99 ms | vs dream-concat |
| --- | ---: | ---: | ---: | ---: |
| dream-concat (floor) | 13696 | 2.29 | 4.32 | 1.00 |
| yuka-page (`Yuka.Server.page`) | 3832 | 8.12 | 15.80 | 0.28 |
| yuka-stream (`Yuka.Server.stream`, as the demo) | 4163 | 7.56 | 14.49 | 0.30 |
| server-reason-react `renderToString` | 6380 | 5.08 | 9.70 | 0.47 |
| React 19 `renderToString`, Node 22 | 3197 | 9.85 | 15.31 | 0.23 |
| Solid 1.9 `renderToString`, Node 22 | 7689 | 4.06 | 8.10 | 0.56 |

A second run (load average 62 -> 43) was within 4% for each candidate. The reference is not chosen: it is a user decision. Yuka renders this page at about half the speed of Solid and of server-reason-react.

## Resolution

Reference decided (user, 2026-11-10): Yuka must be faster than both Solid and server-reason-react. The benchmark is `make bench-ssr` (commit 8ae6986). The speed work is ticket 31.
