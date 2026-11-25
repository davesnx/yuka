open Async_feed_shared

let item (_ : Yuka.Server.request) ~id =
  Yuka.Async.return (match Store.find id with Some event -> Ok event | None -> Error Yuka.Server.Not_found)

type embed_data = { event : Model.event; theme : Model.theme option }

let embed request ~id =
  let theme =
    match Yuka.Server.Request.cookie request Model.theme_cookie with Some t -> Model.theme_of_string t | None -> None
  in
  Yuka.Async.return
    (match Store.find id with Some event -> Ok { event; theme } | None -> Error Yuka.Server.Not_found)

let zone_char = function 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '/' | '_' | '+' | '-' -> true | _ -> false

let settings request =
  let cookie name = Yuka.Server.Request.cookie request name in
  let zone =
    match match cookie Zone.cookie with Some z -> Yuka.Url.decode_uri_component z | None -> None with
    | Some zone when zone <> "" && String.length zone <= 64 && String.for_all zone_char zone -> Some zone
    | _ -> None
  in
  let theme = match cookie Model.theme_cookie with Some t -> Model.theme_of_string t | None -> None in
  Yuka.Async.return (Ok { Model.theme; zone })
