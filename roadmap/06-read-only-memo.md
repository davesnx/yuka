# Read-only memo

Type: wayfinder:task
Release: 0.2
Blocked by: none
Claimed by: none

## Question

Build: State.set on a memo is a compile error, through a read-only type.

## Resolution

`State` now has one abstract type with a phantom access parameter, `('a, 'access) State.signal`: `make` returns `'a State.t` (`[ `Write ]`), `memo` and `Async.watch` return `'a State.read` (`[ `Read ]`). `get` and `peek` take `('a, _) signal`, so a function that only reads accepts both with no conversion, while `set` and `update` take `'a State.t`, so a write to a memo is a type error; the run-time `Invalid_argument` and its test in `test/cases/cases.ml` are gone. No call site needed a change. The test is `test/memo`: it compiles files that write a memo and compares the compiler errors with `read_only.expected`; it fails without the change.
