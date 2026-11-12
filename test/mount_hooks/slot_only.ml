open Dom

let () =
  let c, dispose = mount (fun () -> Yuka.runtime_slot (Some (Yuka.text "s"))) in
  check "slot mounts its markers" "<!--[$--><!--]-->" (html c);
  dispose ();
  finish "slot hook"
