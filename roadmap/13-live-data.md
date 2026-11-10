# Live data

Type: wayfinder:grilling
Release: 0.4
Blocked by: 11, 12
Claimed by: none

## Question

What is the Live API and protocol: topics, WebSocket or SSE, reconnect, sessions and CSRF, and what the Dream adapter must provide?

## Resolution

Done (2026-11-10), increments L1 to L3 of `.workplace/docs/data-spec.md` (section 3), with two rules corrected before the build (app-spec section 25):

- `Live.mutate` settles on an explicit mark in the socket order: on `Ok` the client sends `sync`, and the server answers `synced` behind the latest state of the subscription. The first rule (settle on the first state after the HTTP answer) waited for an unrelated later publish when the published state arrived before the answer.
- Sessions and the secret must be shared by every node and survive a restart (`Dream.cookie_sessions` with `Dream.set_secret`); with `Dream.memory_sessions` every reconnect after a restart is refused with 4403. The demo uses cookie sessions, and e2e step 8c restarts the server: with `memory_sessions` its check 8c.4 fails.

A topic is `Topic.declare ~name ~key ~state`. The server serves it (`Server.Live.serve`) and publishes full states (`Server.Live.publish`). One WebSocket per page (`GET /_yuka/live`, served by `Yuka_dream.handler`) carries every subscription with protocol v1 (`hello` with a CSRF token, `sub`, `unsub`, `sync`, `ping`; `state` with a sequence number, `error`, `synced`, `pong`). The client reconnects with backoff and gets the full state again; the status is `Ready { stale = true }` meanwhile. The handshake uses the origin rule of the action call. A server render writes the state and the token in the page, so a page with no live use asks no token and sends no live code; the keyed app is unchanged (10,027 B gzip) and `make size` checks that it has no live module and no `WebSocket`.

Demo: the issue list (`/`, `/my`) and the properties panel are live; the label chips above the list read the query `Queries.labels` (remote data). Tests: `test/live` (protocol, coalescing, limits, sync, handshake, server render), `test/melange/live_cases.ml` (client: one socket, seq, backoff, stale, close codes, offline, heartbeat, mutate settle), `demo/test` (embedded state, publish from `update_issue`), `e2e/demo.ts` 3g (two pages, forced 500, closed socket, foreign origin) and 8c (server restart).

Measured (`bench/live`): 500 issues are 122 KB per message (publish to 100 sockets: 14 ms); 5000 issues are 1.2 MB, over the 1 MiB limit of the spec, so a patch ticket is due (not opened here). Changes from the spec are in its section 8. Not built: more than one server node (ticket 25).
