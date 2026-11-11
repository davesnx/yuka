open Dom

let () =
  check_urls "Private.expand" (fun tag name value ->
      let t =
        Yuka.template_coded (fixed_code tag name value) ~html:"" ~walk:[||] ~kids:[||] ~attrs:[||] ~values:[||]
          ~clones:1
      in
      Yuka.Private.element (Yuka.Private.expand t [||]));
  finish "URL check through Private.expand"
