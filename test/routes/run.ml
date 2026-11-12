open Alcotest
open Routes_fixture
module Router = Yuka.Router

let meth_name : Router.meth -> string = function
  | `GET -> "GET"
  | `HEAD -> "HEAD"
  | `POST -> "POST"
  | `PUT -> "PUT"
  | `PATCH -> "PATCH"
  | `DELETE -> "DELETE"
  | `OPTIONS -> "OPTIONS"
  | `Other m -> m

let pp_lookup ppf = function
  | Router.Found r -> Format.fprintf ppf "Found %s" (Routes.href r)
  | Router.Wrong_method ms ->
      Format.fprintf ppf "Wrong_method [%s]" (String.concat "; " (List.map meth_name ms))
  | Router.Redirect { permanent; location } ->
      Format.fprintf ppf "Redirect %b %s" permanent location
  | Router.Missing -> Format.fprintf ppf "Missing"

let lookup = testable pp_lookup ( = )

let hex c =
  match c with
  | '0' .. '9' -> Char.code c - 48
  | 'A' .. 'F' -> Char.code c - 55
  | 'a' .. 'f' -> Char.code c - 87
  | _ -> failwith "hex"

let decode s =
  let b = Buffer.create (String.length s) in
  let i = ref 0 in
  while !i < String.length s do
    if s.[!i] = '%' then begin
      Buffer.add_char b (Char.chr ((hex s.[!i + 1] * 16) + hex s.[!i + 2]));
      i := !i + 3
    end
    else begin
      Buffer.add_char b s.[!i];
      incr i
    end
  done;
  Buffer.contents b

let find ?(meth = `GET) target =
  let path = match String.index_opt target '?' with Some i -> String.sub target 0 i | None -> target in
  let segments =
    String.split_on_char '/' path |> List.filter (fun s -> s <> "") |> List.map decode
  in
  Routes.find meth segments (Yuka.Private.query target)

let t name f = test_case name `Quick f

let blog = Routes.Blog { lang = None; tag = None; page = 1; label = []; draft = false }

let issue =
  Routes.Issue { id = 12; tab = None; seen = []; view = Params.Tab.Overview }

let samples : (Router.meth * Routes.t) list =
  [
    (`GET, Home);
    (`GET, blog);
    ( `GET,
      Blog
        { lang = Some "fr"; tag = Some "a b&c=d"; page = -3; label = [ "x"; "y/z" ]; draft = true }
    );
    (`GET, New_post { lang = None });
    (`GET, New_post { lang = Some "en" });
    (`GET, Post { slug = "a/b c?#\xc3\xa9"; lang = None });
    (`GET, Post { slug = "news"; lang = Some "de" });
    (`GET, issue);
    (`GET, Issue { id = 7; tab = Some Activity; seen = [ 1; -2 ]; view = Activity });
    (`POST, Close_issue { id = 3 });
    (`GET, Issue_json { id = 3 });
    (`PUT, Update_issue { id = 3 });
    (`GET, Page_n { n = 0 });
    (`GET, Page_n { n = -5 });
    (`GET, Cafe);
    (`GET, Doc { parts = [ "a b"; "c"; "%" ] });
    (`GET, Feed);
    (`DELETE, Clear_feed);
    (`GET, Missing);
  ]

let edge_values : Routes.t list =
  [
    Post { slug = ""; lang = None };
    Post { slug = "."; lang = None };
    Post { slug = ".."; lang = None };
    Post { slug = "..."; lang = None };
    Post { slug = ".a"; lang = None };
    Doc { parts = [] };
    Doc { parts = [ "a"; "" ] };
    Doc { parts = [ "." ] };
    Doc { parts = [ "a"; ".."; "b" ] };
    Doc { parts = [ "..."; "%2E" ] };
    Blog { lang = Some ""; tag = Some "."; page = 1; label = [ ""; ".." ]; draft = false };
  ]

let href_cases =
  let check_href name expected route = check string name expected (Routes.href route) in
  [
    t "static and root" (fun () ->
        check_href "root" "/" Home;
        check_href "endpoint" "/feed.xml" Feed;
        check_href "action on the same path" "/feed.xml" Clear_feed);
    t "params are encoded" (fun () ->
        check_href "string" "/blog/a%2Fb%20c%3F%23%C3%A9"
          (Post { slug = "a/b c?#\xc3\xa9"; lang = None });
        check_href "int" "/page/-5" (Page_n { n = -5 });
        check_href "custom" "/issue/YUK-3/close" (Close_issue { id = 3 }));
    t "static segment is encoded" (fun () -> check_href "cafe" "/caf%C3%A9" Cafe);
    t "catch-all" (fun () ->
        check_href "parts" "/docs/a%20b/c%2Fd" (Doc { parts = [ "a b"; "c/d" ] });
        check_href "dots inside a segment" "/docs/.../.a" (Doc { parts = [ "..."; ".a" ] }));
    t "search at its absent value is left out" (fun () ->
        check_href "blog" "/blog" blog;
        check_href "issue" "/issue/YUK-12" issue);
    t "search in field order, encoded" (fun () ->
        check_href "blog" "/blog?lang=fr&tag=a%20b%26c&page=2&label=x&label=y%2Fz&draft=true"
          (Blog
             { lang = Some "fr"; tag = Some "a b&c"; page = 2; label = [ "x"; "y/z" ]; draft = true });
        check_href "custom types"
          "/issue/YUK-12?tab=activity&seen=1&seen=-2&view=activity"
          (Issue { id = 12; tab = Some Activity; seen = [ 1; -2 ]; view = Activity }));
    t "group search on every route below" (fun () ->
        check_href "new" "/blog/new?lang=en" (New_post { lang = Some "en" });
        check_href "post" "/blog/x?lang=en" (Post { slug = "x"; lang = Some "en" }));
  ]

let helper_cases =
  let same name helper route = check string name (Routes.href route) helper in
  [
    t "no param" (fun () ->
        same "home" (Routes.home ()) Home;
        same "cafe" (Routes.cafe ()) Cafe;
        same "endpoint" (Routes.feed ()) Feed;
        same "action" (Routes.clear_feed ()) Clear_feed;
        same "missing" (Routes.missing ()) Missing);
    t "path params" (fun () ->
        same "string" (Routes.post ~slug:"a/b c" ()) (Post { slug = "a/b c"; lang = None });
        same "int" (Routes.page_n ~n:(-5) ()) (Page_n { n = -5 }));
    t "custom param type" (fun () ->
        same "close" (Routes.close_issue ~id:3 ()) (Close_issue { id = 3 });
        same "json" (Routes.issue_json ~id:3 ()) (Issue_json { id = 3 });
        same "update" (Routes.update_issue ~id:3 ()) (Update_issue { id = 3 }));
    t "catch-all" (fun () ->
        same "parts" (Routes.doc ~parts:[ "a b"; "c/d" ] ()) (Doc { parts = [ "a b"; "c/d" ] }));
    t "absent search is the absent value of href" (fun () ->
        same "blog" (Routes.blog ()) blog;
        same "issue" (Routes.issue ~id:12 ()) issue;
        same "group search" (Routes.new_post ()) (New_post { lang = None }));
    t "each search kind" (fun () ->
        same "optional" (Routes.blog ~tag:"a b&c" ())
          (Blog { lang = None; tag = Some "a b&c"; page = 1; label = []; draft = false });
        same "default int" (Routes.blog ~page:2 ())
          (Blog { lang = None; tag = None; page = 2; label = []; draft = false });
        same "default bool" (Routes.blog ~draft:true ())
          (Blog { lang = None; tag = None; page = 1; label = []; draft = true });
        same "many" (Routes.blog ~label:[ "x"; "y/z" ] ())
          (Blog { lang = None; tag = None; page = 1; label = [ "x"; "y/z" ]; draft = false });
        same "group optional" (Routes.post ~slug:"x" ~lang:"en" ()) (Post { slug = "x"; lang = Some "en" });
        same "all, in field order"
          (Routes.blog ~draft:true ~label:[ "x" ] ~page:2 ~tag:"t" ~lang:"fr" ())
          (Blog { lang = Some "fr"; tag = Some "t"; page = 2; label = [ "x" ]; draft = true });
        same "custom types"
          (Routes.issue ~id:12 ~tab:Activity ~seen:[ 1; -2 ] ~view:Activity ())
          (Issue { id = 12; tab = Some Activity; seen = [ 1; -2 ]; view = Activity }));
  ]

let round_trip =
  [
    t "find (href r) is r for every sample" (fun () ->
        List.iter
          (fun (meth, r) ->
            let target = Routes.href r in
            check lookup (meth_name meth ^ " " ^ target) (Router.Found r) (find ~meth target))
          samples);
    t "href refuses or round-trips edge values" (fun () ->
        List.iter
          (fun r ->
            match Routes.href r with
            | exception Invalid_argument _ -> ()
            | target -> check lookup target (Router.Found r) (find target))
          edge_values);
    t "href refuses segments that find cannot give back" (fun () ->
        let refused r =
          match Routes.href r with exception Invalid_argument _ -> true | _ -> false
        in
        check bool "empty" true (refused (Post { slug = ""; lang = None }));
        check bool "dot" true (refused (Post { slug = "."; lang = None }));
        check bool "dot dot" true (refused (Post { slug = ".."; lang = None }));
        check bool "empty catch-all" true (refused (Doc { parts = [] }));
        check bool "empty catch-all item" true (refused (Doc { parts = [ "a"; "" ] }));
        check bool "dot dot catch-all item" true (refused (Doc { parts = [ "a"; ".." ] }));
        check bool "three dots" false (refused (Post { slug = "..."; lang = None })));
    t "every constructor has a sample" (fun () ->
        let name : Routes.t -> string = function
          | Home -> "Home"
          | Blog _ -> "Blog"
          | New_post _ -> "New_post"
          | Post _ -> "Post"
          | Issue _ -> "Issue"
          | Close_issue _ -> "Close_issue"
          | Issue_json _ -> "Issue_json"
          | Update_issue _ -> "Update_issue"
          | Page_n _ -> "Page_n"
          | Cafe -> "Cafe"
          | Doc _ -> "Doc"
          | Feed -> "Feed"
          | Clear_feed -> "Clear_feed"
          | Missing -> "Missing"
        in
        let names = List.sort_uniq compare (List.map (fun (_, r) -> name r) samples) in
        check int "constructors" 14 (List.length names));
  ]

let found (r : Routes.t) = Router.Found r

let find_cases =
  [
    t "static before param" (fun () ->
        check lookup "new" (found (New_post { lang = None })) (find "/blog/new");
        check lookup "news" (found (Post { slug = "news"; lang = None })) (find "/blog/news"));
    t "catch-all needs one segment" (fun () ->
        check lookup "none" Router.Missing (find "/docs");
        check lookup "one" (found (Doc { parts = [ "a" ] })) (find "/docs/a");
        check lookup "decoded" (found (Doc { parts = [ "a/b"; "c" ] })) (find "/docs/a%2Fb/c"));
    t "int is strict" (fun () ->
        List.iter
          (fun s -> check lookup s Router.Missing (find ("/page/" ^ s)))
          [ "1a"; "-"; "+5"; "0x10"; "1.0"; "99999999999999999999999" ];
        check lookup "-5" (found (Page_n { n = -5 })) (find "/page/-5");
        List.iter
          (fun s -> check lookup ("not canonical " ^ s) Router.Missing (find ("/page/" ^ s)))
          [ "007"; "01"; "-0"; "+1"; "1_000"; "0b1" ];
        check lookup "0" (found (Page_n { n = 0 })) (find "/page/0"));
    t "custom param None is Missing" (fun () ->
        check lookup "abc" Router.Missing (find "/issue/abc");
        check lookup "zero" Router.Missing (find "/issue/YUK-0");
        check lookup "action" Router.Missing (find ~meth:`POST "/issue/abc/close"));
    t "wrong method lists the methods of the path" (fun () ->
        check lookup "page" (Router.Wrong_method [ `GET ]) (find ~meth:`POST "/");
        check lookup "two" (Router.Wrong_method [ `GET; `DELETE ]) (find ~meth:`PUT "/feed.xml");
        check lookup "group" (Router.Wrong_method [ `GET; `PUT ]) (find ~meth:`DELETE "/issue/YUK-1/json");
        check lookup "action" (Router.Wrong_method [ `POST ]) (find "/issue/YUK-1/close");
        check lookup "other" (Router.Wrong_method [ `GET ]) (find ~meth:(`Other "TRACE") "/page/1"));
    t "HEAD answers like GET" (fun () ->
        check lookup "page" (found Home) (find ~meth:`HEAD "/");
        check lookup "endpoint" (found Feed) (find ~meth:`HEAD "/feed.xml"));
    t "redirects substitute and encode params, for every method" (fun () ->
        let moved = Router.Redirect { permanent = true; location = "/issue/YUK-7" } in
        check lookup "GET" moved (find "/i/YUK-7");
        check lookup "POST" moved (find ~meth:`POST "/i/YUK-7");
        check lookup "bad param" Router.Missing (find "/i/x");
        check lookup "catch-all"
          (Router.Redirect { permanent = false; location = "/docs/a%20b/c" })
          (find "/old-docs/a%20b/c");
        check lookup "static"
          (Router.Redirect { permanent = false; location = "/blog" })
          (find ~meth:`DELETE "/legacy-blog"));
    t "search decoding" (fun () ->
        let blog ?(tag = None) ?(page = 1) ?(label = []) ?(draft = false) () =
          found (Blog { lang = None; tag; page; label; draft })
        in
        check lookup "bad int is the default" (blog ()) (find "/blog?page=x");
        check lookup "first value" (blog ~page:3 ()) (find "/blog?page=3&page=4");
        check lookup "bad bool is the default" (blog ()) (find "/blog?draft=yes");
        check lookup "bool" (blog ~draft:true ()) (find "/blog?draft=true");
        check lookup "empty string is a value" (blog ~tag:(Some "") ()) (find "/blog?tag=");
        check lookup "many, unknown keys ignored"
          (blog ~label:[ "a"; "b c" ] ())
          (find "/blog?label=a&x=1&label=b+c");
        check lookup "custom optional bad, many skips bad, default bad"
          (found (Routes.Issue { id = 1; tab = None; seen = [ 1; 3 ]; view = Overview }))
          (find "/issue/YUK-1?tab=nope&seen=1&seen=x&seen=3&view=bad");
        check lookup "group search"
          (found (New_post { lang = Some "fr" }))
          (find "/blog/new?lang=fr"));
    t "no match" (fun () ->
        check lookup "unknown" Router.Missing (find "/nope");
        check lookup "too long" Router.Missing (find "/blog/a/b");
        check lookup "prefix only" Router.Missing (find "/issue"));
  ]

let router_cases =
  [
    t "encode" (fun () ->
        check string "reserved" "a%2Fb%20c%3F%23%C3%A9%26%3D%2B" (Router.encode "a/b c?#\xc3\xa9&=+");
        check string "unreserved" "AZaz09-._~" (Router.encode "AZaz09-._~"));
    t "segment" (fun () ->
        check string "encoded" "a%2Fb" (Router.segment "a/b");
        List.iter
          (fun s ->
            check bool s true
              (match Router.segment s with exception Invalid_argument _ -> true | _ -> false))
          [ ""; "."; ".." ]);
    t "int_param" (fun () ->
        check (option int) "neg" (Some (-12)) (Router.int_param "-12");
        check (option int) "empty" None (Router.int_param "");
        check (option int) "space" None (Router.int_param " 1");
        check (option int) "zero" (Some 0) (Router.int_param "0");
        List.iter
          (fun s -> check (option int) s None (Router.int_param s))
          [ "01"; "-0"; "+1"; "0x10"; "1_0"; "-01" ]);
    t "search" (fun () ->
        check (list string) "all values" [ "1"; "3" ]
          (Router.search [ ("a", "1"); ("b", "2"); ("a", "3") ] "a");
        check (list string) "absent" [] (Router.search [ ("a", "1") ] "z"));
  ]

let () =
  run "routes"
    [
      ("href", href_cases);
      ("helpers", helper_cases);
      ("round trip", round_trip);
      ("find", find_cases);
      ("Yuka.Router", router_cases);
    ]
