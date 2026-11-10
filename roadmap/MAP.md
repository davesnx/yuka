# Yuka v1: as good as SolidJS, in OCaml

Label: wayfinder:map. Tickets are the numbered files in this folder. A ticket is open until it has a `## Resolution`. Blocking is the "Blocked by" line of each ticket.

## Destination

Yuka v1 is tagged when it matches SolidJS on measured numbers and has the features below, built and checked:

- Updates: js-framework-benchmark keyed, weighted mean within 5% of Solid.
- Size: client runtime min+gzip at or below Solid's (5 KB measured; Yuka's keyed app is 11 KB, ticket 14).
- A page with no island sends 0 bytes of JavaScript.
- Demo: Total Blocking Time 0 and LCP equal to plain server HTML.
- Server: SSR throughput faster than both Solid and server-reason-react on `make bench-ssr` (user, 2026-11-10; ticket 31).
- Features: generated router from `Routes.mlx`, first-party Dream adapter with Yuka owning the request cycle, three kinds of data (local, remote, live), and the areas listed in "Not yet specified".

## Releases before v1

- 0.2 (plan: `.workplace/plans/yuka-0.2_PLAN.md`, local): tickets 05, 06, 07, 09, 11, 16, 17, 18, 19. `yuka-dream` is a separate opam package.
- 0.3, apps: 10 (navigation), 12 (remote data), 20 (forms), 21 (error boundaries), 22 (prefetch, cache, view transitions), 26 (page measurements), 27 (SSR throughput), 28 (benchmark CI gate).
- 0.4, platform: 13 (live data), 25 (live data on many nodes), 23 (CSS per island), 24 (dev server).
- 0.5, speed and size: 29 (smaller reactive core), 30 (mount path), 31 (SSR faster than Solid and server-reason-react), with the 1.05 speed target confirmed by 28.
- 1.0: every target in "Destination" met and measured.
- A ticket's `Release:` line names its release.

## Notes

- This map carries execution, not only decisions (user, 2026-11-09): a ticket is done when its decision is made and built.
- The hard case is a very interactive app (the mini Linear demo). Content sites must stay good.
- Public API can change freely until 1.x.
- Order: easy and unblocking work first. Measurement before optimisation.
- Skills: grilling and domain-modeling for decisions; mlx-syntax for `.mlx`; melange-advanced for generated JS.
- Baseline facts and interview answers: `.workplace/plans/yuka-solid_ANSWERS.md` (local). Silica's design for remote and live data: /home/me/workplace/davesnx/silica, `.workplace/plans/silica-v1/012`, `016`, `017`.
- No v1 tag before the destination is reached. 0.x releases come before it (user, 2026-11-10).

## Decisions so far

- Route format: one `Routes.mlx` route tree, in the style of server-reason-react router-gen. Not file-system routes.
- Nitro (nitro.build) is the model for the server layer, not for the page router: route rules as props on route nodes, method nodes, a generated matcher, a fixed request order, prerender. See tickets 09 and 11.
- Yuka does not depend on melange-tiny: the client uses a JS `Map` and no `sprintf`.
- Server: Dream only for now, as a first-party adapter; Yuka owns routes, data loading, actions, assets and headers on top of it.
- Data kinds: signal functions that return a `Status` value; no shared client cache at first (as silica chose).
- Client stdlib: replace Printf/Format, Int64, MD5, Hashtbl and Random on the client path with small implementations, usable outside Yuka.
- Resumability: research first, then decide.

## Not yet specified

All earlier items now have tickets (20 to 25, 28). Each grilling ticket gets its design from the user before it is built.

## Out of scope

- Servers other than Dream.
- `let%action`.
