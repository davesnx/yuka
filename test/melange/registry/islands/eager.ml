open Yuka

let%client make ~(initial : int) () =
  let n = State.make initial in
  lower "div" []
    [
      lower "span" [ attr "id" "eager" ] [ hole (fun () -> text (string_of_int (State.get n))) ];
      lower "button" [ attr "id" "eager-add"; on "click" (fun _ -> State.update n succ) ] [ text "+" ];
    ]
