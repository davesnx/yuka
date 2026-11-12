# Smaller reactive core

Type: wayfinder:task
Release: 0.5
Blocked by: none
Claimed by: none

## Question

Build: a reactive core (signals, memos, effects, owners, batch) with the same public behaviour and a smaller minified size than today's 8.6 KB. All tests pass; record size and keyed benchmark before and after.

## Resolution

Done (2026-11-10). The reactive core is now a graph. A write marks its readers dirty and their readers "check". A read, and the flush, pull a node up to date before it runs. Each node keeps its subscribers in one doubly linked list and its dependencies in read order. A re-run keeps the links it reads in the same order. Effects run parents first, then by level, then the last created first. `src/core.ml` and `src/LICENSE.reativa` are removed; no reativa code remains.

A code review found bugs; these are fixed, each with a test that fails before the fix. Three were old-core bugs too: a memo that raised, and work dropped at the 100-round limit, blocked later updates for good; a raising effect lost dependencies it had not read yet. Also fixed: a child effect ran before the parent that disposes it; an effect disposed during its run, or a memo whose first compute raised, stayed linked; a changed read order cost O(n^2).

Size (`make size`, esbuild `bytesInOutput`, minified):

| | Before | After |
|---|---:|---:|
| reactive core in the keyed app | 8,705 B | 6,007 B |
| `scheduler.js` + `core.js` | 4,402 + 1,805 B | 3,749 B |
| `base.js`, `signal.js`, `state.js` | 1,335, 975, 188 B | 1,298, 772, 188 B |
| keyed app | 33,376 B, 10,997 B gzip | 30,573 B, 10,375 B gzip |
| all demo chunks | 117,077 B, 36,430 B gzip | 114,351 B, 35,826 B gzip |
| core alone (State, owners, Effect, batch and their runtime imports, one ESM bundle) | 11,448 B, 3,712 B gzip | 8,678 B, 3,105 B gzip |

Speed: `bench/keyed/run.ts`, 10 runs per benchmark, run 5 times, medians. Yuka/solid ratio 1.052 before (load average 42 to 124) and 1.073 after (load average 78 to 128). The difference is inside the noise of this machine. A node micro benchmark of the core, run alternately with the old core: a select over 1,000 effects 0.12 to 0.088 ms, 300 memos 0.08 to 0.05 ms, creating and disposing 2,000 effects 0.31 to 0.27 ms, a re-run that reverses 5,000 reads 0.13 ms.

Behaviour change: the first run of an effect is now a batch. Writes in it run the effects they make pending when the run ends, as the `batch` doc says, not at the write.
