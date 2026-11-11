open Dom

let () =
  let run path make =
    List.iter
      (fun (tag, name, value, expected) ->
        let s = Yuka.State.make "/start" in
        let c, dispose =
          mount (fun () ->
              Yuka.template_instance (one_part tag)
                [| Yuka.template_attribute (make tag name (fun () -> Some (Yuka.State.get s))) |])
        in
        Yuka.State.set s value;
        check (path ^ ": " ^ tag ^ " " ^ name ^ "=" ^ String.escaped value) expected (html c);
        dispose ())
      url_cases
  in
  run "Yuka.hole_attr" (fun _ name f -> Yuka.hole_attr name f);
  run "Yuka.url_hole_attr" (fun tag name f -> Yuka.url_hole_attr tag name f);
  finish "URL check through hole_attr"
