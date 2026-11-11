open Dom

let () =
  let c, dispose =
    mount (fun () -> Yuka.lower "p" [ Yuka.attr "class" "c" ] [ Yuka.text "x"; Yuka.lower "b" [] [] ])
  in
  check "lower mounts in a process that only calls lower" {|<p class="c">x<b></b></p>|} (html c);
  dispose ();
  finish "element hook"
