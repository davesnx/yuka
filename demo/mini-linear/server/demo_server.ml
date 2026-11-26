let packages dir =
  match Sys.readdir (Filename.concat dir "node_modules") with
  | names ->
      Array.sort compare names;
      Array.to_list names
  | exception Sys_error _ -> []

let late_script inner req =
  match Dream.header req "referer" with
  | Some referer
    when String.ends_with ~suffix:"/before-hydration" referer
         && String.ends_with ~suffix:"/main.js" (Dream.target req) ->
      Lwt.bind (Lwt_unix.sleep 3.) (fun () -> inner req)
  | _ -> inner req

let theme_script =
  let open Demo_shared.Theme in
  let pattern slugs = "/^(" ^ String.concat "|" slugs ^ ")$/" in
  let stored (preference : Demo_shared.Preference.t) =
    Printf.sprintf {|["%s",%s]|} preference.key
      (pattern (List.filter_map (fun (slug, _) -> if slug = "" then None else Some slug) preference.choices))
  in
  Printf.sprintf
    {|<script>(function(){var root=document.documentElement,theme,code;try{theme=localStorage.getItem("%s");code=localStorage.getItem("%s");[%s].forEach(function(p){var value=localStorage.getItem("%s"+p[0]);if(p[1].test(value))root.setAttribute("%s"+p[0],value)})}catch(error){}if(!%s.test(theme))theme=matchMedia("(prefers-color-scheme: light)").matches?"light":"dark";root.setAttribute("%s",theme);if(%s.test(code))root.setAttribute("%s",code)})()</script>|}
    storage_key Code.storage_key
    (String.concat "," (List.map stored Demo_shared.Preference.stored))
    (Demo_shared.Preference.storage_key "") (Demo_shared.Preference.attribute "")
    (pattern (List.map slug all)) attribute (pattern (List.map Code.slug Code.all)) Code.attribute

let refresh_store base inner req =
  let target = Dream.target req in
  if not (String.starts_with ~prefix:(base ^ "/static/") target || String.starts_with ~prefix:(base ^ "/_yuka/app/") target) then
    Demo_shared.Store.refresh ();
  inner req

let with_index index apps req =
  let target = Dream.target req in
  match List.find_opt (fun (config, _) -> Yuka.Server.Prerender.path config target <> None) apps with
  | Some (_, app) -> app req
  | None when String.starts_with ~prefix:"/_yuka/" target -> Dream.empty `Not_Found
  | None -> index req

let node_name () =
  Printf.sprintf "%s-%d-%s" (Unix.gethostname ()) (Unix.getpid ()) Demo_shared.Store.process_id

let read_file path = In_channel.with_open_bin path In_channel.input_all

let stop message =
  prerr_endline ("demo_server: " ^ message);
  exit 1

let () =
  let here = Filename.dirname Sys.executable_name in
  let port =
    ref
      (match Sys.getenv_opt "PORT" with
      | None -> 8080
      | Some value -> (
          match int_of_string_opt value with
          | Some port -> port
          | None -> stop ("PORT is not a number: " ^ value)))
  in
  let interface = ref "localhost" in
  let js_dir = ref (Filename.concat here "../client/out") in
  let static_dir = ref (Filename.concat here "../static") in
  let manifest = ref (Filename.concat here "../client/yuka_islands.json") in
  let metafile = ref (Filename.concat here "../client/meta.json") in
  let bundle = ref false in
  let prerender = ref "" in
  let prerendered = ref "" in
  let second = ref 0 in
  let bus = ref "memory" in
  let base = ref "" in
  let async_feed = ref (Filename.concat here "../../async-feed") in
  let infinite_scroll = ref (Filename.concat here "../../infinite-scroll") in
  let posters = ref (Filename.concat here "../../posters") in
  let crate = ref (Filename.concat here "../../crate") in
  let variable name = match Sys.getenv_opt name with Some "" | None -> None | value -> value in
  let database =
    ref
      (match variable "YUKA_DEMO_DATABASE" with
      | Some conninfo -> conninfo
      | None when Sys.getenv_opt "VERCEL_ENV" = Some "production" ->
          Option.value (List.find_map variable [ "DATABASE_URL_UNPOOLED"; "POSTGRES_URL_NON_POOLING" ]) ~default:""
      | None -> "")
  in
  let reset_days =
    ref
      (match Sys.getenv_opt "YUKA_DEMO_RESET_DAYS" with
      | None | Some "" -> 7
      | Some value -> (
          match int_of_string_opt value with
          | Some days -> days
          | None -> stop ("YUKA_DEMO_RESET_DAYS is not a number: " ^ value)))
  in
  let secret =
    ref (Option.value (Sys.getenv_opt "YUKA_DEMO_SECRET") ~default:"yuka-demo-secret-for-development-only")
  in
  Arg.parse
    [
      ("--port", Arg.Set_int port, "Port to listen on (default: $PORT, or 8080)");
      ("--interface", Arg.Set_string interface, "Network interface to listen on (default localhost)");
      ("--js-dir", Arg.Set_string js_dir, "Melange output directory");
      ("--bundle", Arg.Set bundle, "Serve the esbuild bundle instead of the module tree");
      ("--manifest", Arg.Set_string manifest, "Island manifest (yuka_islands.json)");
      ("--metafile", Arg.Set_string metafile, "esbuild metafile, with --bundle");
      ("--static-dir", Arg.Set_string static_dir, "Directory of style.css");
      ("--prerender", Arg.Set_string prerender, "Write the prerendered pages to DIR and exit");
      ("--prerendered", Arg.Set_string prerendered, "Serve the prerendered pages of DIR");
      ("--base", Arg.Set_string base, "Serve the app under this path prefix, as /mini-linear, and the list of demos at every other path (default: none)");
      ("--async-feed", Arg.Set_string async_feed, "With --base: directory of the Async demo (client/ and static/), served under /async-feed");
      ( "--infinite-scroll",
        Arg.Set_string infinite_scroll,
        "With --base: directory of the Infinite scroll demo (client/ and static/), served under /infinite-scroll" );
      ("--posters", Arg.Set_string posters, "With --base: directory of the Posters demo (client/ and static/), served under /posters");
      ("--crate", Arg.Set_string crate, "With --base: directory of the Crate demo (client/ and static/), served under /crate");
      ("--secret", Arg.Set_string secret, "Secret of the session cookies (default: $YUKA_DEMO_SECRET)");
      ( "--second-node",
        Arg.Set_int second,
        "Also serve a second live node on this port, joined to the first by a bus (same store)" );
      ("--bus", Arg.Set_string bus, "With --second-node: memory (default) or pg:CONNINFO (yuka-live-pg)");
      ( "--database",
        Arg.Set_string database,
        "Postgres connection string of the shared store, a direct (not pooled) one (default: $YUKA_DEMO_DATABASE, or on Vercel production $DATABASE_URL_UNPOOLED or $POSTGRES_URL_NON_POOLING; empty: in memory)" );
      ( "--reset-days",
        Arg.Set_int reset_days,
        "The data starts again from the seed when it is older than this many days (default: $YUKA_DEMO_RESET_DAYS, or 7)" );
    ]
    (fun _ -> ())
    "demo_server [--port N] [--interface ADDRESS] [--bundle] [--prerender DIR] [--prerendered DIR] [--base PREFIX]";
  let manifest = read_file !manifest in
  let client = Filename.concat !js_dir "demo/mini-linear/client" in
  let assets =
    match
      if !bundle then
        Yuka.Server.bundle ~dir:client ~entry:"bundle/main.js" ~manifest
          ~metafile:(read_file !metafile)
      else
        Yuka.Server.modules ~dir:!js_dir ~entry:"demo/mini-linear/client/main.js" ~manifest
          ~packages:(packages !js_dir) ~digest:(Yuka.Server.tree_digest !js_dir)
    with
    | Ok assets -> assets
    | Error message -> stop message
  in
  let index = Yuka_dream.handler (Yuka.Server.config ~head:Demo_index.Pages.head ()) Demo_index.Yuka_routes.app in
  let base = !base in
  if base <> "" && not (List.exists (fun (demo : Demo_index.Pages.demo) -> demo.path = base) Demo_index.Pages.demos) then
    stop ("--base must be the path of a demo in the index: " ^ base);
  let others =
    if base = "" then []
    else if base = "/async-feed" then stop "--base /async-feed is the path of the Async demo"
    else if base = "/infinite-scroll" then stop "--base /infinite-scroll is the path of the Infinite scroll demo"
    else if base = "/posters" then stop "--base /posters is the path of the Posters demo"
    else if base = "/crate" then stop "--base /crate is the path of the Crate demo"
    else
      let dev = !prerender = "" && Sys.getenv_opt "YUKA_DEV" = Some "1" in
      let async =
        match Async_feed_app.Serve.make ~base:"/async-feed" ~bundle:!bundle ~dir:!async_feed ~secret:!secret ~dev () with
        | Ok async -> (async.config, async.handler)
        | Error message -> stop ("the Async demo: " ^ message)
      in
      let infinite =
        match
          Infinite_scroll_app.Serve.make ~base:"/infinite-scroll" ~bundle:!bundle ~dir:!infinite_scroll ~secret:!secret
            ~dev ()
        with
        | Ok infinite -> (infinite.config, infinite.handler)
        | Error message -> stop ("the Infinite scroll demo: " ^ message)
      in
      let posters =
        match Posters_app.Serve.make ~base:"/posters" ~bundle:!bundle ~dir:!posters ~dev () with
        | Ok posters -> (posters.config, posters.handler)
        | Error message -> stop ("the Posters demo: " ^ message)
      in
      let crate =
        match Crate_app.Serve.make ~base:"/crate" ~bundle:!bundle ~dir:!crate ~dev () with
        | Ok crate -> (crate.config, crate.handler)
        | Error message -> stop ("the Crate demo: " ^ message)
      in
      [ async; infinite; posters; crate ]
  in
  let config =
    match
      Yuka.Server.config ~base ~assets
        ~public:[ ("/static", !static_dir) ]
        ?prerendered:(if !prerendered = "" then None else Some !prerendered)
        ~head:
          ({|<meta name="viewport" content="width=device-width, initial-scale=1"><link rel="icon" type="image/svg+xml" href="|}
          ^ base ^ {|/static/favicon.svg">|} ^ theme_script ^ Demo_shared.Code_style.head)
        ~styles:[ base ^ "/static/style.css"; base ^ "/static/markdown.css" ] ~css:Demo_app.Yuka_css.sheets
        ~dev:(!prerender = "" && Sys.getenv_opt "YUKA_DEV" = Some "1")
        ()
    with
    | config -> config
    | exception Invalid_argument message -> stop message
  in
  Demo_app.Handlers.register ();
  if !reset_days < 1 then stop "the reset age must be at least 1 day";
  if !database <> "" && !prerender = "" then begin
    List.iter
      (fun (name, value) -> if Sys.getenv_opt name = None then Unix.putenv name value)
      [
        ("PGCONNECT_TIMEOUT", "5");
        ("PGOPTIONS", "-c lock_timeout=5s -c statement_timeout=10s -c idle_in_transaction_session_timeout=15s");
      ];
    (match Demo_shared.Store.connect ~conninfo:!database ~reset_days:!reset_days with
    | Ok () -> ()
    | Error message ->
        prerr_endline ("demo_server: the database is not available: " ^ message);
        exit 1);
    if !second = 0 then begin
      Demo_shared.Store.notifies := true;
      Lwt_main.run
        (Yuka_dream.to_lwt
           (Yuka.Server.Live.use_bus ~name:(node_name ()) (Yuka_live_pg.bus ~conninfo:!database ~channel:"yuka_demo" ())))
    end
  end;
  let app = Demo_app.Yuka_routes.app in
  if !prerender <> "" then (
    match Lwt_main.run (Yuka_dream.prerender ~out:!prerender config app) with Ok () -> () | Error message -> stop message)
  else if !second = 0 then
    Dream.run ~interface:!interface ~port:!port @@ Dream.logger @@ with_index index ((config, refresh_store base @@ late_script @@ Dream.set_secret !secret
    @@ Dream.cookie_sessions @@ Yuka_dream.handler config app) :: others)
  else begin
    let make_bus =
      match String.index_opt !bus ':' with
      | Some colon when String.sub !bus 0 colon = "pg" ->
          let conninfo = String.sub !bus (colon + 1) (String.length !bus - colon - 1) in
          Demo_shared.Store.notifies := true;
          fun () -> Yuka_live_pg.bus ~conninfo ~channel:"yuka_demo" ()
      | _ when !bus = "memory" ->
          let memory = Yuka.Server.Live.memory () in
          fun () -> Yuka.Server.Live.memory_bus memory
      | _ -> stop ("unknown --bus " ^ !bus)
    in
    let other = Yuka.Server.Live.node () in
    let serve ?node port =
      Dream.serve ~interface:!interface ~port @@ Dream.logger @@ with_index index ((config, refresh_store base @@ late_script @@ Dream.set_secret !secret
      @@ Dream.cookie_sessions @@ Yuka_dream.handler ?node config app) :: others)
    in
    Lwt_main.run
      (let open Lwt.Syntax in
       let* () = Yuka_dream.to_lwt (Yuka.Server.Live.use_bus ~name:"first" (make_bus ())) in
       let* () = Yuka_dream.to_lwt (Yuka.Server.Live.use_bus ~node:other ~name:"second" (make_bus ())) in
       Lwt.join [ serve !port; serve ~node:other !second ])
  end
