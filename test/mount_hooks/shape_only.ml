open Dom

let () =
  let t = Yuka.Private.template Yuka.Private.Template.(element "p" [] [ element "div" [] [ text "x" ] ]) in
  let c, dispose = mount (fun () -> Yuka.runtime_instance t [||]) in
  check "a hand-written template that the parser changes is built node by node"
    "<p><div>x</div></p>" (html c);
  dispose ();
  finish "element hook through Private.template"
