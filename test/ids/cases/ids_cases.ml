open Yuka

let seen : string list ref = ref []
let take_seen () =
  let l = List.rev !seen in
  seen := [];
  l

let doomed = ref true

let field label =
  with_id (fun id ->
      seen := id :: !seen;
      element "p" []
        [
          element "label" [ attr "for" id ] [ text label ];
          element "input" [ attr "id" id; attr "aria-describedby" (id ^ "-hint") ] [];
          element "small" [ attr "id" (id ^ "-hint") ] [ text label ];
        ])

let form_view (async : string Async.t) =
  let rows = State.make [| "r1"; "r2" |] in
  element "div" []
    [
      field "one";
      field "two";
      Await.make ~async ~loading:(field "wait")
        ~children:(fun v -> element "section" [] [ field v; field (v ^ "2") ])
        ();
      each ~key:Fun.id (fun () -> State.get rows) (fun k -> field k);
      Catch.make
        ~fallback:(fun ~error:_ ~reset:_ -> field "fallback")
        ~children:(fun () ->
          fragment [ field "doomed"; hole (fun () -> if !doomed then failwith "boom" else empty) ])
        ();
      field "last";
      element "button" [ on "click" (fun _ -> State.set rows [| "r1"; "r2"; "r3" |]) ] [ text "add" ];
    ]

let slot_view slot = element "div" [] [ field "before"; runtime_slot slot; field "after" ]

let form_island async = runtime_island ~name:"Form" ~props:`Null (fun () -> form_view async)

let slot_island () =
  runtime_island ~name:"Slotted" ~props:`Null (fun () -> slot_view (Some (field "slotted")))

let page async = element "main" [] [ field "page"; form_island async; slot_island (); form_island async ]
let answer async = element "div" [] [ field "nav"; form_island async ]
