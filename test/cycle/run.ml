module Async = Yuka.Async
module Server = Yuka.Server
module App = Cycle_server.App

type reply = { status : int; headers : (string * string) list; body : string }

let files = [ ("pre/plain/index.html", "prerendered plain"); ("js/app/main.js", "main"); ("pub/s.css", "css"); ("b/bundle/chunk-X1.js", "c"); ("b/bundle/main.js", "m") ]
let file_calls = ref []
let body_read = ref 0

module Test_adapter = struct
  type request = App.req
  type response = reply
  type 'a io = 'a Async.t

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

  let csrf_token (_ : request) = "cycle-token"

  let respond (r : Server.http_response) =
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

  let of_async a = a
  let bind = Async.bind

  let sleep _ =
    let a, _, _ = Async.make () in
    a
end

module H = Server.Make (Test_adapter)

let held_writes : (string * (unit -> unit)) list ref = ref []
let stream_ended = ref false
let late_writes = ref 0

module Held_adapter = struct
  include Test_adapter

  type response = { reply : reply; ended : unit Async.t }

  let respond (r : Server.http_response) =
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
end

module Held = Server.Make (Held_adapter)

let modules =
  Server.modules ~dir:"js" ~entry:"./app/main.js" ~manifest:{|{"A":"./a.js"}|} ~digest:"d1"
    ~packages:[ "pkg" ]

let config =
  Server.config ~assets:modules ~public:[ ("/static", "pub") ] ~styles:[ "/static/s.css" ] ()

let logged = ref []

let request ?(meth = `GET) ?(headers = []) ?(body = "") target =
  App.reset ();
  logged := [];
  file_calls := [];
  Server.log_error := (fun m -> logged := m :: !logged);
  { App.meth; target; headers; body }

let fst3 (a, _, _) = a

let call ?(config = config) r = H.handler config Cycle_server.Routes_server.app r

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
            match Server.config ~public:[ (prefix, "pub") ] () with
            | _ -> Alcotest.failf "prefix %S accepted" prefix
            | exception Invalid_argument _ -> ())
          [ "/"; ""; "//" ] );
    ( "a metafile without outputs is rejected",
      fun () ->
        match Server.bundle ~dir:"b" ~entry:"main.js" ~manifest:"{}" ~metafile:"{}" with
        | _ -> Alcotest.fail "accepted"
        | exception Invalid_argument m -> check_true "context" (contains m "metafile") );
    ( "asset miss is 404 no-store and never routed",
      fun () ->
        let r = get "/_yuka/nope.js" in
        check_status r 404;
        check_header r "cache-control" [ "no-store" ];
        check_events [];
        Alcotest.(check (list string)) "file asked" [ "js/nope.js" ] !file_calls );
    ( "css sheets are served immutable, a missing one is 404 no-store",
      fun () ->
        let config =
          Server.config ~assets:modules ~css:[ ("a-1234.css", ".a_1234{}") ] ()
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
          "css_files" [ ("_yuka/css/a-1234.css", ".a_1234{}") ] (Server.css_files config) );
    ( "css names are decoded, other methods are 405, bad names are refused",
      fun () ->
        let config = Server.config ~css:[ ("a b.css", "x") ] () in
        let r = get ~config "/_yuka/css/a%20b.css" in
        check_status r 200;
        Alcotest.(check string) "body" "x" r.body;
        let r = get ~config ~meth:`POST "/_yuka/css/a%20b.css" in
        check_status r 405;
        check_header r "allow" [ "GET, HEAD" ];
        List.iter
          (fun name ->
            match Server.config ~css:[ (name, "x") ] () with
            | _ -> Alcotest.failf "css name %S accepted" name
            | exception Invalid_argument _ -> ())
          [ "../../x.css"; "a/b.css"; ""; ".."; "a\\b.css" ] );
    ( "asset file with no-cache",
      fun () ->
        let r = get "/_yuka/app/main.js" in
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
          [ "/_yuka/../secret"; "/_yuka/%2e%2e/secret"; "/_yuka/a/%2F..%2Fx"; "/static/./s.css"; "/_yuka" ] );
    ( "asset methods",
      fun () ->
        let r = get ~meth:`POST "/_yuka/app/main.js" in
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
        let r = get ~config:(Server.config ()) "/_yuka/app/main.js" in
        check_status r 404;
        Alcotest.(check (list string)) "no file" [] !file_calls );
    ( "bundle outputs other than the entry are immutable",
      fun () ->
        let bundle =
          Server.bundle ~dir:"b" ~entry:"bundle/main.js" ~manifest:"{}"
            ~metafile:{|{"outputs":{"bundle/main.js":{"entryPoint":"main.js"},"bundle/chunk-X1.js":{}}}|}
        in
        let config = Server.config ~assets:bundle () in
        let r = get ~config "/_yuka/bundle/chunk-X1.js" in
        check_header r "cache-control" [ "public, max-age=31536000, immutable" ];
        let r = get ~config "/_yuka/bundle/main.js" in
        check_header r "cache-control" [ "no-cache" ] );
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
  let prerendered = Server.config ~assets:modules ~public:[ ("/static", "pub") ] ~prerendered:"pre" () in
  let app = Cycle_server.Routes_server.app in
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
          [ (prerendered, "/plain", 200); (config, "/_yuka/app/main.js", 200);
            (config, "/static/s.css", 200); (config, "/_yuka/nope.js", 404) ];
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
        Alcotest.(check (list string)) "seeds" [ "/plain"; "/feed.xml" ] (Server.prerender_seeds app);
        let req = request "/" in
        List.iter
          (fun (path, expected) -> Alcotest.(check bool) path expected (Server.prerenderable config app req path))
          [ ("/plain", true); ("/plain?x=1#y", true); ("/feed.xml", true); ("/", false); ("/nowhere", false);
            ("/team/a/1", false); ("/_yuka/app/main.js", false); ("/static/s.css", false) ] );
    ( "links of a page",
      fun () ->
        Alcotest.(check (list string)) "links"
          [ "/a"; "/b&c"; "/"; "/caf%C3%A9"; "/c/d"; "/eA"; "/f\xc3\xa9&bogus;&amp" ]
          (Server.links
             {|<a href="/a?x=1#y"></a><a href="//evil.com/x"></a><a href="https://e.com/"></a><a href="/b&amp;c"></a><link href="/"><a href="/a"><a href="#top"><a href="/caf%C3%A9"><a href="&#x2F;c&#47;d"><a href="/e&#X41;"><a href="/f&#233;&bogus;&amp;amp">|}) );
    ( "file of a path",
      fun () ->
        List.iter
          (fun (path, expected) -> Alcotest.(check (option string)) path expected (Server.prerender_file path))
          [ ("/", Some "index.html"); ("/a/b", Some "a/b/index.html"); ("/feed.xml", Some "feed.xml");
            ("/caf%C3%A9", Some "caf\xc3\xa9/index.html"); ("/%2e%2e/x", None); ("/a%2Fb", None);
            ("/a?q=1", Some "a/index.html") ] );
    ( "the 404 page of the app",
      fun () ->
        match Async.status (Server.missing_page config app ~sleep:Test_adapter.sleep) with
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
          [ ("/_yuka", "js"); ("/static", "pub") ]
          (Server.served_dirs prerendered) );
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
        check_true "org layout" (contains r.body {|<section class="org">|});
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
        check_header r "vary" [ "Yuka-Navigate" ];
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
        check_header r "vary" [ "Cookie, Yuka-Navigate" ];
        let r = get "/plain" in
        check_header r "vary" [ "Yuka-Navigate" ] );
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
    ( "a prefetch gets the same answer as a navigation",
      fun () ->
        let plain = get ~headers:[ ("yuka-navigate", "-") ] "/team/a/1" in
        let pre = get ~headers:[ ("yuka-navigate", "-"); ("yuka-prefetch", "1") ] "/team/a/1" in
        check_status pre plain.status;
        Alcotest.(check string) "same body" plain.body pre.body );
    ( "a stop Redirect needs a redirect status and a clean location",
      fun () ->
        List.iter
          (fun team ->
            let r = get ("/team/" ^ team ^ "/1") in
            check_status r 500;
            check_header r "location" [];
            Alcotest.(check int) "one log" 1 (List.length !logged))
          [ "okay"; "crlf" ] );
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
        check_events [ "outer" ];
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
    ( "Endpoint skips the origin check",
      fun () ->
        let r =
          get ~headers:[ ("Origin", "https://evil.example"); ("Host", "app.example") ] "/team/a/json"
        in
        check_status r 200 );
  ]

let loaders =
  [
    ( "a fallback that fails still answers 500",
      fun () ->
        let a = call (request "/later") in
        Server.log_error := (fun _ -> failwith "log down");
        App.finish_slow "explode";
        match Async.status a with
        | Async.Done r ->
            check_status r 500;
            Alcotest.(check string) "plain" "Internal Server Error" r.body
        | _ -> Alcotest.fail "the request hangs" );
    ( "loader-free layers are built once",
      fun () ->
        let first_layer route =
          match Cycle_server.Routes_server.resolve (request "/") route with
          | Server.Page { load; _ } -> (
              match Async.status (load ()) with
              | Async.Done (Ok plan) -> List.hd plan.layers
              | _ -> Alcotest.fail "no plan")
          | Server.Handler _ -> Alcotest.fail "not a page"
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
        check_true "error page" (contains r.body "error 500");
        check_true "no message" (not (contains r.body "secret"));
        Alcotest.(check int) "one log" 1 (List.length !logged) );
    ( "failed loader Async is 500",
      fun () ->
        let r = get "/team/a/500" in
        check_status r 500;
        Alcotest.(check (list string)) "log" [ "loader secret" ] !logged );
  ]

let render =
  [
    ( "a failed render waits for the writes in flight",
      fun () ->
        held_writes := [];
        let a = Held.handler config Cycle_server.Routes_server.app (request "/slow") in
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
        let a = Held.handler config Cycle_server.Routes_server.app (request "/twice") in
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
            check_true "fill script" (contains r.body Server.fill_script);
            check_true "before the shell" (index r.body Server.fill_script < index r.body "wait")
        | _ -> Alcotest.fail "not done" );
    ( "one module script, before the first island",
      fun () ->
        let r = get "/islands" in
        Alcotest.(check int) "one" 1 (count r.body "<script type=\"module\"");
        let script = index r.body {|<script type="module" async src="/_yuka/app/main.js"></script>|} in
        check_true "found" (script >= 0);
        check_true "before the island" (script < index r.body "<yuka-island");
        check_true "after the content before it" (script > index r.body "before");
        check_true "preload" (contains r.body {|<link rel="modulepreload" href="/_yuka/app/a.js">|}) );
    ( "the module script stays when a Catch drops the first island",
      fun () ->
        let req = request "/islands" in
        App.fail_first := true;
        let r = match Async.status (call req) with Async.Done v -> v | _ -> Alcotest.fail "pending" in
        check_true "fallback" (contains r.body "lost server error");
        check_true "island A dropped" (not (contains r.body {|data-name="A"|}));
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
          let r = request target in
          let view =
            { Server.meth = `GET; target; header = (fun _ -> None); body = (fun ~limit:_ -> Async.return (Some "")); csrf_token = (fun () -> "t") }
          in
          match
            Async.status
              (Server.handle config Cycle_server.Routes_server.app ~sleep:(fun _ -> fst3 (Async.make ()))
                 ~exists:Test_adapter.exists r view)
          with
          | Async.Done (Server.Respond { body = Server.String text; status; _ }) ->
              Printf.sprintf "string %d %b" status (String.ends_with ~suffix:"</body></html>" text)
          | Async.Done (Server.Respond { body = Server.Stream _; status; _ }) -> Printf.sprintf "stream %d" status
          | _ -> "other"
        in
        Alcotest.(check string) "settled" "string 200 true" (kind "/plain");
        Alcotest.(check string) "pending" "stream 200" (kind "/slow") );
    ( "a render failure before the shell is written is the 500 page",
      fun () ->
        let a =
          Server.handle config Cycle_server.Routes_server.app
            ~sleep:(fun _ -> Async.return ())
            ~exists:Test_adapter.exists (request "/slow")
            { Server.meth = `GET; target = "/slow"; header = (fun _ -> None); body = (fun ~limit:_ -> Async.return (Some "")); csrf_token = (fun () -> "t") }
        in
        match Async.status a with
        | Async.Done (Server.Respond r) ->
            check_status { status = r.status; headers = r.headers; body = "" } 500;
            check_header { status = r.status; headers = r.headers; body = "" } "cache-control" [ "no-store" ];
            Alcotest.(check int) "one log" 1 (List.length !logged)
        | _ -> Alcotest.fail "no response" );
    ( "shell exception is the 500 page",
      fun () ->
        let r = get "/broken" in
        check_status r 500;
        check_true "error page" (contains r.body "error 500");
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
  let build = Server.build_id config Cycle_server.Routes_server.app in
  [
    ( "shared root layout: partial with the page body",
      fun () ->
        let r = nav "L0" "/plain" in
        check_status r 200;
        check_header r "yuka-outlet" [ "L0" ];
        check_header r "yuka-build" [ build ];
        check_header r "yuka-title" [ "Plain" ];
        check_header r "content-type" [ "text/html; charset=utf-8" ];
        check_header r "vary" [ "Yuka-Navigate" ];
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
        let app = Cycle_server.Routes_server.app in
        let with_assets ~manifest ~digest =
          Server.config
            ~assets:(Server.modules ~dir:"js" ~entry:"./app/main.js" ~manifest ~packages:[ "pkg" ] ~digest)
            ()
        in
        let other = with_assets ~manifest:{|{"A":"./b.js"}|} ~digest:"d1" in
        check_true "differs" (Server.build_id other app <> build);
        let new_code = with_assets ~manifest:{|{"A":"./a.js"}|} ~digest:"d2" in
        check_true "new file content, new id" (Server.build_id new_code app <> build);
        check_true "stable" (Server.build_id config app = build) );
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
  let with_dev ?file ?(make = fun () -> Server.config ()) f =
    Unix.putenv "YUKA_DEV" "1";
    Unix.putenv "YUKA_DEV_FILE" (Option.value file ~default:"/nonexistent/yuka-dev");
    Fun.protect ~finally:(fun () -> Unix.putenv "YUKA_DEV" "") (fun () -> f (make ()))
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
    let view =
      { Server.meth; target; header = (fun _ -> None); body = (fun ~limit:_ -> Async.return None); csrf_token = (fun () -> "t") }
    in
    match
      Async.status
        (Server.handle config Cycle_server.Routes_server.app ~sleep ~exists:(fun ~root:_ ~path:_ -> false)
           (request target) view)
    with
    | Async.Done (Server.Respond { status; headers; body = Server.Stream f }) ->
        let written = ref [] in
        ignore (f (fun s -> written := !written @ [ s ]; write s));
        (status, headers, written)
    | Async.Done (Server.Respond { status; headers; body = Server.String s }) -> (status, headers, ref [ s ])
    | _ -> Alcotest.fail "no response"
  in
  [
    ( "without YUKA_DEV: no /_yuka/dev and no script",
      fun () ->
        Unix.putenv "YUKA_DEV" "";
        let config = Server.config () in
        let r = get ~config "/_yuka/dev" in
        check_status r 404;
        check_true "no script" (not (contains (get ~config "/plain").body "/_yuka/dev")) );
    ( "with YUKA_DEV=1: the events of the state file",
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
    ( "with YUKA_DEV=1: a heartbeat, an end on a failed write, HEAD without a loop",
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
        let saved = !Server.log_error and logged = ref [] in
        Server.log_error := (fun m -> logged := m :: !logged);
        let ended = Yuka.Private.dev_events ~state ~sleep (fun _ -> Async.return ()) in
        (try tick () with _ -> ());
        Server.log_error := saved;
        check_true "ended" (Async.status ended = Async.Done ());
        Alcotest.(check int) "logged once" 1 (List.length !logged);
        Alcotest.(check int) "no timer left" 0 (List.length !timers) );
    ( "with YUKA_DEV=1: prerendered pages render live; a prerender gets no script",
      fun () ->
        with_dev
          ~make:(fun () -> Server.config ~assets:modules ~prerendered:"pre" ())
          (fun config ->
            let r = get ~config "/plain" in
            check_true "rendered, not the file" (not (String.equal r.body "prerendered plain"));
            check_true "with the script" (contains r.body "EventSource");
            let r = get ~config:(Server.prerender_config config) "/plain" in
            check_true "a prerender config: the file" (String.equal r.body "prerendered plain");
            let r = get ~config:(Server.prerender_config (Server.config ())) "/plain" in
            check_true "a prerender config renders no script" (not (contains r.body "EventSource"))) );
    ( "with YUKA_DEV=1: the script in full pages only",
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
      ("loaders", cases loaders);
      ("render", cases render);
      ("navigation", cases navigation);
      ("forms", cases forms);
    ]
