# Remote data

Type: wayfinder:grilling
Release: 0.3
Blocked by: none
Claimed by: none

## Question

What is the API for remote data on signals: endpoint declaration against existing actions, the Status value, answers embedded by the server, retry, and Optimistic?

## Resolution

Done (2026-11-10), increments R1 to R3 of `.workplace/docs/data-spec.md` (sections 1 and 2). A query is `Action.query` (a phantom kind on `Action.t`, same endpoint and wire format as actions). `Remote.use` gives a `Status.t` signal; it aborts on a new key, retries `Network` and `Server` errors, and is `Idle` when not `enabled`. A server render writes each answer after its island as `<script data-yuka-answer>` (pending answers are streamed), so hydration sends no request. `Remote.invalidate` refetches the mounted uses of a query; `Remote.mutate` with `Optimistic` shows a change at once and rolls it back on failure. The demo issue list reads `Queries.issues` and changes status and priority through `mutate`. A bundle that does not use `Remote` contains none of it (`make size` checks the keyed app). Changes from the spec are in its "Changes during build" section. Tests: `test/remote`, `test/melange/remote_cases.ml`, `e2e/demo.ts` 3e.
