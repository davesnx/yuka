# Smaller reactive core

Type: wayfinder:task
Release: 0.5
Blocked by: none
Claimed by: none

## Question

Build: a reactive core (signals, memos, effects, owners, batch) with the same public behaviour and a smaller minified size than today's 8.6 KB. All tests pass; record size and keyed benchmark before and after.

## Resolution

Done (2026-11-10). The reactive core is now a Solid-style graph (`src/scheduler.ml`, after `solid-js/src/reactive/signal.ts`). A write marks its readers dirty and their readers "check". A read, and the flush, pull a node up to date before it runs. Each node has one doubly linked list of subscriber links. A re-run keeps the links it reads in the same order. Effects run sorted by level, then the last created first. `src/core.ml` is removed. No reativa code remains, but `src/LICENSE.reativa` and the README credit are still there.

Size (`make size`, esbuild `bytesInOutput`, minified):

| | Before | After |
|---|---:|---:|
| reactive core in the keyed app | 8,705 B | 5,244 B |
| `scheduler.js` + `core.js` | 4,402 + 1,805 B | 3,023 B |
| `base.js`, `signal.js`, `state.js` | 1,335, 975, 188 B | 1,298, 735, 188 B |
| keyed app | 33,376 B, 10,997 B gzip | 29,963 B, 10,174 B gzip |
| all demo chunks | 117,077 B, 36,430 B gzip | 113,741 B, 35,624 B gzip |
| core alone (State, owners, Effect, batch and their runtime imports, one ESM bundle) | 11,448 B, 3,712 B gzip | 8,105 B, 2,913 B gzip |

Speed: `bench/keyed/run.ts`, 10 runs per benchmark, run 5 times, medians, load average 42 to 160. The yuka/solid ratio went from 1.052 to 1.007 (single runs 0.989 to 1.155). This is inside the noise of this machine. A node micro benchmark of the core: a select over 1,000 effects 0.12 to 0.095 ms, 300 memos 0.084 to 0.062 ms, creating and disposing 2,000 effects 0.31 to 0.34 ms.

Behaviour change: the first run of an effect is now a batch. Writes in it run the effects they make pending when the run ends, as the `batch` doc says, not at the write. New tests: lazy memo, diamond, dynamic dependencies, read order change, a pending effect disposed in the same flush, a memo that raises, a batch in the first run.
