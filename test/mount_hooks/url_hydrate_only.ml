open Dom

let () =
  List.iter
    (fun (tag, name, value, expected) ->
      let c = container () in
      let t =
        Yuka.template_coded (fixed_code tag name value) ~html:"" ~walk:[||] ~kids:[||] ~attrs:[||] ~values:[||]
          ~clones:1
      in
      match Yuka.Client.hydrate (as_container c) (fun () -> Yuka.template_instance t [||]) with
      | dispose ->
          check ("hydrate: " ^ tag ^ " " ^ name ^ "=" ^ String.escaped value) expected (html c);
          dispose ()
      | exception e ->
          incr failures;
          print_endline ("FAIL hydrate raised " ^ Printexc.to_string e))
    url_cases;
  finish "URL check through hydrate"
