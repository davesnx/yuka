let dialog_open = Yuka.State.make false [@@yuka.shared]
let created : Model.Issue.t option Yuka.State.t = Yuka.State.make None [@@yuka.shared]

let typing e =
  match Yuka.Event.target_tag e with
  | "input" | "textarea" | "select" -> true
  | _ -> false

let navigate : (string -> unit) ref = ref Yuka.Browser.navigate [@@yuka.shared]
