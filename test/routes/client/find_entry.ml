let () =
  match Routes_fixture.Routes.find `GET [] [] with
  | Yuka.Router.Found _ -> print_endline "found"
  | _ -> print_endline "other"
