type t = Form_core.upload

let make limits : t =
  { limits; files = (fun _ -> invalid_arg "Yuka: browser only"); send = (fun _ _ _ _ _ -> invalid_arg "Yuka: browser only") }
