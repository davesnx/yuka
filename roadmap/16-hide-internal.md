# Hide Internal

Type: wayfinder:task
Release: 0.2
Blocked by: none
Claimed by: none

## Question

Build: the public `yuka.mli` has no `Internal` module. Tests and the benchmark reach the same functions through a library that users do not see.

## Resolution

Done (2026-11-10), in a different form than asked: `Yuka.Internal` is now `Yuka.Private`, between two `(**/**)` stop comments in `src/yuka.mli`, so the docs do not show it. Only tests and `bench/bench.ml` use it. Five public doc comments that named `Internal` now describe the behaviour instead.

A first build made `Internal` unreachable (code moved to `src/full.ml(i)`, `yuka.mli` as `Full` without `Internal`). Type errors then named the hidden module, `(int, [ `Read ]) Yuka__Full.State.signal` and not `Yuka.State.signal` (found by `test/memo`). The user chose the hidden-from-docs form (2026-11-10).
