open Dom

let num : int Yuka.Context.t = Yuka.Context.make ()

let () =
  let c, dispose =
    mount (fun () ->
        Yuka.Context.provide num 3 (fun () ->
            Yuka.text (match Yuka.Context.get num with Some n -> string_of_int n | None -> "none")))
  in
  check "Context.provide mounts its children with the value" "<!--[-->3<!--]-->" (html c);
  dispose ();
  finish "context hook"
