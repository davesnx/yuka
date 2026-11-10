let double = Yuka.State.memo (fun () -> 2)
let () = Yuka.State.update double succ
