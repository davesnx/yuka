let el tag ?(attrs = []) children =
  Yuka.element tag (List.map (fun (k, v) -> Yuka.attr k v) attrs) children

let link href = el "a" ~attrs:[ ("href", href) ] [ Yuka.text href ]
let root ~children () = el "div" ~attrs:[ ("class", "root") ] [ children ]

let home () =
  Yuka.Server.page ~title:"Home" (fun () ->
      el "main"
        [
          link "/post/hello";
          link "/post/missing";
          link "/secret";
          link "https://example.com/away";
          link "//example.com/away";
          link "/post/hello";
          link "/docs#top";
          link "/static/s.css";
          link "/_yuka/app.js";
          link "/guide";
          link "/a%2Fb";
        ])

let docs () = Yuka.Server.page ~title:"Docs" (fun () -> el "p" [ Yuka.text "docs" ])

let post (_ : Dream.request) ~slug =
  Yuka.Async.return
    (match slug with "hello" | "world" -> Ok slug | _ -> Error Yuka.Server.Not_found)

let post_page ~slug ~post () =
  Yuka.Server.page ~title:slug (fun () ->
      el "article" [ Yuka.text ("post " ^ post); link "/post/world"; link "/" ])

let page ~parts () =
  Yuka.Server.page (fun () -> el "p" [ Yuka.text ("page " ^ String.concat "/" parts) ])

let secret () = Yuka.Server.page (fun () -> Yuka.text "secret")
let not_found ~path () = Yuka.Server.page ~title:"Missing" (fun () -> Yuka.text ("missing " ^ path))
let feed (_ : Dream.request) = Yuka.Server.text ~headers:[ ("content-type", "application/rss+xml") ] "<rss/>"
