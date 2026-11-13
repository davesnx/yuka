type t = Dark | Light | Gray | Pale

let all = [ Dark; Light; Gray; Pale ]
let slug = function Dark -> "dark" | Light -> "light" | Gray -> "gray" | Pale -> "pale"
let label = function Dark -> "Dark" | Light -> "Light" | Gray -> "Gray" | Pale -> "Pale"
let of_slug text = Option.value (List.find_opt (fun theme -> slug theme = text) all) ~default:Dark
let read : (unit -> string) ref = ref (fun () -> "dark")
let write : (string -> unit) ref = ref ignore
let current () = of_slug (!read ())
let apply theme = !write (slug theme)
