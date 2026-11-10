# SSR faster than Solid and server-reason-react

Type: wayfinder:task
Release: 0.5
Blocked by: 27
Claimed by: none

## Question

Build: on `make bench-ssr` (100-row issue list, one process, wrk -c32), Yuka serves more requests per second than both Solid on Node and server-reason-react. First numbers (ticket 27): Yuka streamed 4,163, server-reason-react 6,380, Solid 7,689 req/s.
