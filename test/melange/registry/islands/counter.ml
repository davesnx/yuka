open Yuka

let%client make ~(id : string) ~(initial : int) () =
  let n = State.make initial in
  lower "div" []
    [
      lower "span" [ attr "id" id ] [ hole (fun () -> text (string_of_int (State.get n))) ];
      lower "button" [ attr "id" (id ^ "-add"); on "click" (fun _ -> State.update n succ) ] [ text "+" ];
    ]
