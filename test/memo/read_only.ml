let n = Yuka.State.make 1
let double = Yuka.State.memo (fun () -> Yuka.State.get n * 2)
let show (s : (int, _) Yuka.State.signal) = string_of_int (Yuka.State.get s)
let both = show n ^ show double ^ string_of_int (Yuka.State.peek double)
let () = Yuka.State.set n 2
let () = Yuka.State.set double 5
