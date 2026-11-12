open Dom

let () =
  check_urls "Template.make" (fun tag name value ->
      let t =
        Yuka.Template.make
          Yuka.Template.(element tag [ fixed name value ] [])
          ~html:"<p><div></div></p>" ~walk:[||] ~kids:[||] ~attrs:[||] ~values:[||]
      in
      Yuka.Template.instance t [||]);
  finish "URL check through Template.make"
