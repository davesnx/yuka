type t = Dark | Light | Gray | Pale

let all = [ Dark; Light; Gray; Pale ]
let slug = function Dark -> "dark" | Light -> "light" | Gray -> "gray" | Pale -> "pale"
let label = function Dark -> "Dark" | Light -> "Light" | Gray -> "Gray" | Pale -> "Pale"
let of_slug text = Option.value (List.find_opt (fun theme -> slug theme = text) all) ~default:Dark
let attribute = "data-theme"
let storage_key = "yuka-demo-theme"

module Code = struct
  type t = Dark_plus | One_dark | Nord | Tokyo_night | Gruvbox | Light_plus

  let all = [ Dark_plus; One_dark; Nord; Tokyo_night; Gruvbox; Light_plus ]

  let slug = function
    | Dark_plus -> "dark"
    | One_dark -> "one-dark"
    | Nord -> "nord"
    | Tokyo_night -> "tokyonight"
    | Gruvbox -> "gruvbox"
    | Light_plus -> "light"

  let label = function
    | Dark_plus -> "Dark+"
    | One_dark -> "One Dark"
    | Nord -> "Nord"
    | Tokyo_night -> "Tokyo Night"
    | Gruvbox -> "Gruvbox"
    | Light_plus -> "Light+"

  let of_slug text = List.find_opt (fun code -> slug code = text) all
  let auto = function Dark -> Dark_plus | Light -> Light_plus | Gray -> One_dark | Pale -> Light_plus
  let attribute = "data-code-theme"
  let storage_key = "yuka-demo-code-theme"
end

let read : (string -> string) ref = ref (fun _ -> "")
let write : (string -> string -> string -> unit) ref = ref (fun _ _ _ -> ())
let current () = of_slug (!read attribute)
let apply theme = !write attribute storage_key (slug theme)
let current_code () = Code.of_slug (!read Code.attribute)
let apply_code code = !write Code.attribute Code.storage_key (match code with Some code -> Code.slug code | None -> "")
