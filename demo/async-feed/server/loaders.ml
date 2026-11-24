open Async_feed_shared

let item (_ : Yuka.Server.request) ~id =
  Yuka.Async.return (match Store.find id with Some event -> Ok event | None -> Error Yuka.Server.Not_found)

type embed_data = { event : Model.event; theme : Model.theme option }

let embed request ~id =
  let theme = Option.bind (Yuka.Server.Request.cookie request Model.theme_cookie) Model.theme_of_string in
  Yuka.Async.return
    (match Store.find id with Some event -> Ok { event; theme } | None -> Error Yuka.Server.Not_found)

let zone_char = function 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '/' | '_' | '+' | '-' -> true | _ -> false

let settings request =
  let cookie name = Yuka.Server.Request.cookie request name in
  let zone =
    match Option.bind (cookie Zone.cookie) Yuka.Url.decode_uri_component with
    | Some zone when zone <> "" && String.length zone <= 64 && String.for_all zone_char zone -> Some zone
    | _ -> None
  in
  Yuka.Async.return (Ok { Model.theme = Option.bind (cookie Model.theme_cookie) Model.theme_of_string; zone })
