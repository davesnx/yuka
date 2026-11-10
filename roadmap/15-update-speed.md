# Update speed work

Type: wayfinder:grilling
Blocked by: 02, 08
Claimed by: none

## Question

From the benchmark and the gap report, which changes to the scheduler, effects and templates are needed to come within 5% of Solid?

## Resolution

Done for this round (2026-11-10): owners without hash tables, delegated handlers without effects, ppx-compiled templates, no markers for an only-child hole or list or a one-element row, one-call removal of a row or a list, identity equality by default, `Yuka.batch`. The Yuka/Solid weighted ratio on `make bench-keyed` went from 1.40 to between 1.03 and 1.08. These runs had a machine load average of 50 to 160, so the number is not final: measure again on a quiet machine before the target (1.05) is called reached. Script time on create is still 1.7 to 2 times Solid's (closure calls through `Curry`, about 13 `Web` calls per row).
