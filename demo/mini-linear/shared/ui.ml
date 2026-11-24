let dialog_open = Yuka.State.make false
let dialog_asked = Yuka.State.make false
let overlays = Yuka.State.make 0

let typing event =
  match Yuka.Event.target_tag event with
  | "input" | "textarea" | "select" -> true
  | _ -> false

let shortcut event =
  not
    (typing event || Yuka.State.peek dialog_open
    || Yuka.State.peek overlays > 0
    || Yuka.Event.ctrl_key event || Yuka.Event.meta_key event)
