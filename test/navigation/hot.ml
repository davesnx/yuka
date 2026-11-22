open Yuka

let island label codec initial next show =
  runtime_entry ~name:"Hot" (fun json ->
      Result.map
        (fun (_ : int) () ->
          let count = State.make initial |> Dev.keep codec in
          let plain = State.make 0 in
          let draft = State.make "" |> Dev.keep Codec.string in
          hole (fun () ->
              let c = State.get count and p = State.get plain and d = State.get draft in
              element "button"
                [ Yuka.attr "id" "hb";
                  on "click" (fun _ ->
                      batch (fun () ->
                          State.set count (next c);
                          State.set plain (p + 1);
                          State.set draft (d ^ "x"))) ]
                [ text (String.concat " " [ label; show c; string_of_int p; d ]) ]))
        (Codec.decode Codec.int json))
