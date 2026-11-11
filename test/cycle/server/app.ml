module Async = Yuka.Async
module Server = Yuka.Server
open Cycle_shared

type req = {
  meth : Yuka.Router.meth;
  target : string;
  headers : (string * string) list;
  body : string;
}

let header req name =
  List.find_map
    (fun (k, v) ->
      if String.lowercase_ascii k = String.lowercase_ascii name then Some v else None)
    req.headers

let events = ref []
let note e = events := e :: !events
let waiting = ref []

let later () =
  let a, resolve, _ = Async.make () in
  waiting := !waiting @ [ (fun () -> resolve (Ok "late")) ];
  a

let slow_state : (string Async.t * (string -> unit) * (string -> unit)) ref =
  ref (Async.make ())

let slow () =
  let a, _, _ = !slow_state in
  a

let finish_slow v =
  let _, resolve, _ = !slow_state in
  resolve v

let second_state : (string Async.t * (string -> unit) * (string -> unit)) ref =
  ref (Async.make ())

let finish_second v =
  let _, resolve, _ = !second_state in
  resolve v

let fail_first = ref false

let reset () =
  fail_first := false;
  events := [];
  waiting := [];
  slow_state := Async.make ();
  second_state := Async.make ()

let el tag ?(attrs = []) children =
  Yuka.lower tag (List.map (fun (k, v) -> Yuka.attr k v) attrs) children

let text = Yuka.text

module Layouts = struct
  let root ~children () =
    el "div" ~attrs:[ ("class", "root") ]
      [
        el "nav"
          [
            el "a" ~attrs:[ ("href", "/plain") ] [ text "plain" ];
            el "a" ~attrs:[ ("href", "/plain?x=1") ] [ text "plain x" ];
            el "a" ~attrs:[ ("href", "/") ] [ text "home" ];
            el "a" ~attrs:[ ("href", "/islands") ] [ text "islands" ];
          ];
        children;
      ]

  let org ~children () = el "section" ~attrs:[ ("class", "org") ] [ children ]

  let team ~squad ~children () =
    el "section" ~attrs:[ ("class", "team") ] [ text ("squad " ^ squad); children ]
end

let jot_form key =
  let open Forms_shared.Entry in
  Yuka.Form.make ~action:jot ~key
    ~children:(fun form ->
      el "div"
        [
          el "input" ~attrs:[ ("name", "body"); ("value", Yuka.Form.value form Body) ] [];
          Yuka.Form.error_view form Body (fun m -> el "p" [ text ("jot " ^ key ^ " error: " ^ m) ]);
        ])
    ()

module Pages = struct
  let team_form ~team:_ ~squad:_ () = Server.page ~title:"Team form" (fun () -> jot_form "team")

  let entry () =
    let open Forms_shared.Entry in
    Server.page ~title:"Entry" (fun () ->
        el "main"
          [
            Yuka.Form.make ~action:save
              ~children:(fun form ->
                el "div"
                  [
                    el "input" ~attrs:[ ("name", "title"); ("value", Yuka.Form.value form Title) ] [];
                    el "input" ~attrs:[ ("name", "count"); ("value", Yuka.Form.value form Count) ] [];
                    Yuka.Form.error_view form Title (fun m -> el "p" [ text ("title error: " ^ m) ]);
                    Yuka.Form.error_view form Count (fun m -> el "p" [ text ("count error: " ^ m) ]);
                    Yuka.Form.form_error_view form (fun m -> el "p" [ text ("form error: " ^ m) ]);
                  ])
              ();
            jot_form "one";
            jot_form "two";
          ])

  let home () =
    Server.page ~title:"Home" (fun () ->
        note "home body";
        text "home")

  let plain () = Server.page ~title:"Plain" (fun () -> el "p" [ text "plain" ])

  let find ~q ~tag () =
    Server.page ~title:"Caf\xc3\xa9 \xe2\x9c\x93" (fun () ->
        text (Option.value q ~default:"-" ^ "|" ^ String.concat "," tag))

  let island name =
    Yuka.Client.island ~name ~props:`Null (fun () ->
        el "button" [ el "a" ~attrs:[ ("href", "/islands") ] [ text name ] ])

  let islands () =
    Server.page ~title:"Islands" (fun () ->
        el "main"
          [ el "p" [ text "before" ];
            Yuka.Catch.make
              ~fallback:(fun ~error ~reset:_ -> text ("lost " ^ error))
              ~children:(fun () ->
                if !fail_first then
                  Yuka.fragment
                    [ island "A"; Yuka.Private.element (Yuka.Private.hole (fun () -> failwith "A")) ]
                else island "A")
              ();
            island "B" ])

  let slow () =
    Server.page ~title:"Slow" (fun () ->
        Yuka.Await.make ~async:(slow ()) ~loading:(text "wait")
          ~failed:(fun _ -> failwith "timeout secret")
          ~children:(fun v -> if v = "explode" then failwith "fill secret" else text v)
          ())

  let twice () =
    let await async =
      Yuka.Await.make ~async ~loading:(text "wait")
        ~failed:(fun _ -> failwith "timeout secret")
        ~children:(fun v -> if v = "explode" then failwith "fill secret" else text v)
        ()
    in
    let first, _, _ = !slow_state and second, _, _ = !second_state in
    Server.page ~title:"Twice" (fun () -> el "main" [ await first; await second ])

  let broken () = Server.page ~title:"Broken" (fun () -> failwith "shell secret")
  let boom ~exploding () = Server.page (fun () -> text exploding)

  let member ~team ~user ~squad ~profile () =
    Server.page ~title:"Member" (fun () ->
        text
          (String.concat " "
             [ Params.Team.to_string team; string_of_int user; squad; profile ]))

  let org_item ~org ~n ~org_item () =
    Server.page (fun () -> text (String.concat " " [ org; string_of_int n; org_item ]))

  let org_missing ~org ~target () =
    Server.page ~title:"Org missing" (fun () -> el "p" [ text ("no org page " ^ target ^ " in " ^ org) ])

  let not_found ~target () =
    Server.page ~title:"Not found" (fun () -> el "p" [ text ("missing " ^ target) ])

  let error ~status () =
    Server.page ~title:"Error" (fun () -> el "p" [ text ("error " ^ string_of_int status) ])
end

module Loaders = struct
  let squad _req ~team =
    note "squad start";
    match Params.Team.to_string team with
    | "wait" -> later ()
    | t -> Async.return (Ok ("of " ^ t))

  let profile req ~team ~user =
    note "profile start";
    match (Params.Team.to_string team, user) with
    | "wait", _ -> later ()
    | _, 404 -> Async.return (Error Server.Not_found)
    | _, 500 -> Async.failed "loader secret"
    | _ -> Async.return (Ok (Option.value (header req "x-user") ~default:"anonymous"))

  let org_item _req ~org:_ ~n =
    Async.return (if n = 404 then Error Server.Not_found else Ok "item")

  let exploding _req : (string, Server.stop) result Async.t = failwith "loader secret"
end

module Guards = struct
  let outer _req ~team =
    note "outer";
    Async.return
      (match Params.Team.to_string team with
      | "nobody" -> Error Server.Not_found
      | "away" -> Error (Server.Redirect { status = 303; location = "/" })
      | "okay" -> Error (Server.Redirect { status = 200; location = "/" })
      | "crlf" -> Error (Server.Redirect { status = 302; location = "/a\r\nset-cookie: x=1" })
      | _ -> Ok ())

  let inner _req ~team:_ ~user =
    note "inner";
    Async.return (if user = 0 then Error (Server.Fail "guard secret") else Ok ())
end

module Api = struct
  let team req ~team =
    note "team json";
    if Params.Team.to_string team = "gone" then Server.text ~status:404 "gone" else
    Server.json
      (`Assoc
        [
          ("team", `String (Params.Team.to_string team));
          ("user", `String (Option.value (header req "x-user") ~default:"anonymous"));
        ])

  let rename _req ~team:_ =
    note "rename";
    Server.text "renamed"

  let feed _req =
    Server.text
      ~headers:[ ("Cache-Control", "no-cache"); ("X-Frame-Options", "SAMEORIGIN") ]
      "feed"

  let later _req =
    Async.bind (slow ()) (fun v ->
        if v = "explode" then Async.failed "handler secret" else Server.text v)

  let clear _req = Server.text "cleared"
  let asset _req = Server.text "asset"
end

let saved = ref []

let () =
  let open Forms_shared.Entry in
  Server.Form.implement save
    ~redirect:(fun o ->
      if String.exists (fun c -> c = ':' || c < ' ' || c = '\127') o || String.starts_with ~prefix:"/" o then o
      else "/entry?saved=" ^ o)
    (fun e ->
      saved := e.title :: !saved;
      match e.title with
      | "taken" -> Async.return (Error [ (Some Title, "Taken") ])
      | "nope" -> Server.Action.reject "Refused"
      | "boom" -> failwith "secret boom"
      | t -> Async.return (Ok t));
  Server.Form.implement jot (fun n ->
      saved := ("jot " ^ n.body) :: !saved;
      if n.body = "x" then Async.return (Error [ (Some Body, "Too short") ])
      else Async.return (Ok (String.length n.body)))
