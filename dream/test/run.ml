let static =
  let dir = Filename.temp_dir "yuka_static" "" in
  Out_channel.with_open_bin (Filename.concat dir "s.css") (fun oc -> output_string oc "body{}");
  dir

let config = Yuka.Server.config ~public:[ ("/static", static) ] ~css:[ ("w-0a1b.css", ".w_0a1b{}") ] ()

let rec files dir prefix =
  Sys.readdir dir |> Array.to_list |> List.sort compare
  |> List.concat_map (fun name ->
         let path = Filename.concat dir name and rel = prefix ^ name in
         if Sys.is_directory path then files path (rel ^ "/")
         else [ (rel, In_channel.with_open_bin path In_channel.input_all) ])

let with_stderr f =
  let file = Filename.temp_file "yuka_stderr" "" in
  let saved = Unix.dup Unix.stderr in
  let fd = Unix.openfile file [ Unix.O_WRONLY; Unix.O_TRUNC ] 0o600 in
  Unix.dup2 fd Unix.stderr;
  Fun.protect
    ~finally:(fun () ->
      Unix.dup2 saved Unix.stderr;
      Unix.close fd)
    f;
  In_channel.with_open_bin file In_channel.input_all

let prerender out = Lwt_main.run (Yuka_dream.prerender ~out config Routes_server.app)

let contains text part =
  let n = String.length part in
  let rec at i = i + n <= String.length text && (String.sub text i n = part || at (i + 1)) in
  at 0

let check_true msg b = Alcotest.(check bool) msg true b

let pages () =
  let out = Filename.temp_dir "yuka_out" "" in
  let warnings = with_stderr (fun () -> prerender out) in
  let written = files out "" in
  Alcotest.(check (list string))
    "files"
    [
      "404.html";
      "_yuka/css/w-0a1b.css";
      "docs/index.html";
      "feed.xml";
      "guide/index.html";
      "index.html";
      "post/hello/index.html";
      "post/world/index.html";
      "static/s.css";
    ]
    (List.map fst written);
  let file name = List.assoc name written in
  check_true "home" (contains (file "index.html") "<title>Home</title>");
  check_true "crawled from a crawled page" (contains (file "post/world/index.html") "post world");
  check_true "rule header page" (contains (file "post/hello/index.html") "class=\"root\"");
  Alcotest.(check string) "endpoint" "<rss/>" (file "feed.xml");
  check_true "404 page" (contains (file "404.html") "missing /404.html");
  Alcotest.(check string) "static copied" "body{}" (file "static/s.css");
  Alcotest.(check string) "css sheet written" ".w_0a1b{}" (file "_yuka/css/w-0a1b.css");
  check_true "warning for the 404 link" (contains warnings "/post/missing answered 404");
  check_true "no warning for links that are not prerendered" (not (contains warnings "/secret"));
  check_true "files are not crawled" (not (contains warnings "/_yuka"));
  check_true "a path that cannot be a file name"
    (contains warnings "yuka-dream prerender: /a%2Fb answered 200 but cannot be a file name, not written");
  let req = Dream.request ~target:"/" "" in
  List.iter
    (fun (path, expected) ->
      Alcotest.(check bool) path expected (Yuka.Server.prerenderable config Routes_server.app req path))
    [ ("/guide", true); ("/static/s.css", false); ("/_yuka/app.js", false); ("/_yuka", false) ]

let twice () =
  let out = Filename.temp_dir "yuka_out" "" in
  ignore (with_stderr (fun () -> prerender out));
  let first = files out "" in
  ignore (with_stderr (fun () -> prerender out));
  Alcotest.(check (list (pair string string))) "same files" first (files out "")

let serve () =
  let out = Filename.temp_dir "yuka_out" "" in
  ignore (with_stderr (fun () -> prerender out));
  Out_channel.with_open_bin (Filename.concat out "docs/index.html") (fun oc ->
      output_string oc "from disk");
  let handler = Yuka_dream.handler (Yuka.Server.config ~prerendered:out ()) Routes_server.app in
  let call target =
    let response = Dream.test handler (Dream.request ~target "") in
    (response, Lwt_main.run (Dream.body response))
  in
  let response, body = call "/docs" in
  Alcotest.(check string) "file" "from disk" body;
  Alcotest.(check (option string)) "rule header" (Some "test") (Dream.header response "x-site");
  Alcotest.(check (option string)) "type" (Some "text/html; charset=utf-8")
    (Dream.header response "content-type");
  let _, body = call "/docs?x=1" in
  check_true "a query renders" (contains body "<p>docs</p>");
  let _, body = call "/secret" in
  check_true "not prerendered" (contains body "secret");
  let response, body = call "/post/nope" in
  Alcotest.(check int) "missing file renders" 404 (Dream.status_to_int (Dream.status response));
  check_true "not found" (contains body "missing /post/nope")

let prerender_without_dev () =
  Unix.putenv "YUKA_DEV" "1";
  let config = Fun.protect ~finally:(fun () -> Unix.putenv "YUKA_DEV" "") (fun () -> Yuka.Server.config ()) in
  let out = Filename.temp_dir "yuka_out" "" in
  ignore (with_stderr (fun () -> Lwt_main.run (Yuka_dream.prerender ~out config Routes_server.app)));
  let index = In_channel.with_open_bin (Filename.concat out "index.html") In_channel.input_all in
  check_true "a page" (contains index "<title>Home</title>");
  check_true "no dev script in a prerendered page" (not (contains index "EventSource"))

let out_inside_a_served_dir () =
  let dir = Filename.temp_dir "yuka_static" "" in
  Out_channel.with_open_bin (Filename.concat dir "s.css") (fun oc -> output_string oc "x");
  let config = Yuka.Server.config ~public:[ ("/static", dir) ] () in
  List.iter
    (fun out ->
      match Lwt_main.run (Yuka_dream.prerender ~out config Routes_server.app) with
      | () -> Alcotest.failf "%s accepted" out
      | exception Invalid_argument m -> check_true "names the directory" (contains m dir))
    [ Filename.concat dir "site"; dir; Filename.concat dir "a/../site" ];
  Alcotest.(check (list string)) "nothing written" [ "s.css" ] (List.map fst (files dir ""))

let tree_digest () =
  let dir = Filename.temp_dir "yuka_tree" "" in
  let write name text =
    Out_channel.with_open_bin (Filename.concat dir name) (fun oc -> output_string oc text)
  in
  Sys.mkdir (Filename.concat dir "a") 0o755;
  write "a/x.js" "one";
  write "y.js" "two";
  let first = Yuka_dream.tree_digest dir in
  Alcotest.(check string) "stable" first (Yuka_dream.tree_digest dir);
  write "a/x.js" "ONE";
  let changed = Yuka_dream.tree_digest dir in
  check_true "content changes it" (changed <> first);
  write "z.js" "";
  check_true "a new file changes it" (Yuka_dream.tree_digest dir <> changed)

let echo = Yuka.Action.declare ~name:"echo" ~input:Yuka.Codec.string ~output:Yuka.Codec.int
let () = Yuka.Server.Action.implement echo (fun s -> Yuka.Async.return (String.length s))

let body_limit () =
  let handler = Yuka_dream.handler config Routes_server.app in
  let post ?length body =
    let headers =
      [ ("Content-Type", "application/json"); ("Origin", "http://app.test"); ("Host", "app.test") ]
      @ match length with Some n -> [ ("Content-Length", string_of_int n) ] | None -> []
    in
    let response = Dream.test handler (Dream.request ~method_:`POST ~target:"/_yuka/action/echo" ~headers body) in
    (Dream.status_to_int (Dream.status response), Lwt_main.run (Dream.body response))
  in
  let quoted size = "\"" ^ String.make (size - 2) 'x' ^ "\"" in
  Alcotest.(check int) "at the limit" 200 (fst (post (quoted 1_048_576)));
  Alcotest.(check (pair int string)) "over the limit"
    (413, {|{"error":"request too large"}|})
    (post (quoted 1_048_577));
  Alcotest.(check int) "a declared length over the limit is refused before reading" 413
    (fst (post ~length:2_000_000 (quoted 4)));
  Alcotest.(check (pair int string)) "a small declared length" (200, {|{"ok":2}|}) (post ~length:4 (quoted 4))

let () =
  Alcotest.run "yuka-dream"
    [
      ( "prerender",
        [
          Alcotest.test_case "seeds, crawled links, 404.html, assets" `Quick pages;
          Alcotest.test_case "twice gives the same files" `Quick twice;
          Alcotest.test_case "the handler serves prerendered files" `Quick serve;
          Alcotest.test_case "a prerender with YUKA_DEV=1 writes no dev script" `Quick prerender_without_dev;
          Alcotest.test_case "out inside a served directory is refused" `Quick out_inside_a_served_dir;
          Alcotest.test_case "tree digest follows file contents" `Quick tree_digest;
        ] );
      ("body", [ Alcotest.test_case "the body limit" `Quick body_limit ]);
    ]
