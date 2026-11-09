# Yuka v1: as good as SolidJS, in OCaml

Label: wayfinder:map. Tickets are the numbered files in this folder. A ticket is open until it has a `## Resolution`. Blocking is the "Blocked by" line of each ticket.

## Destination

Yuka v1 is tagged when it matches SolidJS on measured numbers and has the features below, built and checked:

- Updates: js-framework-benchmark keyed, weighted mean within 5% of Solid.
- Size: client runtime min+gzip at or below Solid's (5 KB measured; Yuka is 31 KB today).
- A page with no island sends 0 bytes of JavaScript.
- Demo: Total Blocking Time 0 and LCP equal to plain server HTML.
- Server: SSR throughput compared with an agreed reference.
- Features: generated router from `Routes.mlx`, first-party Dream adapter with Yuka owning the request cycle, three kinds of data (local, remote, live), and the areas listed in "Not yet specified".

## Notes

- This map carries execution, not only decisions (user, 2026-11-09): a ticket is done when its decision is made and built.
- The hard case is a very interactive app (the mini Linear demo). Content sites must stay good.
- Public API can change freely until 1.x.
- Order: easy and unblocking work first. Measurement before optimisation.
- Skills: grilling and domain-modeling for decisions; mlx-syntax for `.mlx`; melange-advanced for generated JS.
- Baseline facts and interview answers: `.workplace/plans/yuka-solid_ANSWERS.md` (local). Silica's design for remote and live data: /home/me/workplace/davesnx/silica, `.workplace/plans/silica-v1/012`, `016`, `017`.
- No tag and no release before the destination is reached.

## Decisions so far

- Route format: one `Routes.mlx` route tree, in the style of server-reason-react router-gen. Not file-system routes.
- Server: Dream only for now, as a first-party adapter; Yuka owns routes, data loading, actions, assets and headers on top of it.
- Data kinds: signal functions that return a `Status` value; no shared client cache at first (as silica chose).
- Client stdlib: replace Printf/Format, Int64, MD5, Hashtbl and Random on the client path with small implementations, usable outside Yuka.
- Resumability: research first, then decide.

## Not yet specified

- Forms and mutations with progressive enhancement: waits for the remote data design.
- Prefetch on hover or when visible, navigation cache, view transitions: wait for the navigation protocol.
- CSS per island or scoped styles.
- Dev server with hot reload.
- Error boundaries and loading states on the client.
- Benchmarks and size budget as CI gates: wait for the benchmark suite.
- Live data on more than one server node.

## Out of scope

- Servers other than Dream.
- `let%action`.
