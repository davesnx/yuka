# Live data diffs for large states

Type: wayfinder:grilling
Release: later
Blocked by: 13
Claimed by: none

## Question

A live state is sent in full on every publish. Measured (ticket 13, bench/live/publish.ml): 500 issues are 122 KB per message and 14 ms to publish to 100 sockets; 5,000 issues are 1.2 MB, over the 1 MiB message limit. Which diff format (JSON patch, keyed list diff, or a per-topic delta function) and which protocol change (data-spec section 3.4) keep large topics under the limit? Build it.
