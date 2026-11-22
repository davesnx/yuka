let zones =
  [
    "UTC"; "America/Los_Angeles"; "America/Denver"; "America/Chicago"; "America/New_York"; "America/Sao_Paulo";
    "Europe/London"; "Europe/Madrid"; "Europe/Berlin"; "Europe/Kyiv"; "Africa/Lagos"; "Africa/Nairobi";
    "Asia/Dubai"; "Asia/Kolkata"; "Asia/Singapore"; "Asia/Shanghai"; "Asia/Tokyo"; "Australia/Sydney";
    "Pacific/Auckland";
  ]

let zone : (unit -> string) ref = ref (fun () -> "UTC")
let set_zone : (string -> unit) ref = ref (fun _ -> ())
let to_time : (string -> int) ref = ref (fun _ -> 0)
let theme : (unit -> string) ref = ref (fun () -> "light")
let set_theme : (string -> unit) ref = ref (fun _ -> ())
