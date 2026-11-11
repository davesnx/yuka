open Dom

let () =
  let t =
    Yuka.template_coded "\x01p\x02\x01div\x02\x08x\x06\x06" ~html:"<p><div>x</div></p>" ~walk:[||]
      ~kids:[||] ~attrs:[||] ~values:[||] ~clones:1
  in
  let c, dispose = mount (fun () -> Yuka.Private.element (Yuka.Private.expand t [||])) in
  check "the tree from Private.expand mounts" "<p><div>x</div></p>" (html c);
  dispose ();
  finish "element hook through Private.expand"
