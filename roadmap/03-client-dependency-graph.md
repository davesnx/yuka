# What pulls the OCaml stdlib into the client

Type: wayfinder:research
Blocked by: none
Claimed by: none

## Question

For each heavy module in the runtime chunk (camlinternalFormat, Int64, MD5, Hashtbl, Random), which Yuka code pulls it in, and what is the runtime size without it?

## Resolution

Printf and Hashtbl were the large stdlib modules on the client path. The ppx also emitted `Stdlib.Fun.id`, which pulled Printexc and then Printf into each island chunk. All three are gone from the client path.
