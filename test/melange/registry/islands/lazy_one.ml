open Yuka

let%client[@yuka.lazy] make ~(initial : int) () =
  let n = State.make initial in
  lower "div" []
    [
      lower "span" [ attr "id" "lazy" ] [ hole (fun () -> text (string_of_int (State.get n))) ];
      lower "button" [ attr "id" "lazy-add"; on "click" (fun _ -> State.update n succ) ] [ text "+" ];
    ]
