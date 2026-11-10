# Only .mlx files

Type: wayfinder:task
Release: 0.2
Blocked by: none
Claimed by: none

## Question

Build: components and islands are written in .mlx; the generator scans only .mlx.

## Resolution

`yuka-islands` now scans only `.mlx` files, and the ppx rejects `let%client` in any file that is not `.mlx` (`.ml`, `.re`, ...) with "let%client is allowed only in .mlx files: rename a.ml to a.mlx", so an island can no longer compile and then be missing from the registry. The four test islands in `test/melange/registry/islands/` moved to `.mlx` and JSX; the other `.ml` files in `demo/`, `bench/` and `test/` hold no JSX or island. Tests: `test/ppx/errors.t` ("let%client in a .ml file", and a `.re` file name) and `gen/test/islands.t` ("Only .mlx files are scanned"); both fail without the change.
