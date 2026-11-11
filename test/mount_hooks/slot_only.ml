open Dom

let () =
  let c, dispose = mount (fun () -> Yuka.slot (Yuka.Slot.make (Yuka.text "s"))) in
  check "slot mounts its markers" "<!--[$--><!--]-->" (html c);
  dispose ();
  finish "slot hook"
