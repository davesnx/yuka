let double = Yuka.State.memo (fun _ -> 2)
let () = Yuka.State.update double succ
