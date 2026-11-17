let counter () =
  let count = Yuka.State.make 0 in
  Yuka.text (string_of_int (Yuka.State.get count))
