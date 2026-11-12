let dialog_open = Yuka.State.make false

let typing event =
  match Yuka.Event.target_tag event with
  | "input" | "textarea" | "select" -> true
  | _ -> false
