open Dom

let () =
  let t =
    Yuka.Private.Template.make
      Yuka.Private.Template.(element "p" [] [ element "div" [] [ text "x" ] ])
      ~html:"<p><div>x</div></p>" ~walk:[||] ~kids:[||] ~attrs:[||] ~values:[||]
  in
  let c, dispose = mount (fun () -> Yuka.runtime_instance t [||]) in
  check "a Private.Template.make template that the parser changes is built node by node"
    "<p><div>x</div></p>" (html c);
  dispose ();
  finish "element hook through Private.Template.make"
