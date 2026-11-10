# Benchmark suite and Solid baseline

Type: wayfinder:research
Blocked by: none
Claimed by: none

## Question

Which benchmark tells us that Yuka matches Solid? Get the js-framework-benchmark numbers for Solid and vanilla (Chrome 156), decide how Yuka enters that suite (a keyed implementation in the krausest repo layout), and name the reference for SSR throughput.

## Resolution

`make bench-keyed` builds the keyed table app for Yuka, Solid and vanilla JS (`bench/keyed/`) and prints the median time for each operation, the weighted mean and the bundle sizes. First result (2026-11-10, Chrome 151, 5 runs): Yuka/Solid weighted ratio 1.40; app bundle 23.6 KB gzip for Yuka and 5.0 KB for Solid. Not yet built: demo TBT and LCP, SSR throughput, the CI gate.
