# Unsafe URLs and raw-text elements

Type: wayfinder:task
Release: 0.5
Blocked by: 31
Claimed by: none

## Question

Build: (1) URL attributes (href, src, action, formaction, xlink:href and the like) with a `javascript:` (or other script-capable) scheme are not printed as given on the server or set on the client; decide the rule (refuse, replace with a safe value, and log in dev) in the style of other frameworks, and document it. (2) Text inside `<script>` and `<style>` in templates and elements is printed as raw text with only the closing-tag sequence made safe, not HTML-escaped, so inline JS and CSS work and `</script>` still cannot break out. Found by the ticket 31 review; both predate ticket 31.

## Resolution

Done (2026-11-10).

- URL attributes with a `javascript:`, `vbscript:` or non-image `data:` URL, after the browser's own clean-up (case, leading spaces and control characters, tabs and newlines anywhere), are printed by the server and set by the client as `about:blank#blocked` (React's rule, with `vbscript:` and `data:` as Angular checks; no escape hatch, as React). `Yuka.attr` and `Yuka.hole_attr` check URL attributes; the printer checks every attribute it prints, template ones included; a literal unsafe URL in `.mlx` is a build error. The ppx uses unchecked constructors for other attributes, so the keyed app has no URL check (10,034 B gzip, budget 10,040).
- `<script>` and `<style>` text is printed raw, with `</script`, `</style` (any case) and `<!--` in a script made safe (`<\`); the ppx never compiles them into templates. The bench and demo goldens did not change: no page there has script or style text.
- Tests: `test/safety` (normalisation tricks, every URL attribute, printer paths, mlx parts and holes, raw text), `test/melange/dom_cases.ml` (client holes and attributes), `test/ppx` (literal refused, checked constructors only for URL attributes, script and style as `Yuka.lower`).
