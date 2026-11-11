# Live data across more than one server node

Type: wayfinder:grilling
Release: 0.4
Blocked by: 13
Claimed by: none

## Question

How do topic updates reach subscribers on other server nodes (Postgres LISTEN/NOTIFY, Redis, a pluggable bus), and what does the adapter need? Build it.

## Notes

Decided (user, 2026-11-10): the recommended option and every recommended answer in `.workplace/docs/app-spec.md`, section 25.

## Resolution

Done (2026-11-11): option B (`.workplace/docs/app-spec.md` section 25; build changes in "25: changes during build"; the settle rule in `.workplace/docs/data-spec.md` section 8, "More nodes").

- `Server.Live.instance`: each node has its own entries, sockets and `seq`.
- `use_bus ~node bus` with the record `{ send; listen; on_restart }`. A publish sends `{"n","t","k","p"}`. A node with subscribers for the key loads it again, one load at a time; notes during a load make one more load. `on_restart` loads every subscribed key again.
- `Server.Live.changed`; `Server.Live.memory_bus` for tests.
- Settle rule: the action answer carries `"live":[NODE,P]`, and `Live.mutate` sends `sync` with it as `after`. The socket's node holds `synced` until it has heard note `P` of that node and loaded the key again (at most 5 s).
- `revoke` stays per node; the docs say to call it on every node.
- New package `yuka-live-pg` on postgresql-ocaml: LISTEN/NOTIFY, an Lwt wait on the socket, reconnect with `on_restart`. Tested against Postgres 17 in docker over a unix socket.
- The demo runs a second node in one process (`--second-node`, `--bus memory|pg:...`). The e2e opens a page on each node and passes with the memory bus and with Postgres.

Not done: two demo processes, which need a shared store, not the in-memory one. CI does not run the Postgres tests yet: they skip without `YUKA_LIVE_PG`, so a CI job with a Postgres service and that variable is needed.
