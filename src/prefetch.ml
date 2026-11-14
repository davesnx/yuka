type level = [ `Off | `Hover | `Visible ]

let default : level = `Hover
let rank : level -> int = function `Off -> 0 | `Hover -> 1 | `Visible -> 2
let name : level -> string = function `Off -> "off" | `Hover -> "hover" | `Visible -> "visible"

let of_name : string -> level option = function
  | "off" -> Some `Off
  | "hover" -> Some `Hover
  | "visible" -> Some `Visible
  | _ -> None

let trigger value : level =
  match of_name value with Some ((`Hover | `Visible) as t) -> t | Some `Off | None -> `Visible
