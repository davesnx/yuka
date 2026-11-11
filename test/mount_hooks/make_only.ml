open Dom

let () =
  let t =
    Yuka.Template.make
      Yuka.Template.(element "p" [] [ element "div" [] [ text "x" ] ])
      ~html:"<p><div>x</div></p>" ~walk:[||] ~kids:[||] ~attrs:[||] ~values:[||]
  in
  let c, dispose = mount (fun () -> Yuka.Template.instance t [||]) in
  check "a Template.make template that the parser changes is built node by node"
    "<p><div>x</div></p>" (html c);
  dispose ();
  finish "element hook through Template.make"
