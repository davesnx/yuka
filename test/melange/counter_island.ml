open Yuka

let view n =
  let c = State.make n in
  element "div" []
    [
      element "span" [] [ hole (fun () -> text (string_of_int (State.get c))) ];
      element "button" [ on "click" (fun _ -> State.update c succ) ] [ text "+" ];
    ]

let entry =
  runtime_entry ~name:"LazyCounter" (fun json ->
      Result.map (fun n () -> view n) (Codec.decode Codec.int json))

let island ?start n =
  runtime_island ?start ~name:"LazyCounter" ~props:(Codec.encode Codec.int n)
    (fun () -> view n)
