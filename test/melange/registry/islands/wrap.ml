open Yuka

let%client make ~(id : string) ~(children : Yuka.slot) () =
  let n = State.make 0 in
  lower "section" []
    [
      lower "span" [ attr "id" id ] [ hole (fun () -> text (string_of_int (State.get n))) ];
      lower "button" [ attr "id" (id ^ "-add"); on "click" (fun _ -> State.update n succ) ] [ text "+" ];
      slot children;
    ]
