let head base =
  {|<meta name="viewport" content="width=device-width, initial-scale=1"><link rel="icon" type="image/svg+xml" href="|}
  ^ base ^ {|/static/favicon.svg">|}

let read path = In_channel.with_open_bin path In_channel.input_all

let packages dir =
  match Sys.readdir (Filename.concat dir "node_modules") with
  | names ->
      Array.sort compare names;
      Array.to_list names
  | exception Sys_error _ -> []

type t = { config : Yuka.Server.config; handler : Dream.handler }

let assets ~bundle ~client =
  let js_dir = Filename.concat client "out" in
  match read (Filename.concat client "yuka_islands.json") with
  | exception Sys_error message -> Error message
  | manifest when bundle -> (
      match read (Filename.concat client "meta.json") with
      | exception Sys_error message -> Error message
      | metafile ->
          Yuka.Server.bundle ~dir:(Filename.concat js_dir "demo/quest/client") ~entry:"bundle/main.js" ~manifest
            ~metafile)
  | manifest ->
      Yuka.Server.modules ~dir:js_dir ~entry:"demo/quest/client/main.js" ~manifest ~packages:(packages js_dir)
        ~digest:(Yuka.Server.tree_digest js_dir)

let make ?(base = "") ?(bundle = false) ?(dev = false) ~dir ~secret () =
  Result.bind (assets ~bundle ~client:(Filename.concat dir "client")) (fun assets ->
      match
        Yuka.Server.config ~base ~assets
          ~public:[ ("/static", Filename.concat dir "static") ]
          ~head:(head base)
          ~styles:[ base ^ "/static/style.css" ]
          ~dev ()
      with
      | exception Invalid_argument message -> Error message
      | config ->
          Ok { config; handler = Dream.set_secret secret @@ Dream.cookie_sessions @@ Yuka_dream.handler config Yuka_routes.app })
