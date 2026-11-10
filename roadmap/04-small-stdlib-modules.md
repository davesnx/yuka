# Small stdlib modules

Type: wayfinder:task
Blocked by: none
Claimed by: none

## Question

Build small implementations of Printf/Format, Int64, MD5, Hashtbl and Random for Melange, as a package that also works outside Yuka. One agent per module.

## Resolution

The small modules are a separate project, `davesnx/melange-tiny` (Printf, Hashtbl, Random, Digest; exact stdlib signatures and behaviour). Yuka uses `melange-tiny.printf` and `melange-tiny.hashtbl`. `Yuka.format` is removed from the API (user, 2026-11-10). Open: Yuka's four `sprintf` calls on the client path cost about 4 KB gzip; ticket 14 decides if they stay.
