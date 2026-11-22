let%action first =
  Yuka.Action.query ~input:Yuka.Codec.string ~output:Yuka.Codec.string (fun _ filter ->
      Store.after 0.3 (fun () -> "first:" ^ filter))

let%action second =
  Yuka.Action.query ~input:Yuka.Codec.string ~output:Yuka.Codec.string (fun _ filter ->
      Store.after 0.6 (fun () -> "second:" ^ filter))

let%action third =
  Yuka.Action.query ~input:Yuka.Codec.string ~output:Yuka.Codec.string (fun _ filter ->
      Store.after 0.9 (fun () -> "third:" ^ filter))
