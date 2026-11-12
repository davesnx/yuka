open Dom

let () =
  check_urls "Private.template, cloned" (fun tag name value ->
      Yuka.runtime_instance (Yuka.Private.template Yuka.Private.Template.(element tag [ fixed name value ] [])) [||]);
  List.iter
    (fun (tag, name, value, expected) ->
      let t =
        Yuka.Private.template Yuka.Private.Template.(element "p" [] [ element "div" [] [ element tag [ fixed name value ] [] ] ])
      in
      let c, dispose = mount (fun () -> Yuka.runtime_instance t [||]) in
      check
        ("Private.template, built node by node: " ^ tag ^ " " ^ name ^ "=" ^ String.escaped value)
        ("<p><div>" ^ expected ^ "</div></p>")
        (html c);
      dispose ())
    url_cases;
  finish "URL check through Private.template"
