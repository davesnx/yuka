# Unsafe URLs and raw-text elements

Type: wayfinder:task
Release: 0.5
Blocked by: 31
Claimed by: none

## Question

Build: (1) URL attributes (href, src, action, formaction, xlink:href and the like) with a `javascript:` (or other script-capable) scheme are not printed as given on the server or set on the client; decide the rule (refuse, replace with a safe value, and log in dev) in the style of other frameworks, and document it. (2) Text inside `<script>` and `<style>` in templates and elements is printed as raw text with only the closing-tag sequence made safe, not HTML-escaped, so inline JS and CSS work and `</script>` still cannot break out. Found by the ticket 31 review; both predate ticket 31.
