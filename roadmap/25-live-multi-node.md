# Live data across more than one server node

Type: wayfinder:grilling
Release: 0.4
Blocked by: 13
Claimed by: none

## Question

How do topic updates reach subscribers on other server nodes (Postgres LISTEN/NOTIFY, Redis, a pluggable bus), and what does the adapter need? Build it.

## Notes

Decided (user, 2026-11-10): the recommended option and every recommended answer in `.workplace/docs/app-spec.md`, section 25.
