let () =
  match Routes_fixture.Routes.find `GET [ "legacy-blog" ] [] with
  | Yuka.Router.Redirect { location; _ } -> print_endline location
  | _ -> print_endline "other"
