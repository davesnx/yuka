let el tag ?(attrs = []) children =
  Yuka.element tag (List.map (fun (k, v) -> Yuka.attr k v) attrs) children

let link href = el "a" ~attrs:[ ("href", href) ] [ Yuka.text href ]
let root ~children () = el "div" ~attrs:[ ("class", "root") ] [ children ]

let home () =
  Yuka.Server.page ~title:"Home" (fun () -> el "main" [ link "/post/hello"; link "/docs" ])

let docs () = Yuka.Server.page ~title:"Docs" (fun () -> el "p" [ Yuka.text "docs" ])

let post (_ : Tapak.Request.t) ~slug =
  Yuka.Async.return
    (match slug with "hello" | "world" -> Ok slug | _ -> Error Yuka.Server.Not_found)

let post_page ~slug ~post () =
  Yuka.Server.page ~title:slug (fun () ->
      el "article" [ Yuka.text ("post " ^ post); link "/post/world"; link "/" ])

let page ~parts () =
  Yuka.Server.page (fun () -> el "p" [ Yuka.text ("page " ^ String.concat "/" parts) ])

let secret () = Yuka.Server.page (fun () -> Yuka.text "secret")

let warned () =
  Yuka.Server.page (fun () ->
      Yuka.Console.warn "warned page";
      Yuka.text "warned")

let slow () =
  Yuka.Server.page ~title:"Slow" (fun () ->
      let data =
        Yuka_tapak.async ~sw:(Yuka_tapak.switch ()) (fun () ->
            Eio_unix.sleep 0.05;
            "slow data")
      in
      el "main"
        [
          Yuka.text "before";
          Yuka.suspend ~loading:(Yuka.text "loading") (Yuka.Async.map (fun s -> el "p" [ Yuka.text s ]) data);
        ])

let stuck () =
  Yuka.Server.page ~title:"Stuck" (fun () ->
      let never, _, _ = Yuka.Async.make () in
      Yuka.suspend ~loading:(Yuka.text "loading") ~failed:(fun m -> Yuka.text ("failed " ^ m)) never)

let lingering () =
  Yuka.Server.page (fun () ->
      ignore (Yuka_tapak.async ~sw:(Yuka_tapak.switch ()) (fun () -> Eio_unix.sleep 5.));
      Yuka.text "answered")

let not_found ~path () = Yuka.Server.page ~title:"Missing" (fun () -> Yuka.text ("missing " ^ path))

let feed (_ : Tapak.Request.t) =
  Yuka.Server.text ~headers:[ ("content-type", "application/rss+xml") ] "<rss/>"
