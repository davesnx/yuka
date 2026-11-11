open Dom

let () =
  check_urls "template_of_shape, cloned" (fun tag name value ->
      Yuka.Template.instance (Yuka.template_of_shape Yuka.Template.(element tag [ fixed name value ] [])) [||]);
  List.iter
    (fun (tag, name, value, expected) ->
      let t =
        Yuka.template_of_shape Yuka.Template.(element "p" [] [ element "div" [] [ element tag [ fixed name value ] [] ] ])
      in
      let c, dispose = mount (fun () -> Yuka.Template.instance t [||]) in
      check
        ("template_of_shape, built node by node: " ^ tag ^ " " ^ name ^ "=" ^ String.escaped value)
        ("<p><div>" ^ expected ^ "</div></p>")
        (html c);
      dispose ())
    url_cases;
  finish "URL check through template_of_shape"
