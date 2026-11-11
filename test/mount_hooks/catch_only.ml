open Dom

let () =
  let c, dispose =
    mount (fun () ->
        Yuka.Catch.make
          ~fallback:(fun ~error ~reset:_ -> Yuka.text ("failed: " ^ error))
          ~children:(fun () -> Yuka.text "fine")
          ())
  in
  check "Catch mounts its children" "<!--[-->fine<!--]-->" (html c);
  dispose ();
  finish "catch hook"
