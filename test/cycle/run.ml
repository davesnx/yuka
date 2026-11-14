module Async = Yuka.Async
module Server = Yuka.Server
module App = Cycle_server.App

type reply = { status : int; headers : (string * string) list; body : string }

let files = [ ("pre/plain/index.html", "prerendered plain"); ("js/app/main.js", "main"); ("pub/s.css", "css"); ("b/bundle/chunk-X1.js", "c"); ("b/bundle/main.js", "m") ]
let file_calls = ref []
let body_read = ref 0

module Test_adapter = struct
  type request = App.req
  type nonrec reply = reply

  let meth (r : request) = r.meth
  let target (r : request) = r.target
  let header = App.header
  let body (r : request) ~limit =
    let n = String.length r.body in
    let rec read at =
      if at >= n then Some r.body
      else
        let chunk = min 4096 (n - at) in
        body_read := !body_read + chunk;
        if at + chunk > limit then None else read (at + chunk)
    in
    Async.return (read 0)

  let session (r : request) =
    if App.header r "x-no-session" <> None then None else Some "cycle-session"
  let csrf_token (r : request) =
    if App.header r "x-no-session" <> None then None else Some "cycle-token"
  let verify_csrf (_ : request) token = Async.return (token = "cycle-token")
  let upgrade (_ : request) _ = Async.return { status = 101; headers = []; body = "upgraded" }

  let respond (r : Server.response) =
    match r.body with
    | Server.String s -> Async.return { status = r.status; headers = r.headers; body = s }
    | Server.Stream f ->
        let b = Buffer.create 64 in
        Async.map
          (fun () -> { status = r.status; headers = r.headers; body = Buffer.contents b })
          (f (fun s ->
               Buffer.add_string b s;
               Async.return ()))

  let exists ~root ~path = List.mem_assoc (root ^ "/" ^ path) files

  let file _ ~root ~path ~headers =
    let name = root ^ "/" ^ path in
    file_calls := name :: !file_calls;
    Async.return
      (match List.assoc_opt name files with
      | Some body -> { status = 200; headers; body }
      | None -> { status = 404; headers = [ ("cache-control", "no-store") ]; body = "" })

  let sleep _ =
    let a, _, _ = Async.make () in
    a
end

module Cycle = Server.Adapter.Make (Test_adapter)

let held_writes : (string * (unit -> unit)) list ref = ref []
let stream_ended = ref false
let late_writes = ref 0

module Held_adapter = struct
  include Test_adapter

  type nonrec reply = { reply : reply; ended : unit Async.t }

  let respond (r : Server.response) =
    match r.body with
    | Server.String s ->
        Async.return
          { reply = { status = r.status; headers = r.headers; body = s }; ended = Async.return () }
    | Server.Stream f ->
        let ended =
          f (fun s ->
              if !stream_ended then incr late_writes;
              let a, resolve, _ = Async.make () in
              held_writes := !held_writes @ [ (s, fun () -> resolve ()) ];
              a)
        in
        Async.on_settled ended (fun _ -> stream_ended := true);
        Async.return { reply = { status = r.status; headers = r.headers; body = "" }; ended }

  let file _ ~root:_ ~path:_ ~headers:_ = assert false
  let upgrade _ _ = assert false
end

module Held = Server.Adapter.Make (Held_adapter)

let raw_sleep = ref Test_adapter.sleep

module Raw = Server.Adapter.Make (struct
  include Test_adapter

  type reply = Server.response

  let respond r = Async.return r
  let exists ~root:_ ~path:_ = false
  let file _ ~root:_ ~path:_ ~headers:_ = assert false
  let upgrade _ _ = assert false
  let sleep s = !raw_sleep s
end)

let logged = ref []
let log_hook = ref (fun (_ : Server.log_level) m -> logged := m :: !logged)
let config_with = Server.config ~log:(fun level m -> !log_hook level m)

let ok = function Ok v -> v | Error m -> Alcotest.fail m

let modules =
  ok
    (Server.modules ~dir:"js" ~entry:"./app/main.js" ~manifest:{|{"Counter":"./counter.js"}|} ~digest:"d1"
       ~packages:[ "pkg" ])

let config =
  config_with ~assets:modules ~public:[ ("/static", "pub") ] ~styles:[ "/static/s.css" ] ()

let request ?(meth = `GET) ?(headers = []) ?(body = "") target =
  App.reset ();
  logged := [];
  file_calls := [];
  log_hook := (fun _ m -> logged := m :: !logged);
  { App.meth; target; headers; body }

let fst3 (a, _, _) = a

let call ?(config = config) r = Cycle.handler config Cycle_server.Yuka_routes.app r

let get ?config ?meth ?headers ?body target =
  let a = call ?config (request ?meth ?headers ?body target) in
  match Async.status a with
  | Async.Done v -> v
  | Async.Failed m -> Alcotest.failf "%s failed: %s" target m
  | Async.Pending -> Alcotest.failf "%s is pending" target

let contains text part =
  let n = String.length part in
  let rec at i = i + n <= String.length text && (String.sub text i n = part || at (i + 1)) in
  at 0

let index text part =
  let n = String.length part in
  let rec at i =
    if i + n > String.length text then -1 else if String.sub text i n = part then i else at (i + 1)
  in
  at 0

let count text part =
  let n = String.length part in
  let rec at i acc =
    if i + n > String.length text then acc
    else if String.sub text i n = part then at (i + n) (acc + 1)
    else at (i + 1) acc
  in
  at 0 0

let header r name =
  List.filter_map
    (fun (k, v) -> if String.lowercase_ascii k = name then Some v else None)
    r.headers

let check_status r expected = Alcotest.(check int) "status" expected r.status
let check_header r name expected = Alcotest.(check (list string)) name expected (header r name)
let check_events expected = Alcotest.(check (list string)) "events" expected (List.rev !App.events)
let check_true msg b = Alcotest.(check bool) msg true b

let assets =
  [
    ( "HEAD answers have no body",
      fun () ->
        List.iter
          (fun (target, status) ->
            let r = get ~meth:`HEAD target in
            check_status r status;
            Alcotest.(check string) ("no body for " ^ target) "" r.body)
          [ ("/_yuka/%2e%2e/x", 404); ("/_yuka/action/x", 405); ("/team/a/rename", 405); ("/nowhere", 404) ] );
    ( "a public prefix with no segment is rejected",
      fun () ->
        List.iter
          (fun prefix ->
            match config_with ~public:[ (prefix, "pub") ] () with
            | _ -> Alcotest.failf "prefix %S accepted" prefix
            | exception Invalid_argument _ -> ())
          [ "/"; ""; "//" ] );
    ( "a bad manifest is an Error that names Yuka.Server.modules",
      fun () ->
        let error manifest =
          match Server.modules ~dir:"js" ~entry:"main.js" ~manifest ~packages:[] ~digest:"" with
          | Ok _ -> Alcotest.failf "manifest %S accepted" manifest
          | Error m -> m
        in
        Alcotest.(check string) "not an object" "Yuka.Server.modules: manifest is not an object" (error "[]");
        Alcotest.(check string) "entry not a string" "Yuka.Server.modules: manifest entry A is not a string"
          (error {|{"A":1}|});
        let m = error {|{"A":"a.js"|} in
        check_true m (String.starts_with ~prefix:"Yuka.Server.modules: bad manifest JSON: " m) );
    ( "a bad metafile or manifest is an Error that names Yuka.Server.bundle",
      fun () ->
        let error ?(manifest = "{}") metafile =
          match Server.bundle ~dir:"b" ~entry:"main.js" ~manifest ~metafile with
          | Ok _ -> Alcotest.failf "metafile %S accepted" metafile
          | Error m -> m
        in
        Alcotest.(check string) "no outputs" "Yuka.Server.bundle: metafile has no outputs object" (error "{}");
        Alcotest.(check string) "not an object" "Yuka.Server.bundle: metafile is not an object" (error "[]");
        let m = error {|{"outputs":{"main.js":{}|} in
        check_true m (String.starts_with ~prefix:"Yuka.Server.bundle: bad metafile JSON: " m);
        Alcotest.(check string) "bad manifest" "Yuka.Server.bundle: manifest is not an object"
          (error ~manifest:"[]" {|{"outputs":{}}|}) );
    ( "asset miss is 404 no-store and never routed",
      fun () ->
        let r = get "/_yuka/app/nope.js" in
        check_status r 404;
        check_header r "cache-control" [ "no-store" ];
        check_events [];
        Alcotest.(check (list string)) "file asked" [ "js/nope.js" ] !file_calls );
    ( "css sheets are served immutable, a missing one is 404 no-store",
      fun () ->
        let config =
          config_with ~assets:modules ~css:[ ("a-1234.css", ".a_1234{}") ] ()
        in
        let r = get ~config "/_yuka/css/a-1234.css" in
        check_status r 200;
        Alcotest.(check string) "body" ".a_1234{}" r.body;
        check_header r "content-type" [ "text/css; charset=utf-8" ];
        check_header r "cache-control" [ "public, max-age=31536000, immutable" ];
        let r = get ~config ~meth:`HEAD "/_yuka/css/a-1234.css" in
        check_status r 200;
        Alcotest.(check string) "HEAD has no body" "" r.body;
        let r = get ~config "/_yuka/css/b-1234.css" in
        check_status r 404;
        check_header r "cache-control" [ "no-store" ];
        Alcotest.(check (list string)) "no file asked" [] !file_calls;
        Alcotest.(check (list (pair string string)))
          "css_files" [ ("_yuka/css/a-1234.css", ".a_1234{}") ] (Server.Prerender.css_files config) );
    ( "css names are decoded, other methods are 405, bad names are refused",
      fun () ->
        let config = config_with ~css:[ ("a b.css", "x") ] () in
        let r = get ~config "/_yuka/css/a%20b.css" in
        check_status r 200;
        Alcotest.(check string) "body" "x" r.body;
        let r = get ~config ~meth:`POST "/_yuka/css/a%20b.css" in
        check_status r 405;
        check_header r "allow" [ "GET, HEAD" ];
        List.iter
          (fun name ->
            match config_with ~css:[ (name, "x") ] () with
            | _ -> Alcotest.failf "css name %S accepted" name
            | exception Invalid_argument _ -> ())
          [ "../../x.css"; "a/b.css"; ""; ".."; "a\\b.css" ] );
    ( "asset file with no-cache",
      fun () ->
        let r = get "/_yuka/app/app/main.js" in
        check_status r 200;
        Alcotest.(check string) "body" "main" r.body;
        check_header r "cache-control" [ "no-cache" ] );
    ( "dot segments are rejected before the file system",
      fun () ->
        List.iter
          (fun target ->
            let r = get target in
            check_status r 404;
            check_header r "cache-control" [ "no-store" ];
            Alcotest.(check (list string)) ("no file for " ^ target) [] !file_calls)
          [ "/_yuka/../secret"; "/_yuka/app/%2e%2e/secret"; "/_yuka/app/a/%2F..%2Fx"; "/static/./s.css"; "/_yuka"; "/_yuka/main.js" ] );
    ( "asset methods",
      fun () ->
        let r = get ~meth:`POST "/_yuka/app/app/main.js" in
        check_status r 405;
        check_header r "allow" [ "GET, HEAD" ];
        let r = get ~meth:`HEAD "/static/s.css" in
        check_status r 200 );
    ( "public prefix",
      fun () ->
        let r = get "/static/s.css" in
        check_status r 200;
        Alcotest.(check string) "body" "css" r.body;
        let r = get "/static/none.css" in
        check_status r 404;
        check_events [] );
    ( "no assets configured",
      fun () ->
        let r = get ~config:(config_with ()) "/_yuka/app/app/main.js" in
        check_status r 404;
        Alcotest.(check (list string)) "no file" [] !file_calls );
    ( "bundle outputs other than the entry are immutable",
      fun () ->
        let bundle =
          ok
            (Server.bundle ~dir:"b" ~entry:"bundle/main.js" ~manifest:"{}"
               ~metafile:{|{"outputs":{"bundle/main.js":{"entryPoint":"main.js"},"bundle/chunk-X1.js":{}}}|})
        in
        let config = config_with ~assets:bundle () in
        let r = get ~config "/_yuka/app/bundle/chunk-X1.js" in
        check_header r "cache-control" [ "public, max-age=31536000, immutable" ];
        let r = get ~config "/_yuka/app/bundle/main.js" in
        check_header r "cache-control" [ "no-cache" ] );
    ( "a bundle preloads the static imports of each island and of the entry once",
      fun () ->
        let bundle =
          ok @@ Server.bundle ~dir:"b" ~entry:"bundle/main.js" ~manifest:{|{"Counter":"counter.js","Related":"related.js"}|}
            ~metafile:
              {|{"outputs":{
                "bundle/main.js":{"entryPoint":"main.js","imports":[{"path":"bundle/chunk-E.js","kind":"import-statement"},{"path":"bundle/counter-1.js","kind":"dynamic-import"},{"path":"bundle/related-1.js","kind":"dynamic-import"}]},
                "bundle/chunk-E.js":{"imports":[{"path":"bundle/chunk-C.js","kind":"import-statement"}]},
                "bundle/counter-1.js":{"entryPoint":"counter.js","imports":[{"path":"bundle/chunk-A.js","kind":"import-statement"},{"path":"bundle/dyn-1.js","kind":"dynamic-import"}]},
                "bundle/chunk-A.js":{"imports":[{"path":"bundle/chunk-B.js","kind":"import-statement"}]},
                "bundle/chunk-B.js":{"imports":[{"path":"bundle/chunk-C.js","kind":"import-statement"}]},
                "bundle/chunk-C.js":{"imports":[]},
                "bundle/dyn-1.js":{"entryPoint":"dyn.js","imports":[]},
                "bundle/related-1.js":{"entryPoint":"related.js","imports":[{"path":"bundle/chunk-C.js","kind":"import-statement"}]}}}|}
        in
        let r = get ~config:(config_with ~assets:bundle ()) "/islands" in
        let link file = {|<link rel="modulepreload" href="/_yuka/app/bundle/|} ^ file ^ {|">|} in
        List.iter
          (fun file -> Alcotest.(check int) file 1 (count r.body (link file)))
          [ "counter-1.js"; "chunk-A.js"; "chunk-B.js"; "chunk-C.js"; "chunk-E.js"; "related-1.js" ];
        check_true "no dynamic import" (not (contains r.body "dyn-1.js"));
        check_true "the entry is a script, not a preload" (not (contains r.body (link "main.js"))) );
    ( "GET /_yuka/csrf gives a fresh token to the same origin only",
      fun () ->
        let r = get ~headers:[ ("sec-fetch-site", "same-origin") ] "/_yuka/csrf" in
        check_status r 200;
        check_header r "cache-control" [ "no-store" ];
        Alcotest.(check string) "body" {|{"csrf":"cycle-token"}|} r.body;
        let r = get ~headers:[ ("origin", "https://evil.example"); ("host", "app.example") ] "/_yuka/csrf" in
        check_status r 403;
        let r = get ~headers:[ ("sec-fetch-site", "cross-site") ] "/_yuka/csrf" in
        check_status r 403;
        let r = get ~meth:`POST ~headers:[ ("sec-fetch-site", "same-origin") ] "/_yuka/csrf" in
        check_status r 405 );
    ( "action RPC",
      fun () ->
        let r = get ~meth:`GET "/_yuka/action/x" in
        check_status r 405;
        check_header r "allow" [ "POST" ];
        let r =
          get ~meth:`POST
            ~headers:[ ("content-type", "application/json"); ("origin", "http://app.example"); ("host", "app.example") ]
            ~body:"1" "/_yuka/action/x"
        in
        check_status r 404;
        Alcotest.(check string) "body" {|{"error":"unknown action x"}|} r.body );
  ]

let prerender =
  let prerendered = config_with ~assets:modules ~public:[ ("/static", "pub") ] ~prerendered:"pre" () in
  let app = Cycle_server.Yuka_routes.app in
  [
    ( "a prerendered page is its file, after the guards",
      fun () ->
        let r = get ~config:prerendered "/plain" in
        check_status r 200;
        Alcotest.(check string) "file" "prerendered plain" r.body;
        check_header r "content-type" [ "text/html; charset=utf-8" ];
        check_header r "x-frame-options" [ "DENY" ];
        check_header r "cache-control" [ "no-store" ];
        Alcotest.(check (list string)) "asked" [ "pre/plain/index.html" ] !file_calls );
    ( "HEAD on a file has no body",
      fun () ->
        List.iter
          (fun (config, target, status) ->
            let r = get ~config ~meth:`HEAD target in
            check_status r status;
            Alcotest.(check string) ("no body for " ^ target) "" r.body)
          [ (prerendered, "/plain", 200); (config, "/_yuka/app/app/main.js", 200);
            (config, "/static/s.css", 200); (config, "/_yuka/app/nope.js", 404) ];
        let r = get ~config:prerendered ~meth:`HEAD "/plain" in
        check_header r "content-type" [ "text/html; charset=utf-8" ] );
    ( "a prerendered page is rendered with a query, Yuka-Navigate or no file",
      fun () ->
        let rendered r = check_true "rendered" (contains r.body "<p>plain</p>") in
        rendered (get ~config:prerendered "/plain?x=1");
        rendered (get ~config:prerendered ~headers:[ ("Yuka-Navigate", "1") ] "/plain");
        rendered (get "/plain");
        Alcotest.(check (list string)) "no file" [] !file_calls;
        let r = get ~config:prerendered "/feed.xml" in
        Alcotest.(check string) "endpoints are not served from files" "feed" r.body );
    ( "seeds and prerenderable paths",
      fun () ->
        Alcotest.(check (list string)) "seeds" [ "/plain"; "/feed.xml" ] (Server.Prerender.seeds app);
        let req = request "/" in
        List.iter
          (fun (path, expected) -> Alcotest.(check bool) path expected (Server.Prerender.prerenderable config app req path))
          [ ("/plain", true); ("/plain?x=1#y", true); ("/feed.xml", true); ("/", false); ("/nowhere", false);
            ("/team/a/1", false); ("/_yuka/app/app/main.js", false); ("/static/s.css", false) ] );
    ( "links of a page",
      fun () ->
        Alcotest.(check (list string)) "links"
          [ "/a"; "/b&c"; "/"; "/caf%C3%A9"; "/c/d"; "/eA"; "/f\xc3\xa9&bogus;&amp" ]
          (Server.Prerender.links
             {|<a href="/a?x=1#y"></a><a href="//evil.com/x"></a><a href="https://e.com/"></a><a href="/b&amp;c"></a><link href="/"><a href="/a"><a href="#top"><a href="/caf%C3%A9"><a href="&#x2F;c&#47;d"><a href="/e&#X41;"><a href="/f&#233;&bogus;&amp;amp">|}) );
    ( "file of a path",
      fun () ->
        List.iter
          (fun (path, expected) -> Alcotest.(check (option string)) path expected (Server.Prerender.file path))
          [ ("/", Some "index.html"); ("/a/b", Some "a/b/index.html"); ("/feed.xml", Some "feed.xml");
            ("/caf%C3%A9", Some "caf\xc3\xa9/index.html"); ("/%2e%2e/x", None); ("/a%2Fb", None);
            ("/a?q=1", Some "a/index.html") ] );
    ( "the 404 page of the app",
      fun () ->
        match Async.status (Server.Prerender.missing_page config app ~sleep:Test_adapter.sleep) with
        | Async.Done resp -> (
            match Async.status (Test_adapter.respond resp) with
            | Async.Done r ->
                check_status r 404;
                check_true "page" (contains r.body "missing /404.html");
                check_true "layout" (contains r.body {|class="root"|})
            | _ -> Alcotest.fail "no body")
        | _ -> Alcotest.fail "no page" );
    ( "served directories",
      fun () ->
        Alcotest.(check (list (pair string string))) "dirs"
          [ ("/_yuka/app", "js"); ("/static", "pub") ]
          (Server.Prerender.served_dirs prerendered) );
    ( "query pairs are decoded",
      fun () ->
        let r = get "/find?q=a+b%26&tag=x%2By&tag=&other=1" in
        check_true "decoded" (contains r.body "a b&amp;|x+y,") );
  ]

let normalize =
  [
    ( "trailing slash is 308 with the query kept",
      fun () ->
        let r = get "/team/a/1/?q=1&r" in
        check_status r 308;
        check_header r "location" [ "/team/a/1?q=1&r" ];
        check_events [] );
    ( "empty segments are 308",
      fun () ->
        let r = get "//plain" in
        check_status r 308;
        check_header r "location" [ "/plain" ];
        let r = get "/team//a/1" in
        check_header r "location" [ "/team/a/1" ] );
    ( "segments are percent-decoded",
      fun () ->
        let r = get "/team/a%20b/1" in
        check_status r 200;
        check_true "decoded" (contains r.body "a b 1") );
    ( "a backslash in the path is 404, never a redirect",
      fun () ->
        List.iter
          (fun target ->
            let r = get target in
            check_status r 404;
            check_header r "location" [])
          [ "/\\evil.com/"; "/\\evil.com"; "/a/\\b/" ] );
    ( "a target without a leading slash is 404",
      fun () ->
        let r = get "*" in
        check_status r 404 );
  ]

let matching =
  [
    ( "permanent redirect node for any method",
      fun () ->
        List.iter
          (fun meth ->
            let r = get ~meth "/old" in
            check_status r 308;
            check_header r "location" [ "/" ];
            Alcotest.(check string) "no body" "" r.body)
          [ `GET; `POST; `DELETE ] );
    ( "temporary redirect keeps the query",
      fun () ->
        let r = get ~meth:`PUT "/tmp/x?y=1" in
        check_status r 307;
        check_header r "location" [ "/team/x/json?y=1" ] );
    ( "405 with the exact Allow",
      fun () ->
        let r = get ~meth:`POST "/feed.xml" in
        check_status r 405;
        check_header r "allow" [ "GET, HEAD, DELETE, OPTIONS" ];
        check_header r "cache-control" [ "no-store" ];
        Alcotest.(check string) "body" "Method Not Allowed" r.body;
        let r = get ~meth:`PUT "/plain" in
        check_header r "allow" [ "GET, HEAD, OPTIONS" ];
        let r = get ~meth:`GET "/team/a/rename" in
        check_header r "allow" [ "POST, OPTIONS" ];
        check_events [] );
    ( "OPTIONS is 204 with Allow",
      fun () ->
        let r = get ~meth:`OPTIONS "/feed.xml" in
        check_status r 204;
        check_header r "allow" [ "GET, HEAD, DELETE, OPTIONS" ];
        Alcotest.(check string) "no body" "" r.body;
        let r = get ~meth:`OPTIONS "/nowhere" in
        check_status r 404 );
    ( "no match is the not-found page in the root layout",
      fun () ->
        let r = get "/nowhere?x" in
        check_status r 404;
        check_header r "cache-control" [ "no-store" ];
        check_header r "x-frame-options" [ "DENY" ];
        check_true "page" (contains r.body "missing /nowhere");
        check_true "layout" (contains r.body {|class="root"|}) );
    ( "a fallback inside a param group with a layout",
      fun () ->
        let r = get "/org/acme/x/404" in
        check_status r 404;
        check_true "org layout with the param" (contains r.body {|<section class="org" data-org="acme">|});
        check_true "org outlet" (contains r.body {|data-k="L2/acme"|});
        check_true "page with the param" (contains r.body "no org page /org/acme/x/404 in acme");
        let r = get "/org/acme/x/1" in
        check_true "item" (contains r.body "acme 1 item") );
    ( "a param that does not decode is 404",
      fun () ->
        let r = get "/team/BAD/1" in
        check_status r 404;
        check_events [] );
  ]

let head_and_rules =
  [
    ( "HEAD on a page: GET status and headers with the GET length, no body",
      fun () ->
        let g = get "/" in
        check_events [ "home body" ];
        let h = get ~meth:`HEAD "/" in
        check_status h g.status;
        Alcotest.(check (list (pair string string)))
          "headers" (g.headers @ [ ("content-length", string_of_int (String.length g.body)) ]) h.headers;
        Alcotest.(check string) "no body" "" h.body;
        check_events [ "home body" ] );
    ( "HEAD on an endpoint has no body",
      fun () ->
        let h = get ~meth:`HEAD "/feed.xml" in
        check_status h 200;
        Alcotest.(check string) "no body" "" h.body;
        check_header h "content-type" [ "text/plain; charset=utf-8" ] );
    ( "page headers",
      fun () ->
        let r = get "/plain" in
        check_status r 200;
        check_header r "content-type" [ "text/html; charset=utf-8" ];
        check_header r "vary" [ "Yuka-Navigate, Yuka-Prefetch" ];
        check_header r "cache-control" [ "no-store" ];
        check_header r "x-frame-options" [ "DENY" ] );
    ( "header inheritance and override by name",
      fun () ->
        let r = get "/team/a/1" in
        check_header r "x-a" [ "team" ];
        check_header r "x-frame-options" [ "DENY" ];
        check_header r "cache-control" [ "private, max-age=5" ] );
    ( "handler headers win over rule headers",
      fun () ->
        let r = get "/feed.xml" in
        check_header r "cache-control" [ "no-cache" ];
        check_header r "x-frame-options" [ "SAMEORIGIN" ];
        check_header r "x-a" [ "root" ] );
    ( "cache strings",
      fun () ->
        let r = get "/team/a/json" in
        check_header r "cache-control" [ "public, max-age=60, s-maxage=600" ];
        let r = get "/asset.txt" in
        check_header r "cache-control" [ "public, max-age=31536000, immutable" ] );
    ( "vary values are joined",
      fun () ->
        let r = get "/varied" in
        check_header r "vary" [ "Cookie, Yuka-Navigate, Yuka-Prefetch" ];
        let r = get "/plain" in
        check_header r "vary" [ "Yuka-Navigate, Yuka-Prefetch" ] );
    ( "an Action is always no-store",
      fun () ->
        let r = get ~meth:`DELETE ~headers:[ ("sec-fetch-site", "same-origin") ] "/feed.xml" in
        check_status r 200;
        check_header r "cache-control" [ "no-store" ];
        let r = get ~meth:`POST "/team/a/rename" in
        check_header r "cache-control" [ "no-store" ] );
    ( "a handler error status does not get the rule cache",
      fun () ->
        let r = get "/team/gone/json" in
        check_status r 404;
        check_header r "cache-control" [ "no-store" ] );
  ]

let guards =
  [
    ( "guards run parent first, then loaders",
      fun () ->
        let r = get "/team/a/1" in
        check_status r 200;
        check_events [ "outer"; "inner"; "squad start"; "profile start" ] );
    ( "a guard stop skips loaders",
      fun () ->
        let r = get "/team/nobody/1" in
        check_status r 404;
        check_events [ "outer" ];
        let r = get "/team/away/1" in
        check_status r 303;
        check_header r "location" [ "/" ];
        check_header r "cache-control" [ "no-store" ];
        check_header r "x-frame-options" [ "DENY" ];
        check_events [ "outer" ] );
    ( "a prefetch allowed by the route gets the same answer as a navigation",
      fun () ->
        let plain = get ~headers:[ ("yuka-navigate", "-") ] "/team/a/1" in
        let pre = get ~headers:[ ("yuka-navigate", "-"); ("yuka-prefetch", "hover") ] "/team/a/1" in
        check_status pre plain.status;
        Alcotest.(check string) "same body" plain.body pre.body );
    ( "a stop Redirect stays on the site and needs a clean location",
      fun () ->
        List.iter
          (fun team ->
            let r = get ~headers:[ ("host", "app.example") ] ("/team/" ^ team ^ "/1") in
            check_status r 500;
            check_header r "location" [];
            Alcotest.(check int) "one log" 1 (List.length !logged))
          [ "offsite"; "crlf"; "badelsewhere" ] );
    ( "Redirect_off_site leaves the site, Forbidden is 403",
      fun () ->
        let r = get "/team/elsewhere/1" in
        check_status r 307;
        check_header r "location" [ "https://login.example/" ];
        check_header r "cache-control" [ "no-store" ];
        let r = get "/team/denied/1" in
        check_status r 403;
        check_header r "cache-control" [ "no-store" ];
        check_header r "x-frame-options" [ "DENY" ];
        check_events [ "outer" ] );
    ( "a guard Fail is 500 and logged",
      fun () ->
        let r = get "/team/a/0" in
        check_status r 500;
        check_true "no message" (not (contains r.body "guard secret"));
        Alcotest.(check (list string)) "log" [ "guard secret" ] !logged );
    ( "handlers get the request",
      fun () ->
        let r = get ~headers:[ ("X-User", "ana") ] "/team/a/json" in
        Alcotest.(check string) "body" {|{"team":"a","user":"ana"}|} r.body;
        let r = get ~headers:[ ("x-user", "ana") ] "/team/a/1" in
        check_true "loader read the header" (contains r.body "a 1 of a ana") );
    ( "Action from another origin is 403",
      fun () ->
        let r =
          get ~meth:`POST ~headers:[ ("Origin", "https://evil.example"); ("Host", "app.example") ]
            "/team/a/rename"
        in
        check_status r 403;
        check_events [];
        let r =
          get ~meth:`POST ~headers:[ ("Origin", "https://app.example"); ("Host", "app.example") ]
            "/team/a/rename"
        in
        check_status r 200;
        check_events [ "outer"; "rename" ];
        let r = get ~meth:`POST "/team/a/rename" in
        check_status r 403;
        let r = get ~meth:`POST ~headers:[ ("Sec-Fetch-Site", "same-origin") ] "/team/a/rename" in
        check_status r 200 );
    ( "an Endpoint with a safe method skips the origin check",
      fun () ->
        let r =
          get ~headers:[ ("Origin", "https://evil.example"); ("Host", "app.example") ] "/team/a/json"
        in
        check_status r 200 );
    ( "an Endpoint with an unsafe method checks the origin before its guards",
      fun () ->
        let r = get ~meth:`PUT ~headers:[ ("Origin", "https://evil.example"); ("Host", "app.example") ] "/thing" in
        check_status r 403;
        check_events [];
        let r = get ~meth:`PUT ~headers:[ ("Origin", "https://app.example"); ("Host", "app.example") ] "/thing" in
        check_status r 200;
        check_events [ "thing guard"; "thing" ] );
    ( "~cross_origin:true lets a webhook in",
      fun () ->
        let r = get ~meth:`POST ~headers:[ ("Origin", "https://hooks.example"); ("Host", "app.example") ] "/hook" in
        check_status r 200;
        let r = get ~meth:`POST "/hook" in
        check_status r 200 );
    ( "config ~origins accepts the public origin behind a proxy",
      fun () ->
        let headers = [ ("Origin", "https://app.example"); ("Host", "internal:8080") ] in
        let r = get ~meth:`PUT ~headers "/thing" in
        check_status r 403;
        let config = config_with ~origins:[ "https://App.Example" ] () in
        let r = get ~config ~meth:`PUT ~headers "/thing" in
        check_status r 200;
        let r = get ~config ~meth:`PUT ~headers:[ ("Origin", "https://internal:8080"); ("Host", "internal:8080") ] "/thing" in
        check_status r 403 );
  ]

let reviewed =
  [
    ( "a handler may send a header name twice",
      fun () ->
        let r = get "/cookies" in
        check_status r 200;
        check_header r "set-cookie" [ "a=1"; "b=2" ];
        check_header r "x-a" [ "mine" ] );
    ( "a header with CR or LF is a 500, not sent",
      fun () ->
        let r = get "/bad-header" in
        check_status r 500;
        check_header r "x-bad" [];
        check_header r "set-cookie" [];
        Alcotest.(check int) "one log" 1 (List.length !logged) );
    ( "a server render of Live.use runs allow with the request",
      fun () ->
        let loads = !App.mine_loads in
        let r = get ~headers:[ ("x-user", "ann") ] "/live" in
        check_true "allowed" (contains r.body "data secret of ann");
        let r = get ~headers:[ ("x-user", "bob") ] "/live" in
        check_true "refused" (contains r.body "forbidden");
        check_true "no state" (not (contains r.body "secret of ann"));
        Alcotest.(check int) "loaded once" (loads + 1) !App.mine_loads );
    ( "actions get the request context",
      fun () ->
        let r =
          get ~meth:`POST
            ~headers:
              [ ("content-type", "application/json"); ("origin", "http://app.example"); ("host", "app.example"); ("x-user", "ana") ]
            ~body:"null" "/_yuka/action/whoami"
        in
        check_status r 200;
        Alcotest.(check string) "body" {|{"ok":"ana cycle-session POST /_yuka/action/whoami"}|} r.body );
    ( "form actions get the request context",
      fun () ->
        let r =
          get ~meth:`POST
            ~headers:
              [ ("content-type", "application/x-www-form-urlencoded"); ("origin", "http://app.example");
                ("host", "app.example"); ("x-user", "ana") ]
            ~body:"_yuka_action=save_entry&title=who&count=1&level=low" "/entry"
        in
        check_status r 303;
        check_header r "location" [ "/entry?saved=ana" ] );
    ( "the handler answers /_yuka/live",
      fun () ->
        let same = [ ("origin", "https://app.example"); ("host", "app.example") ] in
        let r = get ~headers:(("upgrade", "websocket") :: same) "/_yuka/live" in
        check_status r 101;
        let r = get ~headers:[ ("upgrade", "websocket"); ("origin", "https://evil.example"); ("host", "app.example") ] "/_yuka/live" in
        check_status r 403;
        let r = get ~headers:same "/_yuka/live" in
        check_status r 426;
        let r = get ~meth:`POST ~headers:(("upgrade", "websocket") :: same) "/_yuka/live" in
        check_status r 405;
        Alcotest.(check (list string)) "no file" [] !file_calls );
    ( "a server render of Live.use reads the state of the handler's node",
      fun () ->
        let node = Server.Live.node () in
        let inbox = ref [ Some {|{"t":"hello","v":1,"csrf":"t"}|}; Some {|{"t":"sub","id":1,"topic":"cycle-mine","key":"ann"}|} ] in
        let connection =
          Server.Live.connection
            ~send:(fun _ -> Async.return ())
            ~receive:(fun () ->
              match !inbox with
              | x :: rest ->
                  inbox := rest;
                  Async.return x
              | [] -> fst3 (Async.make ()))
            ~close:(fun _ -> Async.return ())
        in
        let ann = Server.Testing.context ~header:(function "x-user" -> Some "ann" | _ -> None) ~session:"s" () in
        ignore
          (Server.Testing.live_run ~node ~sleep:(fun _ -> fst3 (Async.make ())) ann
             ~verify_csrf:(fun _ -> Async.return true) ~token:(fun () -> Some "t") connection);
        Server.Live.publish ~node App.mine "ann" "published on the node";
        let page handler =
          match Async.status handler with Async.Done (r : reply) -> r.body | _ -> Alcotest.fail "pending"
        in
        let r = request ~headers:[ ("x-user", "ann") ] "/live" in
        check_true "the node's state"
          (contains (page (Cycle.handler ~node config Cycle_server.Yuka_routes.app r)) "data published on the node");
        let r = request ~headers:[ ("x-user", "ann") ] "/live" in
        check_true "the default node loads"
          (contains (page (Cycle.handler config Cycle_server.Yuka_routes.app r)) "data secret of ann") );
    ( "a live upgrade without a session is a 500 and a log, before the upgrade",
      fun () ->
        let r =
          get ~headers:[ ("upgrade", "websocket"); ("origin", "https://app.example"); ("host", "app.example"); ("x-no-session", "1") ]
            "/_yuka/live"
        in
        check_status r 500;
        Alcotest.(check int) "one log" 1 (List.length !logged);
        check_true "names the session" (contains (List.hd !logged) "no session");
        check_true "names the middleware" (contains (List.hd !logged) "the live socket needs session middleware") );
    ( "an action reads no session as None",
      fun () ->
        let r =
          get ~meth:`POST
            ~headers:
              [ ("content-type", "application/json"); ("origin", "http://app.example"); ("host", "app.example");
                ("x-user", "ana"); ("x-no-session", "1") ]
            ~body:"null" "/_yuka/action/whoami"
        in
        check_status r 200;
        Alcotest.(check string) "body" {|{"ok":"ana - POST /_yuka/action/whoami"}|} r.body;
        Alcotest.(check (list string)) "no log" [] !logged );
    ( "GET /_yuka/csrf without a session is a 500 and a log",
      fun () ->
        let r = get ~headers:[ ("sec-fetch-site", "same-origin"); ("x-no-session", "1") ] "/_yuka/csrf" in
        check_status r 500;
        Alcotest.(check string) "body" "Internal Server Error" r.body;
        Alcotest.(check int) "one log" 1 (List.length !logged);
        check_true "names the path and the middleware"
          (contains (List.hd !logged) "/_yuka/csrf" && contains (List.hd !logged) "session middleware") );
    ( "a page with Live.use and no session writes the token as an error",
      fun () ->
        let r = get ~headers:[ ("x-user", "ann"); ("x-no-session", "1") ] "/live" in
        check_status r 200;
        check_true "the state" (contains r.body "data secret of ann");
        check_true "no token"
          (contains r.body {|data-yuka-answer="l:csrf">{"error":{"kind":"forbidden"}}</script>|});
        Alcotest.(check (list string)) "one log"
          [ "page with a Live.use: the request has no session; live data needs session middleware" ] !logged );
    ( "a page with live state under a shared cache rule is sent private, no-store",
      fun () ->
        let r = get ~headers:[ ("x-user", "ann") ] "/live-public" in
        check_status r 200;
        check_header r "cache-control" [ "private, no-store" ];
        Alcotest.(check int) "one log" 1 (List.length !logged);
        let r = get ~headers:[ ("x-user", "ann") ] "/live-public" in
        check_header r "cache-control" [ "private, no-store" ];
        Alcotest.(check int) "logged once per path" 0 (List.length !logged);
        let r = get "/plain-public" in
        check_header r "cache-control" [ "public, max-age=60" ];
        let r = get ~headers:[ ("x-user", "ann") ] "/live" in
        check_header r "cache-control" [ "no-store" ] );
    ( "a prerender refuses a page with live state and has no dev script",
      fun () ->
        let pre = Server.Prerender.config (config_with ~dev:true ~assets:modules ()) in
        let r = get ~config:pre ~headers:[ ("x-user", "ann") ] "/live" in
        check_status r 500;
        check_true "no state" (not (contains r.body "secret of ann"));
        check_true "logged" (List.exists (fun m -> contains m "cannot be prerendered") !logged);
        let r = get ~config:pre "/plain" in
        check_status r 200;
        check_true "no dev script" (not (contains r.body "EventSource")) );
    ( "the default live node logs to the config of the handler",
      fun () ->
        ignore (get "/plain");
        let inbox = ref [ Some {|{"t":"hello","v":1,"csrf":"t"}|}; Some {|{"t":"sub","id":1,"topic":"cycle-boom","key":"k"}|} ] in
        let connection =
          Server.Live.connection
            ~send:(fun _ -> Async.return ())
            ~receive:(fun () ->
              match !inbox with
              | x :: rest ->
                  inbox := rest;
                  Async.return x
              | [] -> fst3 (Async.make ()))
            ~close:(fun _ -> Async.return ())
        in
        ignore
          (Server.Testing.live_run ~sleep:(fun _ -> fst3 (Async.make ())) (Server.Testing.context ~session:"s" ())
             ~verify_csrf:(fun _ -> Async.return true) ~token:(fun () -> Some "t") connection);
        check_true "in the config log" (List.exists (fun m -> contains m "boom secret") !logged) );
    ( "the handler's live node marks its action answers",
      fun () ->
        let node = Server.Live.node () in
        ignore (Server.Live.use_bus ~node ~name:"second" (Server.Live.memory_bus (Server.Live.memory ())));
        let headers = [ ("content-type", "application/json"); ("origin", "http://app.example"); ("host", "app.example") ] in
        let r = request ~meth:`POST ~headers ~body:"null" "/_yuka/action/whoami" in
        match Async.status (Cycle.handler ~node config Cycle_server.Yuka_routes.app r) with
        | Async.Done r -> check_true "mark" (contains r.body {|"live":["second",0]|})
        | _ -> Alcotest.fail "pending" );
  ]

let loaders =
  [
    ( "a fallback that fails still answers 500",
      fun () ->
        let a = call (request "/later") in
        log_hook := (fun _ _ -> failwith "log down");
        App.finish_slow "explode";
        match Async.status a with
        | Async.Done r ->
            check_status r 500;
            Alcotest.(check string) "plain" "Internal Server Error" r.body
        | _ -> Alcotest.fail "the request hangs" );
    ( "loader-free layers are built once",
      fun () ->
        let first_layer route =
          match Cycle_server.Yuka_routes.resolve (request "/") route with
          | Server.Generated.Page { load; _ } -> (
              match Async.status (load ()) with
              | Async.Done (Ok plan) -> List.hd plan.layers
              | _ -> Alcotest.fail "no plan")
          | Server.Generated.Handler _ -> Alcotest.fail "not a page"
        in
        let a = first_layer Cycle_shared.Routes.Plain in
        let b = first_layer Cycle_shared.Routes.Home in
        check_true "same value" (a == b) );
    ( "loaders start before either resolves",
      fun () ->
        let a = call (request "/team/wait/1") in
        check_true "pending" (Async.status a = Async.Pending);
        check_events [ "outer"; "inner"; "squad start"; "profile start" ];
        Alcotest.(check int) "two waiting" 2 (List.length !App.waiting);
        List.iter (fun resolve -> resolve ()) !App.waiting;
        match Async.status a with
        | Async.Done r ->
            check_status r 200;
            check_true "both results" (contains r.body "squad late")
        | _ -> Alcotest.fail "not done" );
    ( "loader Not_found is 404 inside the fallback layers",
      fun () ->
        let r = get "/team/a/404" in
        check_status r 404;
        check_header r "cache-control" [ "no-store" ];
        check_header r "x-a" [ "root" ];
        check_true "root layout" (contains r.body {|class="root"|});
        check_true "no team layout" (not (contains r.body {|class="team"|}));
        check_true "page" (contains r.body "missing /team/a/404") );
    ( "loader exception is 500 with no message and one log",
      fun () ->
        let r = get "/boom" in
        check_status r 500;
        check_header r "cache-control" [ "no-store" ];
        check_true "error page" (contains r.body "error page");
        check_true "no message" (not (contains r.body "secret"));
        Alcotest.(check int) "one log" 1 (List.length !logged) );
    ( "failed loader Async is 500",
      fun () ->
        let r = get "/team/a/500" in
        check_status r 500;
        Alcotest.(check (list string)) "log" [ "loader secret" ] !logged );
  ]

let console_calls () =
  Yuka.Console.log "l";
  Yuka.Console.info "i";
  Yuka.Console.warn "w";
  Yuka.Console.error "e";
  Yuka.Console.debug "d"

let leveled got level m =
  let name = match level with `Error -> "error" | `Warn -> "warn" | `Info -> "info" | `Debug -> "debug" in
  got := (name ^ " " ^ m) :: !got

let console_levels = [ "info l"; "info i"; "warn w"; "error e"; "debug d" ]

let render =
  [
    ( "Console during a request goes to the log of the config",
      fun () ->
        let r = request "/" in
        let got = ref [] in
        log_hook := leveled got;
        App.in_home := console_calls;
        (match Async.status (call r) with
        | Async.Done r -> check_status r 200
        | _ -> Alcotest.fail "no response");
        Alcotest.(check (list string)) "levels" console_levels (List.rev !got) );
    ( "Console outside a request goes to the default sink",
      fun () ->
        let got = ref [] in
        Server.Testing.set_log (leveled got);
        console_calls ();
        Server.Testing.set_log (fun _ m -> prerr_endline m);
        Alcotest.(check (list string)) "levels" console_levels (List.rev !got) );
    ( "a failed render waits for the writes in flight",
      fun () ->
        held_writes := [];
        let a = Held.handler config Cycle_server.Yuka_routes.app (request "/slow") in
        let ended =
          match Async.status a with
          | Async.Done r ->
              check_status r.Held_adapter.reply 200;
              r.ended
          | _ -> Alcotest.fail "no response"
        in
        App.finish_slow "explode";
        Alcotest.(check int) "one write held" 1 (List.length !held_writes);
        check_true "not ended while a write is held" (Async.status ended = Async.Pending);
        List.iter (fun (_, resolve) -> resolve ()) !held_writes;
        check_true "ended" (Async.status ended = Async.Done ());
        Alcotest.(check int) "one log" 1 (List.length !logged) );
    ( "a failed render writes nothing after the stream ended",
      fun () ->
        held_writes := [];
        stream_ended := false;
        late_writes := 0;
        let a = Held.handler config Cycle_server.Yuka_routes.app (request "/twice") in
        let ended =
          match Async.status a with
          | Async.Done r -> r.Held_adapter.ended
          | _ -> Alcotest.fail "no response"
        in
        App.finish_slow "ready";
        App.finish_second "explode";
        let rec release n =
          match !held_writes with
          | [] -> n
          | (_, resolve) :: rest ->
              held_writes := rest;
              resolve ();
              if !held_writes <> [] then
                check_true "not ended while a write is held" (Async.status ended = Async.Pending);
              release (n + 1)
        in
        let written = release 0 in
        Alcotest.(check int) "shell and the first fill" 2 written;
        Alcotest.(check int) "no write after the end" 0 !late_writes;
        check_true "ended" (Async.status ended = Async.Done ()) );
    ( "no aria-current inside an island",
      fun () ->
        let r = get "/islands" in
        Alcotest.(check int) "only the layout link" 1 (count r.body "aria-current");
        check_true "outside the island" (index r.body "aria-current" < index r.body "<yuka-island") );
    ( "no module script without islands",
      fun () ->
        let r = get "/plain" in
        check_true "no script" (not (contains r.body "<script type=\"module\""));
        check_true "import map stays" (contains r.body "importmap") );
    ( "0 bytes of JavaScript without islands or fills",
      fun () ->
        let r = get "/plain" in
        Alcotest.(check int) "only the import map script" 1 (count r.body "<script");
        check_true "import map" (contains r.body {|<script type="importmap">|});
        check_true "no fill script" (not (contains r.body "__yukaFill"));
        check_true "no preload" (not (contains r.body "modulepreload")) );
    ( "the fill script is sent when a fill is pending",
      fun () ->
        let a = call (request "/slow") in
        App.finish_slow "ready";
        match Async.status a with
        | Async.Done r ->
            check_true "fill script" (contains r.body Yuka.Private.fill_script);
            check_true "before the shell" (index r.body Yuka.Private.fill_script < index r.body "wait")
        | _ -> Alcotest.fail "not done" );
    ( "one module script, before the first island",
      fun () ->
        let r = get "/islands" in
        Alcotest.(check int) "one" 1 (count r.body "<script type=\"module\"");
        let script = index r.body {|<script type="module" async src="/_yuka/app/app/main.js"></script>|} in
        check_true "found" (script >= 0);
        check_true "before the island" (script < index r.body "<yuka-island");
        check_true "after the content before it" (script > index r.body "before");
        check_true "preload" (contains r.body {|<link rel="modulepreload" href="/_yuka/app/app/counter.js">|}) );
    ( "the module script stays when a Catch drops the first island",
      fun () ->
        let req = request "/islands" in
        App.fail_first := true;
        let r = match Async.status (call req) with Async.Done v -> v | _ -> Alcotest.fail "pending" in
        check_true "fallback" (contains r.body "lost server error");
        check_true "island Counter dropped" (not (contains r.body {|data-name="Counter"|}));
        Alcotest.(check int) "one module script" 1 (count r.body "<script type=\"module\"");
        check_true "before the island" (index r.body "<script type=\"module\"" < index r.body "<yuka-island");
        Alcotest.(check int) "logged" 1 (List.length !logged) );
    ( "outlets nest in layer order",
      fun () ->
        let r = get "/team/a/1" in
        let l0 = index r.body {|<yuka-outlet data-k="L0" style="display:contents">|} in
        let team = index r.body {|class="team"|} in
        let l1 = index r.body {|<yuka-outlet data-k="L1/a" style="display:contents">|} in
        let page = index r.body "a 1 of a" in
        check_true "order" (0 <= l0 && l0 < team && team < l1 && l1 < page);
        let r = get "/team/a%2Fb/1" in
        check_true "key is encoded" (contains r.body {|data-k="L1/a%2Fb"|}) );
    ( "aria-current only on the exact path",
      fun () ->
        let r = get "/plain?x=1" in
        check_true "exact" (contains r.body {|<a href="/plain" aria-current="page">|});
        Alcotest.(check int) "once" 1 (count r.body "aria-current");
        let r = get "/" in
        check_true "home" (contains r.body {|<a href="/" aria-current="page">|});
        Alcotest.(check int) "once" 1 (count r.body "aria-current") );
    ( "title, styles and the document",
      fun () ->
        let r = get "/plain" in
        check_true "doctype" (String.starts_with ~prefix:"<!DOCTYPE html>" r.body);
        check_true "title" (contains r.body "<title>Plain</title>");
        check_true "style" (contains r.body {|<link rel="stylesheet" href="/static/s.css">|});
        check_true "end" (String.ends_with ~suffix:"</body></html>" r.body) );
    ( "streamed fill",
      fun () ->
        let a = call (request "/slow") in
        check_true "pending" (Async.status a = Async.Pending);
        App.finish_slow "ready";
        match Async.status a with
        | Async.Done r ->
            check_status r 200;
            check_true "loading first" (index r.body "wait" < index r.body "<template data-yuka-fill");
            check_true "filled" (contains r.body "ready</template>");
            check_true "end" (String.ends_with ~suffix:"</body></html>" r.body)
        | _ -> Alcotest.fail "not done" );
    ( "error after the first write ends the stream and logs",
      fun () ->
        let a = call (request "/slow") in
        App.finish_slow "explode";
        match Async.status a with
        | Async.Done r ->
            check_status r 200;
            check_true "shell sent" (contains r.body "wait");
            check_true "no end" (not (String.ends_with ~suffix:"</body></html>" r.body));
            Alcotest.(check int) "one log" 1 (List.length !logged)
        | _ -> Alcotest.fail "not done" );
    ( "a settled page is one string, a page with a pending Await streams",
      fun () ->
        let kind target =
          raw_sleep := (fun _ -> fst3 (Async.make ()));
          match Async.status (Raw.handler config Cycle_server.Yuka_routes.app (request target)) with
          | Async.Done { body = Server.String text; status; _ } ->
              Printf.sprintf "string %d %b" status (String.ends_with ~suffix:"</body></html>" text)
          | Async.Done { body = Server.Stream _; status; _ } -> Printf.sprintf "stream %d" status
          | _ -> "other"
        in
        Alcotest.(check string) "settled" "string 200 true" (kind "/plain");
        Alcotest.(check string) "pending" "stream 200" (kind "/slow") );
    ( "a render failure before the shell is written is the 500 page",
      fun () ->
        raw_sleep := (fun _ -> Async.return ());
        let a = Raw.handler config Cycle_server.Yuka_routes.app (request "/slow") in
        match Async.status a with
        | Async.Done r ->
            check_status { status = r.status; headers = r.headers; body = "" } 500;
            check_header { status = r.status; headers = r.headers; body = "" } "cache-control" [ "no-store" ];
            Alcotest.(check int) "one log" 1 (List.length !logged)
        | _ -> Alcotest.fail "no response" );
    ( "shell exception is the 500 page",
      fun () ->
        let r = get "/broken" in
        check_status r 500;
        check_true "error page" (contains r.body "error page");
        check_true "no message" (not (contains r.body "secret"));
        Alcotest.(check (list string)) "log" [ "Failure(\"shell secret\")" ] !logged );
    ( "Yuka-Navigate gives the settled document",
      fun () ->
        let a = call (request ~headers:[ ("Yuka-Navigate", "1") ] "/slow") in
        check_true "waits for the fill" (Async.status a = Async.Pending);
        App.finish_slow "ready";
        match Async.status a with
        | Async.Done r ->
            check_true "doctype" (String.starts_with ~prefix:"<!DOCTYPE html>" r.body);
            check_true "settled" (contains r.body "ready");
            check_true "no fill script" (not (contains r.body "__yukaFill"))
        | _ -> Alcotest.fail "not done" );
  ]

let navigation =
  let nav keys target = get ~headers:[ ("Yuka-Navigate", keys) ] target in
  let build = Server.Adapter.build_id config Cycle_server.Yuka_routes.app in
  [
    ( "shared root layout: partial with the page body",
      fun () ->
        let r = nav "L0" "/plain" in
        check_status r 200;
        check_header r "yuka-outlet" [ "L0" ];
        check_header r "yuka-build" [ build ];
        check_header r "yuka-title" [ "Plain" ];
        check_header r "content-type" [ "text/html; charset=utf-8" ];
        check_header r "vary" [ "Yuka-Navigate, Yuka-Prefetch" ];
        check_header r "x-frame-options" [ "DENY" ];
        Alcotest.(check string) "body" "<p>plain</p>" r.body );
    ( "the deepest shared layout is the outlet",
      fun () ->
        let r = nav "L0 L2/acme" "/org/acme/x/2" in
        check_header r "yuka-outlet" [ "L2/acme" ];
        check_true "no org layout" (not (contains r.body {|class="org"|}));
        check_true "page" (contains r.body "acme 2 item") );
    ( "a layout that takes a loader result is rendered again",
      fun () ->
        let r = nav "L0 L1/a" "/team/a/2" in
        check_header r "yuka-outlet" [ "L0" ];
        check_true "team layout with fresh data" (contains r.body {|<section class="team">squad of a|});
        check_true "page" (contains r.body "a 2 of a");
        let r = nav "L0 L1/a" "/team/b/1" in
        check_header r "yuka-outlet" [ "L0" ];
        check_true "team layout again" (contains r.body {|<yuka-outlet data-k="L1/b" style="display:contents">|}) );
    ( "unknown, empty or old keys give a full document with the build",
      fun () ->
        List.iter
          (fun keys ->
            let r = nav keys "/plain" in
            check_header r "yuka-outlet" [];
            check_header r "yuka-build" [ build ];
            check_true "document" (String.starts_with ~prefix:"<!DOCTYPE html>" r.body);
            check_true "meta" (contains r.body ({|<meta name="yuka-build" content="|} ^ build ^ {|">|})))
          [ "X0"; ""; "-"; "1"; "L1/a" ] );
    ( "ids in a partial start with the outlet key",
      fun () ->
        let r = nav "L0" "/islands" in
        check_true "island id" (contains r.body {|data-id="L0-i1"|});
        check_true "props id" (contains r.body {|data-yuka-props="L0-i2"|});
        check_true "no module script" (not (contains r.body "<script type=\"module\""));
        check_true "no bare id" (not (contains r.body {|data-id="i1"|})) );
    ( "a 404 partial keeps its status",
      fun () ->
        let r = nav "L0" "/nowhere" in
        check_status r 404;
        check_header r "yuka-outlet" [ "L0" ];
        check_header r "cache-control" [ "no-store" ];
        check_true "page" (contains r.body "missing /nowhere") );
    ( "the title header is percent-encoded UTF-8",
      fun () ->
        let r = nav "L0" "/find" in
        check_header r "yuka-title" [ "Caf%C3%A9%20%E2%9C%93" ] );
    ( "a streamed document has the build meta",
      fun () ->
        let r = get "/plain" in
        check_true "meta" (contains r.body ({|<meta name="yuka-build" content="|} ^ build ^ {|">|}));
        check_header r "yuka-build" [] );
    ( "the build id follows the assets",
      fun () ->
        let app = Cycle_server.Yuka_routes.app in
        let with_assets ~manifest ~digest =
          config_with
            ~assets:(ok (Server.modules ~dir:"js" ~entry:"./app/main.js" ~manifest ~packages:[ "pkg" ] ~digest))
            ()
        in
        let other = with_assets ~manifest:{|{"Counter":"./related.js"}|} ~digest:"d1" in
        check_true "differs" (Server.Adapter.build_id other app <> build);
        let new_code = with_assets ~manifest:{|{"Counter":"./counter.js"}|} ~digest:"d2" in
        check_true "new file content, new id" (Server.Adapter.build_id new_code app <> build);
        check_true "stable" (Server.Adapter.build_id config app = build) );
  ]

let forms =
  let form_type = ("content-type", "application/x-www-form-urlencoded") in
  let json_headers = [ ("content-type", "application/json"); ("origin", "http://app.example"); ("host", "app.example") ] in
  let post ?(headers = [ form_type; ("origin", "http://app.example"); ("host", "app.example") ]) ?(target = "/entry") body =
    App.saved := [];
    get ~meth:`POST ~headers ~body target
  in
  [
    ( "a valid post is 303 to the redirect",
      fun () ->
        let r = post "_yuka_action=save_entry&title=hello+there&count=2&level=low" in
        check_status r 303;
        check_header r "location" [ "/entry?saved=hello there" ];
        check_header r "cache-control" [ "no-store" ];
        Alcotest.(check (list string)) "called" [ "hello there" ] !App.saved );
    ( "without a redirect it is 303 to the page URL",
      fun () ->
        let r = post ~target:"/entry?x=1" "_yuka_action=jot&body=hi" in
        check_status r 303;
        check_header r "location" [ "/entry?x=1" ] );
    ( "a bad field is 422 with the values and errors, and no call",
      fun () ->
        let r = post "_yuka_action=save_entry&title=keep+me&count=abc&level=low" in
        check_status r 422;
        check_header r "cache-control" [ "no-store" ];
        Alcotest.(check (list string)) "not called" [] !App.saved;
        check_true "value kept" (contains r.body {|name="title" value="keep me"|});
        check_true "bad value kept" (contains r.body {|name="count" value="abc"|});
        check_true "error" (contains r.body "count error: Not a whole number");
        check_true "the jot forms are empty" (contains r.body {|name="body" value=""|});
        check_true "no JavaScript" (not (contains r.body "<script type=\"module\"" || contains r.body "__yukaFill")) );
    ( "Error and reject show their messages",
      fun () ->
        let r = post "_yuka_action=save_entry&title=taken&count=1&level=low" in
        check_status r 422;
        check_true "field error" (contains r.body "title error: Taken");
        let r = post "_yuka_action=save_entry&title=nope&count=1&level=low" in
        check_status r 422;
        check_true "form error" (contains r.body "form error: Refused") );
    ( "a failure is the 500 page",
      fun () ->
        let r = post "_yuka_action=save_entry&title=boom&count=1&level=low" in
        check_status r 500;
        check_true "no detail" (not (contains r.body "secret boom")) );
    ( "origin checks",
      fun () ->
        let r = post ~headers:[ form_type; ("origin", "https://evil.example"); ("host", "app.example") ] "_yuka_action=jot&body=x" in
        check_status r 403;
        let r = post ~headers:[ form_type; ("host", "app.example") ] "_yuka_action=jot&body=x" in
        check_status r 403;
        let r = post ~headers:[ form_type; ("sec-fetch-site", "same-origin") ] "_yuka_action=jot&body=y" in
        check_status r 303 );
    ( "a foreign origin is refused without reading the body",
      fun () ->
        body_read := 0;
        let r =
          post ~headers:[ form_type; ("origin", "https://evil.example"); ("host", "app.example") ] (String.make 10_000 'a')
        in
        check_status r 403;
        Alcotest.(check int) "body not read" 0 !body_read;
        check_header r "x-frame-options" [ "DENY" ] );
    ( "an oversize body is 413 without reading past the limit",
      fun () ->
        body_read := 0;
        let r = post ("_yuka_action=jot&body=" ^ String.make (3 * 1024 * 1024) 'a') in
        check_status r 413;
        check_true "stopped near the limit" (!body_read <= (1024 * 1024) + 4096) );
    ( "the action RPC reads a bounded body too",
      fun () ->
        body_read := 0;
        let r =
          get ~meth:`POST ~headers:json_headers ~body:(String.make (3 * 1024 * 1024) ' ') "/_yuka/action/jot"
        in
        check_status r 413;
        check_true "stopped near the limit" (!body_read <= (1024 * 1024) + 4096);
        let r = get ~meth:`POST ~headers:json_headers ~body:{|[["body","hello"]]|} "/_yuka/action/jot" in
        check_status r 200;
        Alcotest.(check string) "answer" {|{"ok":{"value":5}}|} r.body );
    ( "foreign origin to the action endpoint reads 0 bytes",
      fun () ->
        let refused name headers status =
          body_read := 0;
          let r = get ~meth:`POST ~headers ~body:(String.make 10_000 ' ') ("/_yuka/action/" ^ name) in
          check_status r status;
          Alcotest.(check int) (name ^ " body not read") 0 !body_read
        in
        refused "jot" [ ("content-type", "application/json"); ("origin", "https://evil.example"); ("host", "app.example") ] 403;
        refused "jot" [ ("content-type", "application/json"); ("host", "app.example") ] 403;
        refused "nobody" json_headers 404;
        refused "jot" [ form_type; ("origin", "http://app.example"); ("host", "app.example") ] 415 );
    ( "a redirect that is not a path on this site is 500 and logged",
      fun () ->
        let r = post "_yuka_action=save_entry&title=http%3A%2F%2Fapp.example%2Fdone&count=1&level=low" in
        check_status r 303;
        check_header r "location" [ "http://app.example/done" ];
        let r = post "_yuka_action=save_entry&title=HTTPS%3A%2F%2Fapp.example%2Fdone&count=1&level=low" in
        check_status r 303;
        check_header r "location" [ "HTTPS://app.example/done" ];
        List.iter
          (fun title ->
            let r = post ("_yuka_action=save_entry&count=1&level=low&title=" ^ title) in
            check_status r 500;
            check_true "no location" (not (List.mem_assoc "location" r.headers));
            Alcotest.(check int) "logged" 1 (List.length !logged))
          [
            "a%0D%0ASet-Cookie%3A+x%3D1";
            "https%3A%2F%2Fevil.example%2Fx";
            "http%3A%2F%2Fapp.example.evil%2F";
            "%2F%09%2Fevil.com";
            "%2F%0A%2Fevil.com";
            "%2F%0D%2Fevil.com";
            "%2F%7F%2Fevil.com";
            "%2Fok%00";
            "%09%2F%2Fevil.com";
            "javascript%3A%2F%2Fapp.example%2F%250aalert(1)";
            "JavaScript%3A%2F%2Fapp.example%2F%250aalert(1)";
            "data%3A%2F%2Fapp.example%2Fx";
            "ftp%3A%2F%2Fapp.example%2Fx";
          ] );
    ( "the action RPC answer of a form refuses a redirect that is not a path on this site",
      fun () ->
        let call title =
          logged := [];
          get ~meth:`POST ~headers:json_headers
            ~body:(Printf.sprintf {|[["title",%S],["count","1"],["level","low"]]|} title)
            "/_yuka/action/save_entry"
        in
        let r = call "http://app.example/done" in
        check_status r 200;
        Alcotest.(check string) "same site" {|{"ok":{"value":"http://app.example/done","redirect":"http://app.example/done"}}|} r.body;
        List.iter
          (fun title ->
            let r = call title in
            check_status r 500;
            Alcotest.(check string) ("answer " ^ String.escaped title) {|{"error":"action failed"}|} r.body;
            Alcotest.(check int) "logged" 1 (List.length !logged))
          [
            "javascript:alert(1)";
            " javascript:alert(1)";
            "https://evil.example/x";
            "//evil.example";
            "/\\evil.example";
            "javascript://app.example/%0aalert(1)";
            "JAVASCRIPT://app.example/%0aalert(1)";
            "data://app.example/x";
          ] );
    ( "page guards run before the action",
      fun () ->
        let r = post ~target:"/team/nobody/form" "_yuka_action=jot&body=hi" in
        check_status r 404;
        Alcotest.(check (list string)) "not called" [] !App.saved;
        let r = post ~target:"/team/away/form" "_yuka_action=jot&body=hi" in
        check_status r 303;
        check_header r "location" [ "/" ];
        Alcotest.(check (list string)) "not called" [] !App.saved;
        let r = post ~target:"/team/a/form" "_yuka_action=jot&body=hi" in
        check_status r 303;
        check_header r "location" [ "/team/a/form" ];
        Alcotest.(check (list string)) "called" [ "jot hi" ] !App.saved );
    ( "the rule headers are on the 303",
      fun () ->
        let r = post "_yuka_action=jot&body=hi" in
        check_header r "x-frame-options" [ "DENY" ];
        check_header r "x-a" [ "root" ] );
    ( "only the posted form gets the 422 state",
      fun () ->
        let r = post "_yuka_action=jot&_yuka_key=two&body=x" in
        check_status r 422;
        check_true "form two" (contains r.body "jot two error: Too short");
        check_true "form two value" (contains r.body {|value="x"|});
        check_true "not form one" (not (contains r.body "jot one error")) );
    ( "unknown form action is 404",
      fun () ->
        let r = post "_yuka_action=nobody&x=1" in
        check_status r 404 );
    ( "a post that is not a form post stays 405",
      fun () ->
        let r = post "title=x" in
        check_status r 405;
        check_header r "allow" [ "GET, HEAD, OPTIONS" ];
        let r = post ~headers:[ ("content-type", "application/json") ] "{}" in
        check_status r 405;
        let r = post ~target:"/team/nobody/form" ~headers:[ ("content-type", "text/plain") ] "_yuka_action=jot&body=x" in
        check_status r 405;
        check_events [];
        let r = post ~target:"/feed.xml" "_yuka_action=jot&body=x" in
        check_status r 405 );
    ( "GET and HEAD of the form page are unchanged",
      fun () ->
        let r = get "/entry" in
        check_status r 200;
        check_true "form" (contains r.body {|<form method="post" data-yuka-action="save_entry" data-yuka-key=""><input type="hidden" name="_yuka_action" value="save_entry">|});
        check_true "no action attribute" (not (contains r.body "<form action"));
        let h = get ~meth:`HEAD "/entry" in
        check_status h 200;
        Alcotest.(check string) "no body" "" h.body );
  ]

let dev =
  let with_dev ?file ?(make = fun () -> config_with ~dev:true ()) f =
    Unix.putenv "YUKA_DEV_FILE" (Option.value file ~default:"/nonexistent/yuka-dev");
    f (make ())
  in
  let state_file text =
    let f = Filename.temp_file "yuka_dev" "" in
    Out_channel.with_open_bin f (fun oc -> output_string oc text);
    f
  in
  let timers = ref [] in
  let sleep _ =
    let a, resolve, _ = Async.make () in
    timers := !timers @ [ resolve ];
    a
  in
  let tick () =
    let due = !timers in
    timers := [];
    List.iter (fun resolve -> resolve ()) due
  in
  let stream ?(meth = `GET) ?(write = fun _ -> Async.return ()) config target =
    raw_sleep := sleep;
    match Async.status (Raw.handler config Cycle_server.Yuka_routes.app (request ~meth target)) with
    | Async.Done { status; headers; body = Server.Stream f } ->
        let written = ref [] in
        ignore (f (fun s -> written := !written @ [ s ]; write s));
        (status, headers, written)
    | Async.Done { status; headers; body = Server.String s } -> (status, headers, ref [ s ])
    | _ -> Alcotest.fail "no response"
  in
  [
    ( "without ~dev: no /_yuka/dev and no script, even with YUKA_DEV=1",
      fun () ->
        Unix.putenv "YUKA_DEV" "1";
        let config = Fun.protect ~finally:(fun () -> Unix.putenv "YUKA_DEV" "") (fun () -> config_with ()) in
        let r = get ~config "/_yuka/dev" in
        check_status r 404;
        check_true "no script" (not (contains (get ~config "/plain").body "/_yuka/dev")) );
    ( "with ~dev: the events of the state file",
      fun () ->
        let file = state_file {|{"build":1,"page":1,"error":null}|} in
        with_dev ~file (fun config ->
            timers := [];
            let status, headers, written = stream config "/_yuka/dev" in
            Alcotest.(check int) "status" 200 status;
            Alcotest.(check (option string)) "type" (Some "text/event-stream") (List.assoc_opt "content-type" headers);
            Alcotest.(check (list string)) "first event" [ {|data: {"build":1,"page":1,"error":null}|} ^ "\n\n" ] !written;
            tick ();
            Alcotest.(check int) "no event without a change" 1 (List.length !written);
            Out_channel.with_open_bin file (fun oc -> output_string oc {|{"build":2,"page":1,"error":null}|});
            tick ();
            Alcotest.(check string) "css change" ({|data: {"build":2,"page":1,"error":null}|} ^ "\n\n") (List.nth !written 1);
            Out_channel.with_open_bin file (fun oc -> output_string oc "{\"build\":2,\"page\":1,\n\"error\":\"boom\"}");
            tick ();
            Alcotest.(check string) "error, on one line" ({|data: {"build":2,"page":1, "error":"boom"}|} ^ "\n\n") (List.nth !written 2);
            let r = get ~config ~meth:`POST "/_yuka/dev" in
            check_status r 405) );
    ( "with ~dev: a heartbeat, an end on a failed write, HEAD without a loop",
      fun () ->
        let file = state_file {|{"build":1}|} in
        with_dev ~file (fun config ->
            timers := [];
            let _, _, written = stream config "/_yuka/dev" in
            for _ = 1 to 60 do tick () done;
            Alcotest.(check (list string)) "a comment after 15 s without a change"
              [ {|data: {"build":1}|} ^ "\n\n"; ": ping\n\n" ] !written;
            timers := [];
            let failing, _, fail = Async.make () in
            let _, _, written = stream ~write:(fun _ -> failing) config "/_yuka/dev" in
            Alcotest.(check int) "one write in flight" 1 (List.length !written);
            fail "closed";
            Alcotest.(check int) "no timer after a failed write" 0 (List.length !timers);
            timers := [];
            let status, headers, body = stream ~meth:`HEAD config "/_yuka/dev" in
            Alcotest.(check int) "HEAD status" 200 status;
            Alcotest.(check (option string)) "HEAD type" (Some "text/event-stream") (List.assoc_opt "content-type" headers);
            Alcotest.(check (list string)) "HEAD body" [ "" ] !body;
            Alcotest.(check int) "HEAD starts no loop" 0 (List.length !timers)) );
    ( "the dev stream ends when the state cannot be read",
      fun () ->
        timers := [];
        let calls = ref 0 in
        let state () =
          incr calls;
          if !calls = 1 then {|{"build":1}|} else failwith "state gone"
        in
        let logged = ref [] in
        Server.Testing.set_log (fun _ m -> logged := m :: !logged);
        let ended = Yuka.Private.dev_events ~state ~sleep (fun _ -> Async.return ()) in
        (try tick () with _ -> ());
        Server.Testing.set_log (fun _ m -> prerr_endline m);
        check_true "ended" (Async.status ended = Async.Done ());
        Alcotest.(check int) "logged once" 1 (List.length !logged);
        Alcotest.(check int) "no timer left" 0 (List.length !timers) );
    ( "with ~dev: prerendered pages render live; without it, the file",
      fun () ->
        with_dev
          ~make:(fun () -> config_with ~dev:true ~assets:modules ~prerendered:"pre" ())
          (fun config ->
            let r = get ~config "/plain" in
            check_true "rendered, not the file" (not (String.equal r.body "prerendered plain"));
            check_true "with the script" (contains r.body "EventSource");
            let r = get ~config:(config_with ~assets:modules ~prerendered:"pre" ()) "/plain" in
            check_true "without dev: the file" (String.equal r.body "prerendered plain")) );
    ( "with ~dev: the script in full pages only",
      fun () ->
        let file = state_file {|{"build":3,"page":2,"error":"<\/script>"}|} in
        with_dev ~file (fun config ->
            let page = (get ~config "/plain").body in
            check_true "script in the head" (index page "new EventSource(\"/_yuka/dev\")" < index page "</head>");
            check_true "state in the script, < escaped" (contains page {|var s={"build":3,"page":2,"error":"\u003c\/script>"}|});
            let partial = get ~config ~headers:[ ("Yuka-Navigate", "L0") ] "/plain" in
            check_header partial "yuka-outlet" [ "L0" ];
            check_true "no script in a partial answer" (not (contains partial.body "EventSource"));
            let full = get ~config ~headers:[ ("Yuka-Navigate", "") ] "/plain" in
            check_true "no script in a navigation answer" (not (contains full.body "EventSource"))) );
  ]

let prefetch =
  let nav ?(trigger = []) target = get ~headers:([ ("yuka-navigate", "-") ] @ trigger) target in
  let trigger v = [ ("yuka-prefetch", v) ] in
  let refused r level =
    check_status r 204;
    check_header r "yuka-prefetch" [ level ];
    Alcotest.(check string) "no body" "" r.body;
    check_header r "cache-control" [ "no-store" ];
    check_header r "vary" [ "Yuka-Navigate, Yuka-Prefetch" ];
    check_events []
  in
  let highest ?cache ?(headers = []) pages =
    let app =
      Server.Generated.app ~build:"b" ~headers:[] ~prerender:[]
        ~pages:(List.map (fun prefetch -> Server.Generated.rules ~headers:[ headers ] ?cache ?prefetch ~prerender:false ()) pages)
        ~find:Cycle_shared.Routes.find ~resolve:Cycle_server.Yuka_routes.resolve
        ~missing:{ layers = []; not_found = Server.Generated.default_not_found; error = Server.Generated.default_error }
    in
    let page = Cycle.handler config app (request "/plain") in
    match Async.status page with Async.Done r -> r.body | _ -> Alcotest.fail "no page"
  in
  [
    ( "a visible trigger on a Hover route: 204 with the level, before guards and loaders",
      fun () -> refused (nav ~trigger:(trigger "visible") "/team/a/1") "hover" );
    ( "a trajectory trigger on a Hover route: 204 hover, no guard or loader",
      fun () -> refused (nav ~trigger:(trigger "trajectory") "/team/a/1") "hover" );
    ( "a trajectory trigger on a Trajectory or a Visible route is answered",
      fun () ->
        check_status (nav ~trigger:(trigger "trajectory") "/plain") 200;
        check_status (nav ~trigger:(trigger "trajectory") "/plain-public") 200 );
    ( "a route with no ~prefetch in the tree has level Trajectory",
      fun () -> refused (nav ~trigger:(trigger "visible") "/plain") "trajectory" );
    ( "a hover trigger on a Hover route is answered",
      fun () ->
        let r = nav ~trigger:(trigger "hover") "/team/a/1" in
        check_status r 200;
        check_events [ "outer"; "inner"; "squad start"; "profile start" ] );
    ( "any trigger on an Off route: 204 off",
      fun () ->
        refused (nav ~trigger:(trigger "hover") "/team/a/form") "off";
        refused (nav ~trigger:(trigger "visible") "/team/a/form") "off" );
    ( "no Yuka-Prefetch is never refused",
      fun () ->
        check_status (nav "/team/a/form") 200;
        check_status (get "/team/a/form") 200 );
    ( "an unknown trigger counts as visible",
      fun () ->
        List.iter (fun v -> refused (nav ~trigger:(trigger v) "/team/a/1") "hover") [ "1"; ""; "off"; "Hover"; "idle" ];
        check_status (nav ~trigger:(trigger "1") "/plain-public") 200;
        check_status (nav ~trigger:(trigger "visible") "/plain-public") 200 );
    ( "a prefetch of an endpoint or an action: 204 off, no guard or handler",
      fun () ->
        List.iter (fun v -> refused (nav ~trigger:(trigger v) "/team/a/json") "off") [ "hover"; "trajectory"; "visible" ];
        refused (get ~meth:`POST ~headers:(trigger "hover") "/team/a/rename") "off" );
    ( "an endpoint with no Yuka-Prefetch is answered",
      fun () ->
        check_status (nav "/team/a/json") 200;
        check_events [ "outer"; "team json" ] );
    ( "a redirect and a 404 are answered as today",
      fun () ->
        check_status (nav ~trigger:(trigger "visible") "/old") 308;
        check_status (nav ~trigger:(trigger "visible") "/nowhere") 404 );
    ( "a page answer varies on Yuka-Prefetch",
      fun () ->
        check_header (nav ~trigger:(trigger "hover") "/team/a/1") "vary" [ "Yuka-Navigate, Yuka-Prefetch" ];
        check_header (get "/plain") "vary" [ "Yuka-Navigate, Yuka-Prefetch" ] );
    ( "a prerendered file: a refused trigger gets 204, an allowed one the file",
      fun () ->
        let prerendered = config_with ~assets:modules ~prerendered:"pre" () in
        let r = get ~config:prerendered ~headers:(trigger "visible") "/plain" in
        check_status r 204;
        Alcotest.(check (list string)) "no file" [] !file_calls;
        let r = get ~config:prerendered ~headers:(trigger "hover") "/plain" in
        Alcotest.(check string) "the file" "prerendered plain" r.body;
        check_header r "vary" [ "Yuka-Navigate, Yuka-Prefetch" ] );
    ( "the page prints the highest level of the tree",
      fun () ->
        check_true "idle" (contains (get "/plain").body {|<meta name="yuka-prefetch" content="idle">|});
        check_true "in a navigation document"
          (contains (get ~headers:[ ("Yuka-Navigate", "-") ] "/plain").body {|<meta name="yuka-prefetch" content="idle">|});
        check_true "off" (contains (highest [ Some `Off; Some `Off ]) {|<meta name="yuka-prefetch" content="off">|});
        check_true "no page route: off" (contains (highest []) {|<meta name="yuka-prefetch" content="off">|});
        List.iter
          (fun pages -> check_true "trajectory is not printed" (not (contains (highest pages) "yuka-prefetch")))
          [ [ None ]; [ Some `Off; None ]; [ Some `Trajectory; Some `Off ] ];
        check_true "hover" (contains (highest [ Some `Hover; Some `Off ]) {|<meta name="yuka-prefetch" content="hover">|});
        check_true "visible wins" (contains (highest [ Some `Off; Some `Visible; None ]) {|content="visible"|}) );
    ( "an idle trigger on an Idle route with a max-age is answered and runs the loader",
      fun () ->
        let r = nav ~trigger:(trigger "idle") "/team/a/idle/1" in
        check_status r 200;
        check_events [ "outer"; "inner"; "squad start"; "profile start" ] );
    ( "hover, trajectory and visible triggers on an Idle route are answered",
      fun () ->
        List.iter
          (fun v -> check_status (nav ~trigger:(trigger v) "/team/a/idle/1") 200)
          [ "hover"; "trajectory"; "visible" ] );
    ( "an idle trigger on a Visible or lower route: 204 with the level, no loader",
      fun () ->
        refused (nav ~trigger:(trigger "idle") "/plain-public") "visible";
        refused (nav ~trigger:(trigger "idle") "/plain") "trajectory";
        refused (nav ~trigger:(trigger "idle") "/team/a/1") "hover";
        refused (nav ~trigger:(trigger "idle") "/team/a/form") "off" );
    ( "a route that says Idle with a cache without max-age has level Visible",
      fun () ->
        refused (nav ~trigger:(trigger "idle") "/team/a/uncached") "visible";
        check_status (nav ~trigger:(trigger "visible") "/team/a/uncached") 200;
        let demoted cache = highest ~cache [ Some `Idle; Some `Hover ] in
        List.iter
          (fun cache ->
            check_true "the meta says visible" (contains (demoted cache) {|<meta name="yuka-prefetch" content="visible">|}))
          [ Server.no_store; Server.no_cache; Server.private_ ~max_age:0 ];
        check_true "no cache rule: visible"
          (contains (highest [ Some `Idle ]) {|<meta name="yuka-prefetch" content="visible">|}) );
    ( "a Cache-Control in ~headers decides the level of an Idle route",
      fun () ->
        refused (nav ~trigger:(trigger "idle") "/team/a/headed") "visible";
        check_true "no-store in ~headers over a lasting ~cache: visible"
          (contains
             (highest ~headers:[ ("Cache-Control", "no-store") ] ~cache:(Server.public ~max_age:60 ()) [ Some `Idle ])
             {|<meta name="yuka-prefetch" content="visible">|});
        check_true "a lasting Cache-Control in ~headers and no ~cache: idle"
          (contains
             (highest ~headers:[ ("cache-control", "public, max-age=60") ] [ Some `Idle ])
             {|<meta name="yuka-prefetch" content="idle">|}) );
    ( "a prefetch of a static file: 204 off, the file is not read",
      fun () ->
        let css = config_with ~assets:modules ~public:[ ("/static", "pub") ] ~css:[ ("a-1.css", ".a{}") ] () in
        List.iter
          (fun target ->
            List.iter
              (fun v -> refused (get ~config:css ~headers:(trigger v) target) "off")
              [ "hover"; "idle" ];
            Alcotest.(check (list string)) ("no file for " ^ target) [] !file_calls)
          [ "/static/s.css"; "/_yuka/app/app/main.js"; "/_yuka/css/a-1.css" ];
        let r = get "/static/s.css" in
        check_status r 200;
        Alcotest.(check string) "with no Yuka-Prefetch the file is served" "css" r.body );
    ( "the meta says idle when an Idle route has a max-age",
      fun () ->
        check_true "idle wins"
          (contains
             (highest ~cache:(Server.public ~max_age:60 ()) [ Some `Visible; Some `Idle; None ])
             {|<meta name="yuka-prefetch" content="idle">|}) );
  ]

let cases tests = List.map (fun (name, f) -> Alcotest.test_case name `Quick f) tests

let () =
  Alcotest.run "cycle"
    [
      ("dev", cases dev);
      ("assets", cases assets);
      ("prerender", cases prerender);
      ("normalize", cases normalize);
      ("match", cases matching);
      ("head and rules", cases head_and_rules);
      ("guards", cases guards);
      ("review", cases reviewed);
      ("loaders", cases loaders);
      ("render", cases render);
      ("navigation", cases navigation);
      ("forms", cases forms);
      ("prefetch", cases prefetch);
    ]
