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

module Pages = struct
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
                    [ island "A"; Yuka.Private.element (Yuka.Private.Hole (fun () -> failwith "A")) ]
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
    | t -> Async.resolved (Ok ("of " ^ t))

  let profile req ~team ~user =
    note "profile start";
    if header req "yuka-prefetch" = Some "1" then note "prefetch";
    match (Params.Team.to_string team, user) with
    | "wait", _ -> later ()
    | _, 404 -> Async.resolved (Error Server.Not_found)
    | _, 500 -> Async.failed "loader secret"
    | _ -> Async.resolved (Ok (Option.value (header req "x-user") ~default:"anonymous"))

  let org_item _req ~org:_ ~n =
    Async.resolved (if n = 404 then Error Server.Not_found else Ok "item")

  let exploding _req : (string, Server.stop) result Async.t = failwith "loader secret"
end

module Guards = struct
  let outer _req ~team =
    note "outer";
    Async.resolved
      (match Params.Team.to_string team with
      | "nobody" -> Error Server.Not_found
      | "away" -> Error (Server.Redirect { status = 303; location = "/" })
      | "okay" -> Error (Server.Redirect { status = 200; location = "/" })
      | "crlf" -> Error (Server.Redirect { status = 302; location = "/a\r\nset-cookie: x=1" })
      | _ -> Ok ())

  let inner _req ~team:_ ~user =
    note "inner";
    Async.resolved (if user = 0 then Error (Server.Fail "guard secret") else Ok ())
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
