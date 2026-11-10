# Markers only inside islands

Type: wayfinder:task
Blocked by: none
Claimed by: none

## Question

Build: the server prints hydration markers only inside an island. In progress.

## Resolution

Done in commit 5f71133. The page printer prints markers only inside an island. A streamed `Await` outside an island keeps one marker pair for its fill.
