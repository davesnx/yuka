open Dom

let () =
  let c, dispose =
    mount (fun () -> Yuka.element "p" [ Yuka.attr "class" "c" ] [ Yuka.text "x"; Yuka.element "b" [] [] ])
  in
  check "element mounts in a process that only calls element" {|<p class="c">x<b></b></p>|} (html c);
  dispose ();
  finish "element hook"
