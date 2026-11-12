open Dom

let () =
  List.iter
    (fun (name, value, expected) ->
      let c, dispose =
        mount (fun () -> Yuka.element "svg" [] [ Yuka.element "animate" [ Yuka.runtime_attr name value ] [] ])
      in
      check ("element animate " ^ name ^ "=" ^ value) ("<svg><animate " ^ expected ^ "></animate></svg>") (html c);
      dispose ())
    [ ("to", "javascript:alert(1)", {|to="about:blank#blocked"|});
      ("values", "/a;javascript:alert(1)", {|values="about:blank#blocked"|});
      ("from", "/a", {|from="/a"|}) ];
  finish "URL check through element"
