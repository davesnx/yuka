let commands =
  [
    ("routes", Yuka_routes_cmd.main, "Write the shared or the server module of a Routes.ml route tree");
    ("islands", Yuka_islands.main, "Write the island registry or manifest of the island libraries");
    ("css", Yuka_css.main, "Write the module with the sheets of every [%yuka.css] declaration");
    ("dev", Yuka_dev.main, "Rebuild in watch mode, restart the server and reload the browser");
  ]

let usage =
  "usage: yuka COMMAND [OPTION]...\n\ncommands:\n"
  ^ String.concat "" (List.map (fun (name, _, doc) -> Printf.sprintf "  %-8s %s\n" name doc) commands)
  ^ "\nyuka COMMAND --help shows the options of a command.\n"

let () =
  match Array.to_list Sys.argv with
  | _ :: ("--help" | "-help" | "help") :: _ -> print_string usage
  | _ :: name :: rest when List.exists (fun (n, _, _) -> n = name) commands ->
      let _, main, _ = List.find (fun (n, _, _) -> n = name) commands in
      main (Array.of_list (("yuka " ^ name) :: rest))
  | [] | [ _ ] ->
      prerr_string ("yuka: no command\n" ^ usage);
      exit 2
  | _ :: name :: _ ->
      prerr_string ("yuka: unknown command " ^ name ^ "\n" ^ usage);
      exit 2
