# Error boundaries and loading states on the client

Type: wayfinder:grilling
Release: 0.3
Blocked by: none
Claimed by: none

## Question

What does a client error boundary catch (render, effect, event handler, async), how does it show and reset a fallback, and how do loading states compose with `Await` and `Remote` status? Build it.

## Notes

Decided (user, 2026-11-10): the recommended option and every recommended answer in `.workplace/docs/app-spec.md`, section 21.

## Resolution

Built (option A with `Show`, every recommended answer).

- `<Yuka.Catch fallback=(fun ~error ~reset -> ...)>` catches exceptions in
  the children's render, effects (body and re-run cleanup), memos read by
  them, holes and rows that run again, and event handlers. The fallback
  replaces the children; `reset` renders them again from their first
  state. An error in the fallback goes to the boundary above.
- An island with no `Catch` stops at its first exception, keeps its DOM,
  and logs `yuka island ID (NAME): message` to `console.error` and to
  `Yuka.mount ~on_error`. Other islands keep working.
- Server: an exception in the children prints the fallback with
  `"server error"` in a `<!--[!-->` hole; the detail goes to
  `Server.log_error`. The client hydrates the fallback.
- `<Yuka.Show status loading failed>` shows a `Status.t`; `Yuka.Status`
  is added (type, `data`, `error_to_string`).
- Failed `Async` and `Status.Failed` stay data.
- Size: +177 B gzip on the keyed benchmark against main b8c02c8 (the routing in the core).
- Deviations: `.workplace/docs/app-spec.md`, "21: changes during build".
