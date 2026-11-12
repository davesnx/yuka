let dialog_open = Yuka.State.make false

let typing e =
  match Yuka.Event.target_tag e with
  | "input" | "textarea" | "select" -> true
  | _ -> false
