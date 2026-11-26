open Posters_shared

let poster_svg _req ~kind ~seed ~padding ~lines ~amplitude ~waves ~stroke ~direction ~blocks ~gap ~filled ~squareness ~radius ~clouds ~puffs ~size ~bolts ~branches ~jaggedness ~thickness ~length ~style ~columns ~rows ~half ~empty ~block ~bar ~merge ~round ~accent ~tint ~bg ~fg ~title ~subtitle ~year ~day ~weekday =
  let settings =
    Link.settings ~defaults:(Pages.today ())
      (Routes.Home
         { kind; seed; padding; lines; amplitude; waves; stroke; direction; blocks; gap; filled; squareness; radius; clouds; puffs; size; bolts; branches; jaggedness; thickness; length; style; columns; rows; half; empty; block; bar; merge; round; accent; tint; bg; fg; title; subtitle; year; day; weekday })
  in
  Yuka.Server.response
    ~headers:[ ("content-type", "image/svg+xml; charset=utf-8") ]
    (String (Yuka.Server.to_string (fun () -> Poster.still settings)))
