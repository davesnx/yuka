# CSS per island

Type: wayfinder:grilling
Release: 0.4
Blocked by: none
Claimed by: none

## Question

How does a component or island bring its CSS (file next to the component, scoped class names, ppx), how is it bundled and preloaded with the island, and how does the server print only the CSS a page uses? Build it.

## Notes

Decided (user, 2026-11-10): the recommended option and every recommended answer in `.workplace/docs/app-spec.md`, section 23.

## Resolution

Done (2026-11-10), option B built through A (`.workplace/docs/app-spec.md`, section 23; build changes in "23: changes during build").

- `module Css = [%yuka.css "file.css"]` gives `Css.stylesheet` and one scoped `string` per class (`row_HASH`); a class that the file does not have is a compile error. Each `make` after it calls `Yuka.use_css Css.stylesheet`.
- The server prints `<link rel="stylesheet" data-yuka-css>` once per page, before the first use. The sheets an island uses go before its `<yuka-island>`, after its `modulepreload`. Streamed chunks get their links.
- The browser adds a missing sheet to `<head>`. After a client navigation, new links move to `<head>` with no duplicate.
- `yuka-css` writes the sheets as an OCaml module for `Yuka.Server.config ~css`. The cycle serves them at `/_yuka/css/` with `Immutable`, and a prerender writes them.
- The demo's `Related` island uses it. The e2e checks the style after client navigations and on a full load.

Tests: ppx cram `test/ppx/css.t`; native `css` cases; cycle; prerender (`yuka-dream`); jsdom (`dom_cases`, navigation); e2e 7j. Size: keyed app 10,026 B gzip (no change); demo 43,241 to 43,593 B gzip. `/about` still sends 0 bytes of JavaScript.

Review fixes:
- Links move to `<head>` at navigation start and before each swap.
- A link of an `Await` loading part is printed before the fill region.
- CSS escapes and quoted `url()` are handled, and `@scope` and `@supports selector()` are renamed.
- `use_css` goes only into `make` functions that return an element.
- `/_yuka/css` is decoded and limited to `GET`/`HEAD`, and names are validated.
- `render_html` prints no links.
- `yuka-css` reads the declarations from the sources.

Not built: the sheets of other modules in an island's chunk are not printed with its `modulepreload`, so a part that only the client renders gets its sheet when it renders. No minifying of the sheets.
