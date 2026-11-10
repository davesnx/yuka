# Prerender at build time

Type: wayfinder:task
Release: 0.2
Blocked by: 09, 11
Claimed by: none

## Question

Build: a build step writes HTML files for exact routes and for pages found by following links from them. Links that leave the app are not followed.

## Resolution

Done (2026-11-10), in `yuka-dream` (increment 3 of `.workplace/docs/routes-spec.md`, section 3.6). `Yuka_dream.prerender ~out config app` (the demo: `demo_server.exe --prerender DIR`) renders each `GET` node with no param and `prerender=true` through the request cycle, follows the links of each HTML page to other `prerender=true` pages, and writes `index.html`-style files, `404.html`, and the client and public files. Links to another origin are not followed; a page that does not answer 2xx is skipped with a warning. `Yuka.Server.config ~prerendered:DIR` serves the files. Tests: `dream/test/run.ml`.
