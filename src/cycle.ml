open Types

type stop =
  | Not_found
  | Redirect of { status : int; location : string }
  | Fail of string

type page = { title : string; head : string; body : unit -> node }

let page ?(title = "") ?(head = "") body = { title; head; body }

type layer = { key : string; wrap : node -> node }
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
  Async.resolved
    { status; headers = merge_headers [ [ ("content-type", kind) ]; headers ]; body = String text }

let text ?status ?headers s = with_type "text/plain; charset=utf-8" ?status ?headers s
let html ?status ?headers s = with_type "text/html; charset=utf-8" ?status ?headers s
let json ?status ?headers j = with_type "application/json" ?status ?headers (Json.to_string j)

let see_other location =
  Async.resolved { status = 303; headers = [ ("location", location) ]; body = String "" }

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
      find : Router.meth -> string list -> (string * string) list -> 'r Router.lookup;
      resolve : 'req -> 'r -> target;
      missing : fallback;
    }
      -> 'req app

let app ~build ~headers ~find ~resolve ~missing =
  App { build; headers = merge_headers [ headers ]; find; resolve; missing }

let build_id (App a) = a.build

let failure e = Fail (Web.exn_to_string e)

let settle a =
  let r, resolve, _ = Async.make () in
  Async.on_settled a (function
    | Async.Done v -> resolve v
    | Async.Failed m -> resolve (Error (Fail m))
    | Async.Pending -> ());
  r

let protect f = match f () with a -> settle a | exception e -> Async.resolved (Error (failure e))

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
  import_map : (string * string) list;
  preload : string -> string option;
  immutable : string -> bool;
}

let modules ~dir ~entry ~manifest ~packages =
  let entry = Server.normalize entry in
  let base =
    match String.rindex_opt entry '/' with
    | Some i -> "/_yuka/" ^ String.sub entry 0 (i + 1)
    | None -> "/_yuka/"
  in
  {
    dir;
    entry;
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
    import_map = [];
    preload = Server.preload_urls ~manifest ~base:"/_yuka/" ~metafile ();
    immutable = (fun path -> List.exists (String.equal path) hashed);
  }

type config = {
  assets : assets option;
  public : (string list * string) list;
  styles : string list;
  head : string;
  timeout : float;
}

let public_prefix (prefix, dir) =
  match Router.split_path prefix with
  | [] ->
      invalid_arg
        ("Yuka.Server.config: public prefix " ^ Printf.sprintf "%S" prefix
       ^ " has no segment; it would hide every route")
  | segments -> (segments, dir)

let config ?assets ?(public = []) ?(styles = []) ?(head = "") ?(timeout = 10.) () =
  {
    assets;
    public = List.map public_prefix public;
    styles;
    head;
    timeout;
  }

type request = {
  meth : Router.meth;
  target : string;
  header : string -> string option;
  body : unit -> string Async.t;
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
let reply r = Async.resolved (Respond r)
let empty status headers = { status; headers; body = String "" }

type env = {
  config : config;
  sleep : float -> unit Async.t;
  head_only : bool;
  navigating : bool;
  current : string;
  root_headers : (string * string) list;
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
    Server.head ~extra ~head:(env.config.head ^ page.head) ~import_map ~title:page.title
      ~styles:env.config.styles ()
  in
  let build = nest layers page.body in
  let timeout = env.config.timeout and current = env.current in
  if env.navigating then
    Async.map
      (fun body -> { status; headers; body = String (head "" ^ body ^ "</body></html>") })
      (Server.settled ?preload ?entry ~current ~timeout ~sleep:env.sleep build)
  else
    let early = Buffer.create 4096 in
    let writer =
      ref (fun text ->
          Buffer.add_string early text;
          Async.resolved ())
    in
    let write text = !writer text in
    let finished =
      Server.drive ?preload ?entry ~current ~timeout ~sleep:env.sleep build
        ~on_shell:(fun ~fills shell -> write (head (if fills then Server.fill_script else "") ^ shell))
        ~on_fill:(fun id _ links html -> write (links ^ Server.fill_chunk id html))
        ~on_value:(fun id json -> write (Server.value_script id json))
    in
    match Async.status finished with
    | Async.Failed m -> Async.failed m
    | _ ->
    let stream w =
      let flushed = w (Buffer.contents early) in
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
    Async.resolved { status; headers; body = Stream stream }

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
    Async.resolved (internal_error ())
  in
  if env.head_only then Async.resolved (empty 500 headers)
  else
    match render env ~status:500 ~headers fallback.layers (fallback.error 500) with
    | a -> recover a give_up
    | exception e -> give_up (Web.exn_to_string e)

let fail_page env fallback message =
  !Server.log_error message;
  error_page env fallback

let show env ~status ~headers ~fallback layers (page : unit -> page) =
  if env.head_only then Async.resolved (empty status headers)
  else
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
        Async.resolved
          (empty status (merge_headers [ env.root_headers; [ ("location", location); no_store ] ]))
  | Fail m -> fail_page env fallback m

let rec run_guards = function
  | [] -> Async.resolved (Ok ())
  | g :: rest ->
      Async.bind (protect g) (function
        | Ok () -> run_guards rest
        | Error _ as e -> Async.resolved e)

let rule_cache (rules : rules) headers =
  match rules.cache with
  | Some c when not (has_header "cache-control" headers) ->
      headers @ [ ("cache-control", cache_control c) ]
  | _ -> headers

let valid_file_segment s =
  s <> "" && s <> "." && s <> ".."
  && not (String.exists (fun c -> c = '/' || c = '\\' || c = '\000') s)

let file_path raw =
  let parts = List.map (Router.decode ~plus:false) raw in
  if parts <> [] && List.for_all valid_file_segment parts then Some (String.concat "/" parts)
  else None

let asset_miss () = plain 404 "Not Found" []

let serve_file meth ~root ~headers raw =
  match meth with
  | `GET | `HEAD -> (
      match file_path raw with
      | Some path -> Async.resolved (File { root; path; headers })
      | None -> reply (asset_miss ()))
  | _ -> reply (plain 405 "Method Not Allowed" [ ("allow", "GET, HEAD") ])

let action (r : request) raw =
  match (raw, r.meth) with
  | [ name ], `POST ->
      Async.bind (r.body ()) (fun body ->
          Async.map
            (fun (status, json) ->
              Respond
                {
                  status;
                  headers = [ ("content-type", "application/json"); no_store ];
                  body = String json;
                })
            (Server.handle_action ~name:(Router.decode ~plus:false name)
               ~content_type:(r.header "content-type") ~origin:(r.header "origin")
               ~host:(r.header "host") ~body))
  | [ _ ], _ -> reply (plain 405 "Method Not Allowed" [ ("allow", "POST") ])
  | _ -> reply (asset_miss ())

let rec strip_prefix prefix parts =
  match (prefix, parts) with
  | [], rest -> Some rest
  | p :: prefix, x :: rest when String.equal p x -> strip_prefix prefix rest
  | _ -> None

let route env (App a) req (r : request) ~path ~raw ~query =
  let segments = List.map (Router.decode ~plus:false) raw in
  let suffix = match query with Some q when q <> "" -> "?" ^ q | _ -> "" in
  let page_or_error a = Async.map (fun resp -> Respond resp) a in
  match a.find r.meth segments (Router.query r.target) with
  | Router.Redirect { permanent; location } ->
      reply (empty (if permanent then 308 else 307) [ ("location", location ^ suffix) ])
  | Router.Missing -> page_or_error (not_found_page env a.missing path)
  | Router.Wrong_method ms -> (
      match r.meth with
      | `OPTIONS -> reply (empty 204 [ ("allow", allow ms) ])
      | _ -> reply (method_not_allowed (allow ms)))
  | Router.Found found -> (
      match a.resolve req found with
      | exception e -> page_or_error (fail_page env a.missing (Web.exn_to_string e))
      | Page { rules; guards; load; fallback } ->
          page_or_error
            (Async.bind (run_guards guards) (function
              | Error stop -> stopped env fallback path stop
              | Ok () ->
                  Async.bind (protect load) (function
                    | Error stop -> stopped env fallback path stop
                    | Ok plan ->
                        let headers = rule_cache rules (html_headers rules.headers []) in
                        show env ~status:200 ~headers ~fallback plan.layers (fun () -> plan.page))))
      | Handler { rules; same_origin; guards; run } ->
          page_or_error
            (Async.bind (run_guards guards) (function
              | Error stop -> stopped env a.missing path stop
              | Ok () ->
                  if
                    same_origin
                    && not
                         (Server.same_origin ~origin:(r.header "origin") ~host:(r.header "host"))
                  then Async.resolved (plain 403 "Forbidden" [])
                  else
                    let ran =
                      match run () with
                      | resp -> Async.map (fun x -> Ok x) resp
                      | exception e -> Async.resolved (Error (Web.exn_to_string e))
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
                            Async.resolved { resp with headers }))
                      (fail_page env a.missing))))

let handle config (App a as app) ~sleep req (r : request) =
  let path, query = Router.split_target r.target in
  let env =
    {
      config;
      sleep;
      head_only = (match r.meth with `HEAD -> true | _ -> false);
      navigating = Option.is_some (r.header "yuka-navigate");
      current = path;
      root_headers = a.headers;
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
        match List.tl raw with
        | "action" :: rest -> action r rest
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
          let suffix = match query with Some q when q <> "" -> "?" ^ q | _ -> "" in
          reply (empty 308 [ ("location", canonical ^ suffix) ])
        else route env app req r ~path ~raw ~query
    | _ -> Async.map (fun x -> Respond x) (not_found_page env a.missing path)
  in
  let bodyless = function
    | Respond r when env.head_only -> Respond { r with body = String "" }
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
        Async.resolved (last ())
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
  val body : request -> string Async.t
  val respond : http_response -> response io
  val file : request -> root:string -> path:string -> headers:(string * string) list -> response io
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
        body = (fun () -> A.body req);
      }
    in
    A.bind (A.of_async (handle config app ~sleep:A.sleep req view)) (function
      | Respond r -> A.respond r
      | File { root; path; headers } -> A.file req ~root ~path ~headers)
end
