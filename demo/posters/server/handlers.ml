open Posters_shared

let poster_svg req =
  let defaults = Pages.today () in
  let settings =
    match Routes.find `GET [] (Yuka.Server.Request.query req) with
    | Yuka.Router.Found route -> Link.settings ~defaults route
    | _ -> defaults
  in
  Yuka.Server.response
    ~headers:[ ("content-type", "image/svg+xml; charset=utf-8") ]
    (String (Yuka.Server.to_string (fun () -> Poster.still settings)))
