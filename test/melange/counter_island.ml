open Yuka

let view n =
  let c = State.make n in
  lower "div" []
    [
      lower "span" [] [ hole (fun () -> text (string_of_int (State.get c))) ];
      lower "button" [ on "click" (fun _ -> State.update c succ) ] [ text "+" ];
    ]

let entry =
  Client.entry ~name:"LazyCounter" (fun json ->
      Result.map (fun n () -> view n) (Codec.decode Codec.int json))

let island ?loading n =
  Client.island ?loading ~name:"LazyCounter" ~props:(Codec.encode Codec.int n)
    (fun () -> view n)
