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
