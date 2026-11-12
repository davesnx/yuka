# Keep what the user did before hydration

Type: wayfinder:grilling
Release: 1.0
Blocked by: none
Claimed by: none

## Question

A user can type in an input, tick a checkbox or choose an option before the JavaScript of the island loads. Hydration then loses it. `dom/js/client.ml` (`mount_attr`, `Dynamic`) mounts a reactive attribute as an effect that sets it, so `value=(State.get draft)` sets `el.value` to the first value of the State. A static `value` is not touched, because hydration skips static attributes of an element it adopts.

Decide and build: when hydration adopts a form control that the user changed, the DOM value wins and the State learns it. The user's direction (2026-11-12): fire the DOM changes again after hydration.

Open points:

- How to detect a change: `value` against `defaultValue`, `checked` against `defaultChecked`, `selected` against `defaultSelected`, for `input`, `textarea` and `select`.
- How the State learns it: dispatch `input` and `change` on the element after its handlers are attached, so `on_input` runs as it does for a real event. An element with a reactive `value` and no handler has no State to update; decide whether the DOM value stays or the State wins.
- Events other than form input that happen before hydration (a click on a button of an island that starts on `Visible` or `Interaction`): replay them or not. Lazy islands already start on interaction; check what they do with the event that started them.
- Focus and the cursor position must stay where they are.
- Cost in bytes against the budget of `make size`.

Checks: a jsdom case in `test/melange/dom_cases.ml` (type, then hydrate, the text and the State both hold the typed value), and an e2e step with a slow script.

## Resolution

Done (2026-11-12). Design: DESIGN.md, "Input made before hydration".

- Changed: hydration compares an adopted `input` or `textarea` with what the server printed: `checked` with `defaultChecked` for a checkbox or radio, else `value` with `defaultValue` (for a `textarea` that is its text). A `select` is changed when the selected options differ from those of a fresh copy (`cloneNode`): a copy does not keep the user's choice, and the browser applies its own default rules (no `selected` option, `multiple`, `size`). An `option` counts as changed when its `select` is.
- On a changed control, the first run of a reactive `value`, `checked` or `selected` reads the State but does not write the DOM; later runs write as before. Focus, cursor and selection do not move, because nothing writes the control.
- When the hydration batch has ended (handlers attached, effects run), Yuka dispatches `input` and then `change` (bubbling) on each changed control, in document order. The handlers write the State as for a real event. A control with handlers but no reactive `value` gets the same events. A control with a reactive `value` and no handler keeps the DOM value until its State changes. A radio that the user unchecked keeps its state but gets no event, as in the browser.
- An island that starts later (`Idle`, `Visible`, `Interaction`, `Lazy`) records events once its script runs. A control that has recorded `input` or `change` events gets no dispatch at hydration; the replay sends them, so each handler runs once per event.
- Not done: clicks and other events made before the script runs are not replayed. An untouched control and a client-only render behave as before.
- Size (`make size`, gzip): the keyed benchmark app does not change (7,962 B; it never hydrates). A one-island page: +343 B (counter), +358 B (Codec props), +364 B (Remote); demo start +363 B. For the counter page: detection and the skipped first write +248 B, the dispatch +65 B (the case "handlers and no reactive `value`" costs nothing more), no double events with recorded events +30 B.
- Demo: `/before-hydration`; the demo server sends `main.js` 3 s late to that page only.
- Tests: `test/melange/dom_cases.ml` (`hydrate keeps what the user changed and the State learns it`, `hydrate fires only the checked radio`), e2e step `3i`. Both jsdom cases fail on the code before this change (`input keeps what the user typed: expected "typed by hand", got "server"`; `the radio the user checked stays checked: expected "false,true", got "true,false"`).
