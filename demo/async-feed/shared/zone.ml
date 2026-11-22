let zones =
  [
    "UTC"; "America/Los_Angeles"; "America/Denver"; "America/Chicago"; "America/New_York"; "America/Sao_Paulo";
    "Europe/London"; "Europe/Madrid"; "Europe/Berlin"; "Europe/Kyiv"; "Africa/Lagos"; "Africa/Nairobi";
    "Asia/Dubai"; "Asia/Kolkata"; "Asia/Singapore"; "Asia/Shanghai"; "Asia/Tokyo"; "Australia/Sydney";
    "Pacific/Auckland";
  ]

let cookie = "async-feed-zone"
let saved : string option Yuka.Context.t = Yuka.Context.make ~name:"zone" ~codec:Yuka.Codec.(option string) ()
let chosen : string option Yuka.State.t = Yuka.State.make None
let saved_zone () = Option.join (Yuka.Context.get saved)

let current saved =
  match (Yuka.State.get chosen, saved) with
  | Some zone, _ -> zone
  | None, Some zone when Env.valid_zone zone -> zone
  | None, _ -> Env.default_zone ()

let choose zone =
  Yuka.State.set chosen (Some zone);
  ignore (Yuka.Browser.set_cookie ~max_age:31536000 cookie zone)
