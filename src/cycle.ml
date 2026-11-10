open Types

type stop =
  | Not_found
  | Redirect of { status : int; location : string }
  | Fail of string

type page = { title : string; head : string; body : unit -> node }

let page ?(title = "") ?(head = "") body = { title; head; body }

type layer = { key : string; data : bool; wrap : node -> node }
type plan = { layers : layer list; page : page }

type cache =
  | No_store
  | Private of { max_age : int }
  | Public of { max_age : int; s_max_age : int option }
  | Immutable

let cache_control = function
  | No_store -> "no-store"
  | Private { max_age } -> "private, max-age=" ^ string_of_int max_age
  | Public { max_age; s_max_age } -> (
      "public, max-age=" ^ string_of_int max_age
      ^ match s_max_age with Some s -> ", s-maxage=" ^ string_of_int s | None -> "")
  | Immutable -> "public, max-age=31536000, immutable"

let same_name a b = String.equal (String.lowercase_ascii a) (String.lowercase_ascii b)

let has_header name headers = List.exists (fun (n, _) -> same_name n name) headers

let set_header ((name, _) as h) headers =
  List.filter (fun (n, _) -> not (same_name n name)) headers @ [ h ]

let merge_headers lists =
  List.fold_left (fun acc l -> List.fold_left (fun acc h -> set_header h acc) acc l) [] lists

type rules = { headers : (string * string) list; cache : cache option; prerender : bool }

let rules ~headers ?cache ~prerender () =
  { headers = merge_headers headers; cache; prerender }

type body = String of string | Stream of ((string -> unit Async.t) -> unit Async.t)
type response = { status : int; headers : (string * string) list; body : body }

let with_type kind ?(status = 200) ?(headers = []) text =
  Async.return
    { status; headers = merge_headers [ [ ("content-type", kind) ]; headers ]; body = String text }

let text ?status ?headers s = with_type "text/plain; charset=utf-8" ?status ?headers s
let html ?status ?headers s = with_type "text/html; charset=utf-8" ?status ?headers s
let json ?status ?headers j = with_type "application/json" ?status ?headers (Json.to_string j)

let see_other location =
  Async.return { status = 303; headers = [ ("location", location) ]; body = String "" }

type fallback = { layers : layer list; not_found : string -> page; error : int -> page }

let heading text () = Element { tag = "h1"; attrs = []; children = [ Text text ] }
let default_not_found _ = page ~title:"Not Found" (heading "Not Found")
let default_error _ = page ~title:"Error" (heading "Internal Server Error")

type target =
  | Page of {
      rules : rules;
      guards : (unit -> (unit, stop) result Async.t) list;
      load : unit -> (plan, stop) result Async.t;
      fallback : fallback;
    }
  | Handler of {
      rules : rules;
      same_origin : bool;
      guards : (unit -> (unit, stop) result Async.t) list;
      run : unit -> response Async.t;
    }

type 'req app =
  | App : {
      build : string;
      headers : (string * string) list;
      prerender : string list;
      find : Router.meth -> string list -> (string * string) list -> 'r Router.lookup;
      resolve : 'req -> 'r -> target;
      missing : fallback;
    }
      -> 'req app

let app ~build ~headers ~prerender ~find ~resolve ~missing =
  App { build; headers = merge_headers [ headers ]; prerender; find; resolve; missing }

let failure e = Fail (Web.exn_to_string e)

let settle a =
  let r, resolve, _ = Async.make () in
  Async.on_settled a (function
    | Async.Done v -> resolve v
    | Async.Failed m -> resolve (Error (Fail m))
    | Async.Pending -> ());
  r

let protect f = match f () with a -> settle a | exception e -> Async.return (Error (failure e))

let loaded a k =
  let r, resolve, _ = Async.make () in
  Async.on_settled a (function
    | Async.Done (Ok v) -> Async.on_settled (protect (fun () -> k v)) (function
        | Async.Done x -> resolve x
        | Async.Failed m -> resolve (Error (Fail m))
        | Async.Pending -> ())
    | Async.Done (Error s) -> resolve (Error s)
    | Async.Failed m -> resolve (Error (Fail m))
    | Async.Pending -> ());
  r

type assets = {
  dir : string;
  entry : string;
  digest : string;
  import_map : (string * string) list;
  preload : string -> string option;
  immutable : string -> bool;
}

let fingerprint text =
  let hash seed =
    String.fold_left (fun h c -> (h lxor Char.code c) * 0x01000193 land 0xffffffff) seed text
  in
  Printf.sprintf "%08x%08x" (hash 0x811c9dc5) (hash 0x050c5d1f)

let modules ~dir ~entry ~manifest ~packages ~digest =
  let entry = Server.normalize entry in
  let base =
    match String.rindex_opt entry '/' with
    | Some i -> "/_yuka/" ^ String.sub entry 0 (i + 1)
    | None -> "/_yuka/"
  in
  {
    dir;
    entry;
    digest = fingerprint (String.concat "\n" (entry :: manifest :: digest :: packages));
    import_map = Server.import_map ~url:"/_yuka" packages;
    preload = Server.preload_urls ~manifest ~base ();
    immutable = (fun _ -> false);
  }

let outputs metafile =
  match Json.of_string metafile with
  | Ok (`Assoc top) -> (
      match List.assoc_opt "outputs" top with
      | Some (`Assoc outs) -> List.map (fun (file, _) -> Server.normalize file) outs
      | _ -> invalid_arg "Yuka.Server.bundle: metafile has no outputs object")
  | Ok _ -> invalid_arg "Yuka.Server.bundle: metafile is not an object"
  | Error m -> invalid_arg ("Yuka.Server.bundle: bad metafile JSON: " ^ m)

let bundle ~dir ~entry ~manifest ~metafile =
  let entry = Server.normalize entry in
  let hashed = List.filter (fun f -> not (String.equal f entry)) (outputs metafile) in
  {
    dir;
    entry;
    digest = fingerprint (String.concat "\n" [ entry; manifest; metafile ]);
    import_map = [];
    preload = Server.preload_urls ~manifest ~base:"/_yuka/" ~metafile ();
    immutable = (fun path -> List.exists (String.equal path) hashed);
  }

type dev = { state : unit -> string }

let dev_default = {|{"session":"","build":0,"page":0,"error":null}|}

let dev_of_env () =
  match Sys.getenv_opt "YUKA_DEV" with
  | Some "1" ->
      let file = Sys.getenv_opt "YUKA_DEV_FILE" in
      let state () =
        match file with
        | None -> dev_default
        | Some f -> (
            match Option.map String.trim (Web.read_file f) with
            | None | Some "" -> dev_default
            | Some text -> String.concat " " (String.split_on_char '\n' text))
      in
      Some { state }
  | _ -> None

let dev_script state =
  let json = String.concat "\\u003c" (String.split_on_char '<' state) in
  "<script>(function(){var s=" ^ json
  ^ {|,b=s.build,p=s.page,k="yuka-dev-scroll",o=null;try{var y=sessionStorage.getItem(k);if(y!==null){sessionStorage.removeItem(k);addEventListener("load",function(){scrollTo(0,+y)})}}catch(e){}function show(t){if(!t){if(o){o.remove();o=null}return}if(!o){o=document.createElement("pre");o.id="yuka-dev-error";o.style.cssText="position:fixed;inset:0;z-index:2147483647;margin:0;padding:16px;overflow:auto;background:rgba(30,0,0,.94);color:#fdd;font:13px/1.4 monospace;white-space:pre-wrap"}o.textContent=t;(document.body||document.documentElement).appendChild(o)}var e=new EventSource("/_yuka/dev");e.onmessage=function(m){var d=JSON.parse(m.data);show(d.error);if(d.error)return;if(d.session!==s.session||d.page>p){try{sessionStorage.setItem(k,String(scrollY))}catch(x){}s.session=d.session;p=d.page;location.reload();return}if(d.build>b){b=d.build;document.querySelectorAll('link[rel="stylesheet"]').forEach(function(l){if(l.hasAttribute("data-yuka-css"))return;var u=new URL(l.getAttribute("href"),location.href);if(u.origin!==location.origin)return;u.searchParams.set("v",String(b));l.href=u.href})}}})()</script>|}

type config = {
  dev : dev option;
  assets : assets option;
  public : (string list * string) list;
  styles : string list;
  css : (string * string) list;
  head : string;
  timeout : float;
  prerendered : string option;
}

let valid_file_segment s =
  s <> "" && s <> "." && s <> ".."
  && not (String.exists (fun c -> c = '/' || c = '\\' || c = '\000') s)

let public_prefix (prefix, dir) =
  match Router.split_path prefix with
  | [] ->
      invalid_arg
        ("Yuka.Server.config: public prefix " ^ Printf.sprintf "%S" prefix
       ^ " has no segment; it would hide every route")
  | segments -> (segments, dir)

let config ?assets ?(public = []) ?prerendered ?(styles = []) ?(css = []) ?(head = "") ?(timeout = 10.) () =
  {
    dev = dev_of_env ();
    assets;
    public = List.map public_prefix public;
    styles;
    css =
      List.map
        (fun (name, text) ->
          if valid_file_segment name then (name, text)
          else invalid_arg (Printf.sprintf "Yuka.Server.config: css file name %S is not one path segment" name))
        css;
    head;
    timeout;
    prerendered;
  }

let build_id config (App a) =
  match config.assets with
  | None -> a.build
  | Some assets -> a.build ^ assets.digest

let prerender_config config = { config with dev = None }

let css_files config = List.map (fun (file, text) -> ("_yuka/css/" ^ file, text)) config.css

let served_dirs config =
  Option.to_list (Option.map (fun (a : assets) -> ("/_yuka", a.dir)) config.assets)
  @ List.map (fun (prefix, dir) -> ("/" ^ String.concat "/" prefix, dir)) config.public

type request = {
  meth : Router.meth;
  target : string;
  header : string -> string option;
  body : limit:int -> string option Async.t;
  csrf_token : unit -> string;
}

type outcome =
  | Respond of response
  | File of { root : string; path : string; headers : (string * string) list }

let method_name : Router.meth -> string = function
  | `GET -> "GET"
  | `HEAD -> "HEAD"
  | `POST -> "POST"
  | `PUT -> "PUT"
  | `PATCH -> "PATCH"
  | `DELETE -> "DELETE"
  | `OPTIONS -> "OPTIONS"
  | `Other m -> m

let allow ms =
  let names =
    List.concat_map (function `GET -> [ "GET"; "HEAD" ] | m -> [ method_name m ]) ms
    @ [ "OPTIONS" ]
  in
  let unique =
    List.fold_left (fun acc n -> if List.exists (String.equal n) acc then acc else acc @ [ n ]) [] names
  in
  String.concat ", " unique

let no_store = ("cache-control", "no-store")

let plain status message headers =
  {
    status;
    headers = merge_headers [ headers; [ ("content-type", "text/plain; charset=utf-8"); no_store ] ];
    body = String message;
  }

let method_not_allowed allowed = plain 405 "Method Not Allowed" [ ("allow", allowed) ]
let reply r = Async.return (Respond r)
let empty status headers = { status; headers; body = String "" }

type env = {
  config : config;
  sleep : float -> unit Async.t;
  head_only : bool;
  navigate : string list option;
  build : string;
  current : string;
  root_headers : (string * string) list;
  exists : root:string -> path:string -> bool;
  form : (string * string * (string * string) list * (string option * string) list) option;
  csrf : (unit -> string) option;
}

let outlet key inner =
  Element
    {
      tag = "yuka-outlet";
      attrs = [ Static ("data-k", key); Static ("style", "display:contents") ];
      children = [ inner ];
    }

let nest layers body () =
  List.fold_right (fun (l : layer) inner -> l.wrap (outlet l.key inner)) layers (body ())

let add_vary value headers =
  let existing =
    List.concat_map
      (fun (n, v) ->
        if same_name n "vary" then
          List.filter (fun x -> x <> "") (List.map String.trim (String.split_on_char ',' v))
        else [])
      headers
  in
  let values =
    if List.exists (same_name value) existing then existing else existing @ [ value ]
  in
  set_header ("vary", String.concat ", " values) headers

let html_headers rule_headers extra =
  add_vary "Yuka-Navigate"
    (merge_headers [ rule_headers; [ ("content-type", "text/html; charset=utf-8") ]; extra ])

let rec shared sent (layers : layer list) =
  match (sent, layers) with
  | s :: sent, l :: layers when (not l.data) && String.equal s l.key -> 1 + shared sent layers
  | _ -> 0

let render env ~status ~headers layers (page : page) =
  let assets = env.config.assets in
  let preload = Option.map (fun (a : assets) -> a.preload) assets in
  let entry =
    Option.map
      (fun (a : assets) ->
        "<script type=\"module\" async src=\""
        ^ Printer.escape ~quote:true ("/_yuka/" ^ a.entry)
        ^ "\"></script>")
      assets
  in
  let import_map = match assets with Some a -> a.import_map | None -> [] in
  let head extra =
    Server.head
      ~extra:
        ("<meta name=\"yuka-build\" content=\"" ^ Printer.escape ~quote:true env.build ^ "\">"
        ^ (match (env.config.dev, env.navigate) with
          | Some dev, None -> dev_script (dev.state ())
          | _ -> "")
        ^ extra)
      ~head:(env.config.head ^ page.head) ~import_map ~title:page.title ~styles:env.config.styles ()
  in
  let build = nest layers page.body in
  let timeout = env.config.timeout and current = env.current in
  match env.navigate with
  | Some sent -> (
      let headers = set_header ("yuka-build", env.build) headers in
      let keys = List.map (fun (l : layer) -> l.key) layers in
      match shared sent layers with
      | 0 ->
          Async.map
            (fun body -> { status; headers; body = String (head "" ^ body ^ "</body></html>") })
            (Server.settled ?preload ?entry ?form:env.form ?csrf:env.csrf ~current ~timeout ~sleep:env.sleep build)
      | n ->
          let outlet = List.nth keys (n - 1) in
          let headers =
            merge_headers
              [ headers; [ ("yuka-outlet", outlet); ("yuka-title", Router.encode page.title) ] ]
          in
          Async.map
            (fun body -> { status; headers; body = String body })
            (Server.settled ?preload ?form:env.form ?csrf:env.csrf ~id_prefix:(outlet ^ "-") ~current ~timeout ~sleep:env.sleep
               (nest (List.filteri (fun i _ -> i >= n) layers) page.body)))
  | None ->
    let early = ref [] in
    let writer =
      ref (fun text ->
          early := text :: !early;
          Async.return ())
    in
    let write text = !writer text in
    let finished =
      Server.drive ?preload ?entry ?form:env.form ?csrf:env.csrf ~current ~timeout ~sleep:env.sleep build
        ~on_shell:(fun ~fills shell ->
          Async.bind (write (head (if fills then Server.fill_script else ""))) (fun () -> write shell))
        ~on_fill:(fun id _ links html -> write (links ^ Server.fill_chunk id html))
        ~on_value:write
    in
    let written () = String.concat "" (List.rev !early) in
    match Async.status finished with
    | Async.Failed m -> Async.failed m
    | Async.Done () ->
        early := "</body></html>" :: !early;
        Async.return { status; headers; body = String (written ()) }
    | Async.Pending ->
    let stream w =
      let flushed = w (written ()) in
      writer := (fun text -> Async.bind flushed (fun () -> w text));
      let result, resolve, _ = Async.make () in
      Async.on_settled finished (function
        | Async.Done () -> Async.on_settled (write "</body></html>") (fun _ -> resolve ())
        | Async.Failed m ->
            !Server.log_error m;
            Async.on_settled flushed (fun _ -> resolve ())
        | Async.Pending -> ());
      result
    in
    Async.return { status; headers; body = Stream stream }

let internal_error () = plain 500 "Internal Server Error" []
let log_quietly m = try !Server.log_error m with _ -> ()

let recover_with ~last a f =
  let r, resolve, _ = Async.make () in
  let give_up m =
    log_quietly m;
    resolve (last ())
  in
  Async.on_settled a (function
    | Async.Done v -> resolve v
    | Async.Failed m -> (
        match f m with
        | b ->
            Async.on_settled b (function
              | Async.Done v -> resolve v
              | Async.Failed m -> give_up m
              | Async.Pending -> ())
        | exception e -> give_up (Web.exn_to_string e))
    | Async.Pending -> ());
  r

let recover a f = recover_with ~last:internal_error a f

let error_page env (fallback : fallback) =
  let headers = html_headers env.root_headers [ no_store ] in
  let give_up m =
    !Server.log_error m;
    Async.return (internal_error ())
  in
    match render env ~status:500 ~headers fallback.layers (fallback.error 500) with
    | a -> recover a give_up
    | exception e -> give_up (Web.exn_to_string e)

let fail_page env fallback message =
  !Server.log_error message;
  error_page env fallback

let show env ~status ~headers ~fallback layers (page : unit -> page) =
    match render env ~status ~headers layers (page ()) with
    | a -> recover a (fail_page env fallback)
    | exception e -> fail_page env fallback (Web.exn_to_string e)

let not_found_page env (fallback : fallback) target =
  show env ~status:404 ~headers:(html_headers env.root_headers [ no_store ]) ~fallback
    fallback.layers (fun () -> fallback.not_found target)

let stopped env fallback target = function
  | Not_found -> not_found_page env fallback target
  | Redirect { status; location } ->
      if not (List.mem status [ 301; 302; 303; 307; 308 ]) then
        fail_page env fallback ("redirect with status " ^ string_of_int status)
      else if String.exists (fun c -> c = '\r' || c = '\n') location then
        fail_page env fallback "redirect location holds CR or LF"
      else
        Async.return
          (empty status (merge_headers [ env.root_headers; [ ("location", location); no_store ] ]))
  | Fail m -> fail_page env fallback m

let rec run_guards = function
  | [] -> Async.return (Ok ())
  | g :: rest ->
      Async.bind (protect g) (function
        | Ok () -> run_guards rest
        | Error _ as e -> Async.return e)

let rule_cache (rules : rules) headers =
  match rules.cache with
  | Some c when not (has_header "cache-control" headers) ->
      headers @ [ ("cache-control", cache_control c) ]
  | _ -> headers

let file_path raw =
  let parts = List.map (Router.decode ~plus:false) raw in
  if parts <> [] && List.for_all valid_file_segment parts then Some (String.concat "/" parts)
  else None

let asset_miss () = plain 404 "Not Found" []

let prerender_file target =
  let path, _ = Router.split_target target in
  let parts = Router.split_path path in
  let decoded = List.map (Router.decode ~plus:false) parts in
  if not (List.for_all valid_file_segment decoded) then None
  else
    match List.rev decoded with
    | [] -> Some "index.html"
    | last :: _ when String.contains last '.' -> Some (String.concat "/" decoded)
    | _ -> Some (String.concat "/" (decoded @ [ "index.html" ]))

let prerendered_file env (rules : rules) (r : request) ~path ~query =
  match (env.config.prerendered, r.meth, query) with
  | Some root, (`GET | `HEAD), (None | Some "")
    when rules.prerender && env.navigate = None && Option.is_none env.config.dev -> (
      match prerender_file path with
      | Some file when env.exists ~root ~path:file -> Some (root, file)
      | _ -> None)
  | _ -> None

let serve_file meth ~root ~headers raw =
  match meth with
  | `GET | `HEAD -> (
      match file_path raw with
      | Some path -> Async.return (File { root; path; headers })
      | None -> reply (asset_miss ()))
  | _ -> reply (plain 405 "Method Not Allowed" [ ("allow", "GET, HEAD") ])

let csrf_answer (r : request) =
  match r.meth with
  | `GET | `HEAD ->
      if Server.trusted_origin r.header then
        reply
          {
            status = 200;
            headers = [ ("content-type", "application/json"); no_store ];
            body = String (Json.to_string (`Assoc [ ("csrf", `String (r.csrf_token ())) ]));
          }
      else reply (plain 403 "Forbidden" [])
  | _ -> reply (method_not_allowed "GET, HEAD")

let action (r : request) raw =
  match (raw, r.meth) with
  | [ name ], `POST -> (
      let json (status, body) =
        Respond { status; headers = [ ("content-type", "application/json"); no_store ]; body = String body }
      in
      let name = Router.decode ~plus:false name in
      match Server.accept_action ~name r.header with
      | Error e -> Async.return (json e)
      | Ok handler ->
          Async.bind (r.body ~limit:Server.max_body) (function
            | None -> Async.return (json (Server.action_error 413 "request too large"))
            | Some body -> Async.map json (Server.answer_action ~name handler body)))
  | [ _ ], _ -> reply (plain 405 "Method Not Allowed" [ ("allow", "POST") ])
  | _ -> reply (asset_miss ())

let rec strip_prefix prefix parts =
  match (prefix, parts) with
  | [], rest -> Some rest
  | p :: prefix, x :: rest when String.equal p x -> strip_prefix prefix rest
  | _ -> None

let query_suffix = function Some q when q <> "" -> "?" ^ q | _ -> ""

let serve_page env (r : request) ~path ~query ~status ~(rules : rules) ~guards
    ~(load : unit -> (plan, stop) result Async.t) ~(fallback : fallback) =
  let page_or_error a = Async.map (fun resp -> Respond resp) a in
  Async.bind (run_guards guards) (function
    | Error stop -> page_or_error (stopped env fallback path stop)
    | Ok () -> (
        let headers = rule_cache rules (html_headers rules.headers []) in
        let headers = if status = 200 then headers else set_header no_store headers in
        match prerendered_file env rules r ~path ~query with
        | Some (root, file) -> Async.return (File { root; path = file; headers })
        | None ->
            page_or_error
              (Async.bind (protect load) (function
                | Error stop -> stopped env fallback path stop
                | Ok plan -> show env ~status ~headers ~fallback plan.layers (fun () -> plan.page)))))

let is_form ct = Server.media_type ct = Some "application/x-www-form-urlencoded"

let form_post env (App a) req (r : request) ~path ~segments ~query ~allowed =
  let page_or_error a = Async.map (fun resp -> Respond resp) a in
  match a.find `GET segments (Router.query r.target) with
  | Router.Found found -> (
      match a.resolve req found with
      | exception e -> page_or_error (fail_page env a.missing (Web.exn_to_string e))
      | Handler _ -> reply (method_not_allowed allowed)
      | Page { rules; guards; load; fallback } ->
          let plain status message = plain status message rules.headers in
          if not (Server.trusted_origin r.header) then reply (plain 403 "Forbidden")
          else
            Async.bind (run_guards guards) (function
              | Error stop -> page_or_error (stopped env fallback path stop)
              | Ok () ->
                  Async.bind (r.body ~limit:Server.max_body) (function
                    | None -> reply (plain 413 "Request Too Large")
                    | Some body -> (
                        let fields = Router.query ("?" ^ body) in
                        match List.assoc_opt "_yuka_action" fields with
                        | None -> reply (method_not_allowed allowed)
                        | Some name -> (
                            match Server.find_form name with
                            | None -> reply (plain 404 "Not Found")
                            | Some run ->
                                let key = Option.value (List.assoc_opt "_yuka_key" fields) ~default:"" in
                                let values =
                                  List.filter (fun (k, _) -> k <> "_yuka_action" && k <> "_yuka_key") fields
                                in
                                let unprocessable errors =
                                  serve_page { env with form = Some (name, key, values, errors) } r ~path ~query
                                    ~status:422 ~rules ~guards:[] ~load ~fallback
                                in
                                let answer =
                                  match run values with a -> a | exception e -> Async.failed (Web.exn_to_string e)
                                in
                                recover_with ~last:(fun () -> Respond (internal_error ()))
                                  (Async.bind answer (function
                                    | Server.Saved location ->
                                        let location = Option.value location ~default:(path ^ query_suffix query) in
                                        if Server.local_location ~host:(r.header "host") location then
                                          reply
                                            (empty 303
                                               (merge_headers [ rules.headers; [ ("location", location); no_store ] ]))
                                        else
                                          page_or_error
                                            (fail_page env a.missing ("form " ^ name ^ " redirect to " ^ String.escaped location
                                               ^ " is not a path on this site"))
                                    | Server.Unprocessable errors -> unprocessable errors))
                                  (fun m ->
                                    match Server.rejection m with
                                    | Some shown -> unprocessable [ (None, shown) ]
                                    | None -> page_or_error (fail_page env a.missing m)))))))
  | _ -> reply (method_not_allowed allowed)

let route env (App a) req (r : request) ~path ~raw ~query =
  let segments = List.map (Router.decode ~plus:false) raw in
  let suffix = query_suffix query in
  let page_or_error a = Async.map (fun resp -> Respond resp) a in
  match a.find r.meth segments (Router.query r.target) with
  | Router.Redirect { permanent; location } ->
      reply (empty (if permanent then 308 else 307) [ ("location", location ^ suffix) ])
  | Router.Missing -> page_or_error (not_found_page env a.missing path)
  | Router.Wrong_method ms -> (
      match r.meth with
      | `OPTIONS -> reply (empty 204 [ ("allow", allow ms) ])
      | `POST when List.mem `GET ms && is_form (r.header "content-type") ->
          form_post env (App a) req r ~path ~segments ~query ~allowed:(allow ms)
      | _ -> reply (method_not_allowed (allow ms)))
  | Router.Found found -> (
      match a.resolve req found with
      | exception e -> page_or_error (fail_page env a.missing (Web.exn_to_string e))
      | Page { rules; guards; load; fallback } ->
          serve_page env r ~path ~query ~status:200 ~rules ~guards ~load ~fallback
      | Handler { rules; same_origin; guards; run } ->
          page_or_error
            (Async.bind (run_guards guards) (function
              | Error stop -> stopped env a.missing path stop
              | Ok () ->
                  if
                    same_origin && not (Server.trusted_origin r.header)
                  then Async.return (plain 403 "Forbidden" [])
                  else
                    let ran =
                      match run () with
                      | resp -> Async.map (fun x -> Ok x) resp
                      | exception e -> Async.return (Error (Web.exn_to_string e))
                    in
                    recover
                      (Async.bind ran (function
                        | Error m -> fail_page env a.missing m
                        | Ok (resp : response) ->
                            let merged = merge_headers [ rules.headers; resp.headers ] in
                            let headers =
                              if same_origin then set_header no_store merged
                              else if resp.status < 200 || resp.status > 299 then
                                if has_header "cache-control" resp.headers then merged
                                else set_header no_store merged
                              else rule_cache rules merged
                            in
                            Async.return { resp with headers }))
                      (fail_page env a.missing))))

let dev_events ~state ~sleep write =
  let result, resolve, _ = Async.make () in
  let rec step last idle =
    match state () with
    | exception e ->
        log_quietly ("Yuka dev: cannot read the dev state: " ^ Web.exn_to_string e);
        resolve ()
    | now ->
    let message =
      if not (String.equal now last) then Some ("data: " ^ now ^ "\n\n")
      else if idle >= 60 then Some ": ping\n\n"
      else None
    in
    match message with
    | None -> wait now (idle + 1)
    | Some m -> (
        match write m with
        | sent ->
            Async.on_settled sent (function
              | Async.Done () -> wait now 1
              | Async.Failed _ | Async.Pending -> resolve ())
        | exception _ -> resolve ())
  and wait last idle = Async.on_settled (sleep 0.25) (fun _ -> step last idle) in
  step "" 0;
  result

let handle config (App a as app) ~sleep ~exists req (r : request) =
  let path, query = Router.split_target r.target in
  let env =
    {
      config;
      sleep;
      head_only = (match r.meth with `HEAD -> true | _ -> false);
      navigate =
        Option.map
          (fun v -> List.filter (fun k -> k <> "") (String.split_on_char ' ' v))
          (r.header "yuka-navigate");
      build = build_id config (App a);
      current = path;
      root_headers = a.headers;
      exists;
      form = None;
      csrf = Some r.csrf_token;
    }
  in
  let parts = String.split_on_char '/' path in
  let raw = Router.split_path path in
  let public =
    List.find_map
      (fun (prefix, dir) ->
        match strip_prefix prefix raw with
        | Some rest -> Some (dir, rest)
        | _ -> None)
      config.public
  in
  let run () =
    match (parts, public) with
    | "" :: "_yuka" :: _, _ -> (
        match (List.tl raw, config.dev) with
        | [ "dev" ], Some dev -> (
            let headers = [ ("content-type", "text/event-stream"); ("cache-control", "no-store") ] in
            match r.meth with
            | `GET -> reply { status = 200; headers; body = Stream (dev_events ~state:dev.state ~sleep) }
            | `HEAD -> reply { status = 200; headers; body = String "" }
            | _ -> reply (method_not_allowed "GET, HEAD"))
        | raw, _ ->
        match raw with
        | "action" :: rest -> action r rest
        | [ "csrf" ] -> csrf_answer r
        | "css" :: rest when config.css <> [] -> (
            match r.meth with
            | `GET | `HEAD -> (
                match Option.bind (file_path rest) (fun f -> List.assoc_opt f config.css) with
                | Some text ->
                    reply
                      {
                        status = 200;
                        headers =
                          [ ("content-type", "text/css; charset=utf-8"); ("cache-control", cache_control Immutable) ];
                        body = String text;
                      }
                | None -> reply (asset_miss ()))
            | _ -> reply (method_not_allowed "GET, HEAD"))
        | rest -> (
            match config.assets with
            | None -> reply (asset_miss ())
            | Some assets ->
                let headers =
                  match file_path rest with
                  | Some p when assets.immutable p -> [ ("cache-control", cache_control Immutable) ]
                  | _ -> [ ("cache-control", "no-cache") ]
                in
                serve_file r.meth ~root:assets.dir ~headers rest))
    | "" :: _, Some (dir, rest) -> serve_file r.meth ~root:dir ~headers:[] rest
    | "" :: _, None when String.contains path '\\' ->
        Async.map (fun x -> Respond x) (not_found_page env a.missing path)
    | "" :: rest, None ->
        let canonical = "/" ^ String.concat "/" raw in
        let trailing = List.exists (fun s -> s = "") rest && rest <> [ "" ] in
        if trailing then
          let suffix = query_suffix query in
          reply (empty 308 [ ("location", canonical ^ suffix) ])
        else route env app req r ~path ~raw ~query
    | _ -> Async.map (fun x -> Respond x) (not_found_page env a.missing path)
  in
  let bodyless = function
    | Respond ({ body = String text; _ } as r) when env.head_only ->
        let headers =
          if has_header "content-length" r.headers then r.headers
          else r.headers @ [ ("content-length", string_of_int (String.length text)) ]
        in
        Respond { r with headers; body = String "" }
    | Respond ({ body = Stream _; _ } as r) when env.head_only ->
        Respond { r with body = Stream (fun _ -> Async.return ()) }
    | File { root; path; headers } when env.head_only ->
        if exists ~root ~path then Respond (empty 200 headers)
        else Respond { (asset_miss ()) with body = String "" }
    | outcome -> outcome
  in
  let last () = Respond (internal_error ()) in
  let answer =
    match run () with
    | a ->
        recover_with ~last a (fun m ->
            !Server.log_error m;
            reply (internal_error ()))
    | exception e ->
        log_quietly (Web.exn_to_string e);
        Async.return (last ())
  in
  Async.map bodyless answer

type http_response = response

module type ADAPTER = sig
  type request
  type response
  type 'a io

  val meth : request -> Router.meth
  val target : request -> string
  val header : request -> string -> string option
  val body : request -> limit:int -> string option Async.t
  val csrf_token : request -> string
  val respond : http_response -> response io
  val file : request -> root:string -> path:string -> headers:(string * string) list -> response io
  val exists : root:string -> path:string -> bool
  val of_async : 'a Async.t -> 'a io
  val bind : 'a io -> ('a -> 'b io) -> 'b io
  val sleep : float -> unit Async.t
end

module Make (A : ADAPTER) = struct
  let handler config app (req : A.request) =
    let view =
      {
        meth = A.meth req;
        target = A.target req;
        header = A.header req;
        body = (fun ~limit -> A.body req ~limit);
        csrf_token = (fun () -> A.csrf_token req);
      }
    in
    A.bind (A.of_async (handle config app ~sleep:A.sleep ~exists:A.exists req view)) (function
      | Respond r -> A.respond r
      | File { root; path; headers } -> A.file req ~root ~path ~headers)
end

let prerender_seeds (App a) = a.prerender

let prerenderable config (App a) req target =
  let path, _ = Router.split_target target in
  let raw = Router.split_path path in
  let served =
    (match raw with "_yuka" :: _ -> true | _ -> false)
    || List.exists (fun (prefix, _) -> Option.is_some (strip_prefix prefix raw)) config.public
  in
  (not served)
  &&
  match a.find `GET (List.map (Router.decode ~plus:false) raw) [] with
  | Router.Found found -> (
      match a.resolve req found with
      | Page { rules; _ } | Handler { rules; _ } -> rules.prerender
      | exception _ -> false)
  | _ -> false

let char_ref name =
  match name with
  | "amp" -> Some 38
  | "lt" -> Some 60
  | "gt" -> Some 62
  | "quot" -> Some 34
  | "apos" -> Some 39
  | _ when String.length name > 2 && name.[0] = '#' && (name.[1] = 'x' || name.[1] = 'X') ->
      int_of_string_opt ("0x" ^ String.sub name 2 (String.length name - 2))
  | _ when String.length name > 1 && name.[0] = '#' ->
      let digits = String.sub name 1 (String.length name - 1) in
      if String.for_all (fun c -> c >= '0' && c <= '9') digits then int_of_string_opt digits else None
  | _ -> None

let entity text =
  let n = String.length text in
  let b = Buffer.create n in
  let rec go i =
    if i < n then
      let next =
        if text.[i] <> '&' then None
        else
          match String.index_from_opt text i ';' with
          | Some j -> (
              match char_ref (String.sub text (i + 1) (j - i - 1)) with
              | Some code when Uchar.is_valid code -> Some (Uchar.of_int code, j + 1)
              | _ -> None)
          | None -> None
      in
      match next with
      | Some (u, after) ->
          Buffer.add_utf_8_uchar b u;
          go after
      | None ->
          Buffer.add_char b text.[i];
          go (i + 1)
  in
  go 0;
  Buffer.contents b

let links html =
  let marker = "href=\"" in
  let n = String.length marker in
  let rec scan from acc =
    match Server.find_from html marker from with
    | None -> List.rev acc
    | Some i -> (
        let start = i + n in
        match String.index_from_opt html start '"' with
        | None -> List.rev acc
        | Some stop ->
            let raw = entity (String.sub html start (stop - start)) in
            let path, _ = Router.split_target raw in
            let local =
              String.length path > 0 && path.[0] = '/'
              && not (String.length path > 1 && (path.[1] = '/' || path.[1] = '\\'))
            in
            let acc = if local && not (List.mem path acc) then path :: acc else acc in
            scan (stop + 1) acc)
  in
  scan 0 []

let missing_page config (App a) ~sleep =
  let env =
    {
      config;
      sleep;
      head_only = false;
      navigate = None;
      build = build_id config (App a);
      current = "";
      root_headers = a.headers;
      exists = (fun ~root:_ ~path:_ -> false);
      form = None;
      csrf = None;
    }
  in
  not_found_page env a.missing "/404.html"
