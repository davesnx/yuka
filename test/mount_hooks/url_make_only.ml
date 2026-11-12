open Dom

let () =
  check_urls "Private.Template.make" (fun tag name value ->
      let t =
        Yuka.Private.Template.make
          Yuka.Private.Template.(element tag [ fixed name value ] [])
          ~html:"<p><div></div></p>" ~walk:[||] ~kids:[||] ~attrs:[||] ~values:[||]
      in
      Yuka.runtime_instance t [||]);
  finish "URL check through Private.Template.make"
