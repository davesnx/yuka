# Mount path an app pays only for what it uses

Type: wayfinder:task
Release: 0.5
Blocked by: 29
Claimed by: none

## Question

Build: a render-only app does not carry hydration and slot code, and the `Curry`, `List`, `Array` and option helpers leave the client path, so the keyed app reaches Solid's size (5 KB gzip).
