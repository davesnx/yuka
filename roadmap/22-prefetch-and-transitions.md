# Prefetch, navigation cache and view transitions

Type: wayfinder:grilling
Release: 0.3
Blocked by: 10
Claimed by: none

## Question

Prefetch on hover or when a link is visible, a navigation cache with an expiry, and the View Transitions API for client navigation: API, defaults and size cost. Build it.

## Notes

Decided (user, 2026-11-10): the recommended option and every recommended answer in `.workplace/docs/app-spec.md`, section 22.

## Resolution

Built (option A, every recommended answer).

- `Yuka.mount ?prefetch:[ `Hover | `Visible | `Off ]` (default `` `Hover ``)
  and `?transitions:bool` (default false). Per link:
  `data-yuka-prefetch="visible"` or `"off"` (the ppx writes `data_*` as
  `data-*`).
- Prefetch after 50 ms of hover or focus, at once on pointer down, on
  visibility; `Yuka-Prefetch: 1` reaches loaders through the request.
- Navigation cache by URL and outlet keys, lifetime from the answer's
  `Cache-Control`; a `no-store` prefetch is used once within 10 s; at most
  30 entries; a successful action call empties it.
- View transitions with `data-yuka-nav` on `<html>` (the demo turns them
  on); the CSS-only cross-document rule is documented in the README for
  pages with no island.
- Size: keyed benchmark unchanged (10637 to 10635 B gzip); demo client +1381 B gzip.
- Deviations: `.workplace/docs/app-spec.md`, "22: changes during build".
