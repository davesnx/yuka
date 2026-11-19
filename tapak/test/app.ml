let el tag ?(attrs = []) children =
  Yuka.element tag (List.map (fun (k, v) -> Yuka.attr k v) attrs) children

let link href = el "a" ~attrs:[ ("href", href) ] [ Yuka.text href ]
let root ~children () = el "div" ~attrs:[ ("class", "root") ] [ children ]

let home () =
  Yuka.Server.page ~title:"Home" (fun () -> el "main" [ link "/post/hello"; link "/docs" ])

let docs () = Yuka.Server.page ~title:"Docs" (fun () -> el "p" [ Yuka.text "docs" ])

let post (_ : Yuka.Server.request) ~slug =
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
        Yuka_tapak.async ~sw:(Yuka_tapak.switch_exn ()) (fun () ->
            Eio_unix.sleep 0.05;
            "slow data")
      in
      el "main"
        [
          Yuka.text "before";
          Yuka.Await.make ~async:data ~loading:(Yuka.text "loading") ~children:(fun s -> el "p" [ Yuka.text s ]) ();
        ])

let stuck () =
  Yuka.Server.page ~title:"Stuck" (fun () ->
      let never, _, _ = Yuka.Async.make () in
      Yuka.Await.make ~async:never ~loading:(Yuka.text "loading") ~failed:(fun m -> Yuka.text ("failed " ^ m)) ~children:Fun.id ())

let lingering () =
  Yuka.Server.page (fun () ->
      ignore (Yuka_tapak.async ~sw:(Yuka_tapak.switch_exn ()) (fun () -> Eio_unix.sleep 5.));
      Yuka.text "answered")

let not_found ~path () = Yuka.Server.page ~title:"Missing" (fun () -> Yuka.text ("missing " ^ path))

let feed (_ : Yuka.Server.request) =
  Yuka.Server.text ~headers:[ ("content-type", "application/rss+xml") ] "<rss/>"

let sum req =
  Yuka.Async.bind (Yuka.Server.Request.json req Yuka.Codec.(list int)) (function
    | Error _ -> Yuka.Server.text ~status:400 "bad body"
    | Ok numbers ->
        Yuka.Server.json ~status:201
          Yuka.Codec.(list string)
          [
            string_of_int (List.fold_left ( + ) 0 numbers);
            Option.value (Yuka.Server.Request.query_param req "tag") ~default:"-";
            Option.value (Yuka.Server.Request.cookie req "theme") ~default:"-";
          ])

let whoami req =
  match Yuka_tapak.request req with
  | None -> Yuka.Server.text "no tapak request"
  | Some r ->
      Yuka.Server.text (Tapak.Request.target r ^ " " ^ Option.value (Tapak.Request.header "x-user" r) ~default:"-")
