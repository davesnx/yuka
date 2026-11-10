# Forms with progressive enhancement

Type: wayfinder:grilling
Release: 0.3
Blocked by: 12
Claimed by: none

## Question

What is the API for a form that posts to an action without JavaScript and, with an island, submits through `Action.call` with pending state, validation errors and optimistic update? Build it.

## Notes

Decided (user, 2026-11-10): the recommended option and every recommended answer in `.workplace/docs/app-spec.md`, section 20.

## Resolution

Done (2026-11-10), app-spec section 20, option B. `[@@deriving form]` writes a field type and one decoder for both targets; `Yuka.Form.action` is a typed action; `Yuka.Server.Form.implement` serves it; `<Yuka.Form>` prints a `<form method="post">` that posts to the page URL with a hidden `_yuka_action` field. The request cycle has a form-post step: same-origin check, 303 on success, 422 with the sent values and errors on a decode error, `Error` or `reject`. Inside an island the same form submits through `Action.call` with `Form.pending` and field errors, and follows the redirect or calls `~on_ok`. The demo's `/new` page works with JavaScript off, and the new issue dialog uses the same form in an island. Changes during build are in app-spec "20: changes during build". Tests: `test/forms`, `test/cycle` (forms), `test/ppx`, `test/melange/form_cases.ml`, `demo/test`, `e2e/demo.ts` 6f.
