let el tag ?(attrs = []) children =
  Yuka.element tag (List.map (fun (k, v) -> Yuka.attr k v) attrs) children

let link href = el "a" ~attrs:[ ("href", href) ] [ Yuka.text href ]

let home () =
  Yuka.Server.page ~title:"Home" (fun () ->
      el "main" [ el "h1" [ Yuka.text "Yuka on tapak" ]; link "/slow"; link "/hello.json"; link "/api/time" ])

let slow () =
  Yuka.Server.page ~title:"Slow" (fun () ->
      let data =
        Yuka_tapak.async ~sw:(Yuka_tapak.switch ()) (fun () ->
            Eio_unix.sleep 1.;
            "loaded after one second")
      in
      el "main"
        [
          el "h1" [ Yuka.text "Slow" ];
          Yuka.suspend ~loading:(Yuka.text "loading...") (Yuka.Async.map (fun s -> el "p" [ Yuka.text s ]) data);
        ])

let hello (_ : Tapak.Request.t) = Yuka.Server.json (`Assoc [ ("from", `String "yuka endpoint") ])
let not_found ~path () = Yuka.Server.page ~title:"Missing" (fun () -> Yuka.text ("missing " ^ path))
