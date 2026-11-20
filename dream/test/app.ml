let el tag ?(attrs = []) children =
  Yuka.element tag (List.map (fun (k, v) -> Yuka.attr k v) attrs) children

let link href = el "a" ~attrs:[ ("href", href) ] [ Yuka.text href ]
let root ~children () = el "div" ~attrs:[ ("class", "root") ] [ children ]

let home () =
  Yuka.Server.page ~title:"Home" (fun () ->
      el "main"
        [
          link (Yuka.Router.url "/post/hello");
          link (Yuka.Router.url "/post/missing");
          link (Yuka.Router.url "/secret");
          link "https://example.com/away";
          link "//example.com/away";
          link (Yuka.Router.url "/post/hello");
          link (Yuka.Router.url "/docs#top");
          link (Yuka.Router.url "/static/s.css");
          link (Yuka.Router.url "/_yuka/app.js");
          link (Yuka.Router.url "/guide");
          link (Yuka.Router.url "/a%2Fb");
        ])

let docs () = Yuka.Server.page ~title:"Docs" (fun () -> el "p" [ Yuka.text "docs" ])

let post (_ : Yuka.Server.request) ~slug =
  Yuka.Async.return
    (match slug with "hello" | "world" -> Ok slug | _ -> Error Yuka.Server.Not_found)

let post_page ~slug ~post () =
  Yuka.Server.page ~title:slug (fun () ->
      el "article" [ Yuka.text ("post " ^ post); link (Yuka.Router.url "/post/world"); link (Yuka.Router.url "/") ])

let page ~parts () =
  Yuka.Server.page (fun () -> el "p" [ Yuka.text ("page " ^ String.concat "/" parts) ])

let secret () = Yuka.Server.page (fun () -> Yuka.text "secret")

let warned () =
  Yuka.Server.page (fun () ->
      Yuka.Console.warn "warned page";
      Yuka.text "warned")
let not_found ~path () = Yuka.Server.page ~title:"Missing" (fun () -> Yuka.text ("missing " ^ path))
let feed (_ : Yuka.Server.request) = Yuka.Server.text ~headers:[ ("content-type", "application/rss+xml") ] "<rss/>"

let whoami req =
  match Yuka_dream.request req with
  | None -> Yuka.Server.text "no Dream request"
  | Some dream -> Yuka.Server.text (Dream.target dream ^ " " ^ Option.value (Dream.header dream "x-user") ~default:"-")

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
