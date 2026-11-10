# Hydration mismatch log

Type: wayfinder:task
Release: 0.2
Blocked by: none
Claimed by: none

## Question

Build: in development, the client logs when the server HTML does not match.

## Resolution

Hydration now logs one `console.warn` per mismatch (missing node, other tag, other text, extra node) with the island name, the expected and found node, and a short path; the checks are in `src/client.ml`, the message code in the new virtual module `Dev` (`dom/js/dev.ml`). The app's bundler decides: `--define:__YUKA_DEV__=false` turns `Dev.on` and `Dev.mismatch` into constants that esbuild inlines, so the message code is not in the bundle; a dune-profile flag was dropped because an opam install always builds yuka in release. The cost is 42 B (17 B gzip) on the keyed app, from leftovers of the inlined checks; `make size` fails if a bundle contains the message. Tests: "dom hydration mismatch log" in `test/melange/dom_cases.ml`, the `make size` check, and e2e check 11b.
