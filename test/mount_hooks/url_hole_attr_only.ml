open Dom

let () =
  let run path make =
    List.iter
      (fun (tag, name, value, expected) ->
        let s = Yuka.State.make "/start" in
        let c, dispose =
          mount (fun () ->
              Yuka.runtime_instance (one_part tag)
                [| Yuka.runtime_attribute (make tag name (fun () -> Some (Yuka.State.get s))) |])
        in
        Yuka.State.set s value;
        check (path ^ ": " ^ tag ^ " " ^ name ^ "=" ^ String.escaped value) expected (html c);
        dispose ())
      url_cases
  in
  run "Yuka.hole_attr" (fun _ name f -> Yuka.hole_attr name f);
  run "Yuka.runtime_url_hole_attr" (fun tag name f -> Yuka.runtime_url_hole_attr tag name f);
  finish "URL check through hole_attr"
