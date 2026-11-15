type level = [ `Off | `Hover | `Trajectory | `Visible | `Idle ]

let default : level = `Trajectory
let rank : level -> int = function `Off -> 0 | `Hover -> 1 | `Trajectory -> 2 | `Visible -> 3 | `Idle -> 4

let name : level -> string = function
  | `Off -> "off"
  | `Hover -> "hover"
  | `Trajectory -> "trajectory"
  | `Visible -> "visible"
  | `Idle -> "idle"

let of_name : string -> level option = function
  | "off" -> Some `Off
  | "hover" -> Some `Hover
  | "trajectory" -> Some `Trajectory
  | "visible" -> Some `Visible
  | "idle" -> Some `Idle
  | _ -> None

let trigger value : level =
  match of_name value with
  | Some ((`Hover | `Trajectory | `Visible | `Idle) as t) -> t
  | Some `Off | None -> `Visible
