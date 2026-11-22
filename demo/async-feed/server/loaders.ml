open Async_feed_shared

let item (_ : Yuka.Server.request) ~id =
  Yuka.Async.return (match Store.find id with Some event -> Ok event | None -> Error Yuka.Server.Not_found)

let zone_char = function 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '/' | '_' | '+' | '-' -> true | _ -> false

let settings request =
  let cookie name = Yuka.Server.Request.cookie request name in
  let zone =
    match Option.map Dream.from_percent_encoded (cookie Zone.cookie) with
    | Some zone when zone <> "" && String.length zone <= 64 && String.for_all zone_char zone -> Some zone
    | _ -> None
  in
  Yuka.Async.return (Ok { Model.theme = Option.bind (cookie Model.theme_cookie) Model.theme_of_string; zone })
