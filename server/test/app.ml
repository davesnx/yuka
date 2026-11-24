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
      let data = Yuka_server.to_async (Lwt.map (fun () -> "slow data") (Lwt_unix.sleep 0.05)) in
      el "main"
        [
          Yuka.text "before";
          Yuka.Await.make ~async:data ~blocking:`No ~loading:(Yuka.text "loading") ~children:(fun s -> el "p" [ Yuka.text s ]) ();
        ])

let stuck () =
  Yuka.Server.page ~title:"Stuck" (fun () ->
      let never, _, _ = Yuka.Async.make () in
      Yuka.Await.make ~async:never ~loading:(Yuka.text "loading") ~failed:(fun m -> Yuka.text ("failed " ^ m)) ~children:Fun.id ())

let gate = ref (Yuka.Async.return ())

let gated () =
  Yuka.Server.page ~title:"Gated" (fun () ->
      el "main"
        [
          Yuka.text "before";
          Yuka.Await.make ~async:!gate ~loading:(Yuka.text "loading") ~children:(fun () -> el "p" [ Yuka.text "gated data" ]) ();
        ])

let not_found ~path () = Yuka.Server.page ~title:"Missing" (fun () -> Yuka.text ("missing " ^ path))

let feed (_ : Yuka.Server.request) =
  Yuka.Server.text ~headers:[ ("content-type", "application/rss+xml") ] "<rss/>"

let whoami req =
  match Yuka_server.request req with
  | None -> Yuka.Server.text "no ache request"
  | Some reqd ->
      let r = Ache.Request_descriptor.request reqd in
      Yuka.Server.text (r.target ^ " " ^ Option.value (Ache.Headers.get r.headers "x-user") ~default:"-")

let session req = Yuka.Server.text (Option.value (Yuka.Server.Request.session req) ~default:"none")

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

let patched req = Yuka.Server.text (match Yuka.Server.Request.meth req with `PATCH -> "patched" | _ -> "not a PATCH")
let client_left = ref (Yuka.Async.return ())
let second_write = ref None

let ticks (_ : Yuka.Server.request) =
  Yuka.Server.response
    (Yuka.Server.Stream
       (fun write ->
         Yuka.Async.bind (write "first") (fun () ->
             Yuka.Async.bind !client_left (fun () ->
                 let written = write "second" in
                 Yuka.Async.on_result written (fun r -> second_write := Some r);
                 Yuka.Async.return ()))))

let flood_result = ref None

let flood (_ : Yuka.Server.request) =
  let chunk = String.make 65536 'f' in
  Yuka.Server.response
    (Yuka.Server.Stream
       (fun write ->
         let finished, finish, _ = Yuka.Async.make () in
         let rec loop () =
           Yuka.Async.on_result (write chunk) (function
             | Ok () -> loop ()
             | Error m ->
                 flood_result := Some m;
                 finish ())
         in
         loop ();
         finished))

let framing req =
  let text = "hello" in
  let stream status headers = Yuka.Server.response ~status ~headers (Yuka.Server.Stream (fun write -> write text)) in
  let string status headers = Yuka.Server.response ~status ~headers (Yuka.Server.String text) in
  match Option.value (Yuka.Server.Request.query_param req "case") ~default:"" with
  | "length" -> string 200 [ ("content-length", "3") ]
  | "chunked-string" -> string 200 [ ("transfer-encoding", "chunked") ]
  | "stream-te" -> stream 200 [ ("transfer-encoding", "gzip") ]
  | "stream-length" -> stream 200 [ ("content-length", "99") ]
  | "204" -> string 204 [ ("content-length", "5") ]
  | "304" -> string 304 []
  | "204-stream" -> stream 204 []
  | "304-stream" -> stream 304 []
  | "status-99" -> string 99 []
  | "status-1000" -> string 1000 []
  | "bad-name" -> string 200 [ ("bad name", "x") ]
  | "fail" -> Yuka.Server.response (Yuka.Server.Stream (fun write -> Yuka.Async.bind (write "a") (fun () -> Yuka.Async.failed "producer broke")))
  | "raise" -> Yuka.Server.response (Yuka.Server.Stream (fun _ -> failwith "producer raised"))
  | _ -> string 400 []
