let main argv =
  let source = ref None and shared = ref false and server = ref false and shared_module = ref None in
  let c =
    { Cli.name = "routes";
      usage =
        "usage: yuka routes --source FILE --shared\n\
        \       yuka routes --source FILE --server --shared-module MODULE\n\
         Read the route tree in FILE (Routes.ml) and print the shared module (--shared) or the server module (--server).";
      specs =
        [ ("--source", Arg.String (fun f -> source := Some f), "FILE The route file, Routes.ml");
          ("--shared", Arg.Set shared, " Print the shared module: the route type, href and find");
          ("--server", Arg.Set server, " Print the server module: the app of the routes");
          ("--shared-module", Arg.String (fun m -> shared_module := Some m), "MODULE The module path of the shared module, for --server") ] }
  in
  Cli.parse c argv;
  let source = match !source with Some s -> s | None -> Cli.usage_error c "give --source FILE" in
  match (!shared, !server, !shared_module) with
  | true, false, None -> Yuka_routes.shared source
  | false, true, Some m when Yuka_routes.is_module_path m -> Yuka_routes.server ~shared_module:m source
  | false, true, Some m -> Cli.usage_error c "--shared-module takes a module path such as App.Routes, not %S" m
  | false, true, None -> Cli.usage_error c "--server needs --shared-module MODULE"
  | true, false, Some _ -> Cli.usage_error c "--shared-module is only for --server"
  | true, true, _ -> Cli.usage_error c "give one of --shared and --server, not both"
  | false, false, _ -> Cli.usage_error c "give --shared or --server"
