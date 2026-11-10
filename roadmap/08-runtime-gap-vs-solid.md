# Runtime gap against Solid

Type: wayfinder:research
Blocked by: none
Claimed by: none

## Question

What does Solid's compiler and runtime do that Yuka's ppx and client do not (templates, delegation, effect cost per row), and what would resumability gain over lazy islands?

## Resolution

Causes, in order of cost: (1) stdlib modules in the bundle; (2) an owner with a hash table for each effect, and a sort on dispose; each event handler is an effect; (3) templates built at run time and 4 comment nodes for each row; (4) structural equality by default and no `batch`; (5) one runtime chunk for all features. Ticket 15 does 2 to 4, ticket 14 does 1 and 5. Resumability: out for v1. Islands already limit the JavaScript that runs on load, and resumability needs a serialised reactive graph, which is a different runtime.
