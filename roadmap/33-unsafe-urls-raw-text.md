# Unsafe URLs and raw-text elements

Type: wayfinder:task
Release: 0.5
Blocked by: 31
Claimed by: none

## Question

Build: (1) URL attributes (href, src, action, formaction, xlink:href and the like) with a `javascript:` (or other script-capable) scheme are not printed as given on the server or set on the client; decide the rule (refuse, replace with a safe value, and log in dev) in the style of other frameworks, and document it. (2) Text inside `<script>` and `<style>` in templates and elements is printed as raw text with only the closing-tag sequence made safe, not HTML-escaped, so inline JS and CSS work and `</script>` still cannot break out. Found by the ticket 31 review; both predate ticket 31.

## Resolution

Done (2026-11-10), with the fixes of four security reviews.

- URL attributes (any case; also `values`, `to`, `from`, `by` of SVG animations) with a `javascript:` or `vbscript:` URL, or a `data:` URL where it opens or loads a document, after the browser's own clean-up, are printed by the server and set by the client as `about:blank#blocked` (React's rule, no escape hatch). `data:` images and media stay. The server printer checks every attribute with its element; in the browser, the client checks each value where it sets the attribute, with the element; the ppx's unchecked constructors refuse URL names; a literal unsafe URL in `.mlx` is a build error. A `srcdoc` of `iframe` or `href` of `base` that is not a literal in `.mlx` becomes `""`. Tag names must be a letter followed by letters, digits and `-`; attribute names that start with `on` are refused (handlers are functions); `Template.make` is for the ppx only. `data:` is also blocked on `script` `src` and `href`. `values`, `to`, `from`, `by` are URLs only on SVG animation elements Bad attribute names (empty, space, control character, quote, `<`, `>`, `/`, `=`) are refused everywhere. `Yuka.template_of_shape` checks the fixed attributes of a hand-written template. `Yuka.Browser.navigate` ignores `javascript:`, `vbscript:` and `data:` URLs, and a form follows only a `redirect` on this site (server 500 and log; client form error).
- `<script>` and `<style>` take one text. In HTML it is printed raw with every `</` and (JavaScript) `<!--` made safe (`\u003c` for every `<` in non-JavaScript scripts); in `svg`, `math` and `select` it is escaped. The namespace is tracked as the HTML parser does (`svg > foreignObject` is HTML, everything under `math` is treated as MathML), with tags in any case, the same way on the server and the client. The ppx joins texts into one and refuses other children; the printer and the client raise on them.
- Keyed app: 10,898 B gzip (+228 B for the client guards, +42 B for the second review, 0 for the third, +595 B for the URL check at the client sink in the fourth; budget raised to that). The bench and demo goldens did not change.
- Tests: `test/safety`, `test/melange/dom_cases.ml` and `form_cases.ml`, `test/navigation`, `test/cycle`, `test/ppx` (errors and rewrite).
