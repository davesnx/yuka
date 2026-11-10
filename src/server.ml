let log_error = Types.log_error

let to_string build =
  Printer.print
    (Printer.session ~streaming:false ~islands_only:true)
    (fun () -> build ())

let import_map_script = function
  | [] -> []
  | entries ->
      let imports : Json.t =
        `Assoc (List.map (fun (k, v) -> (k, `String v)) entries)
      in
      [ "<script type=\"importmap\">"
        ^ Json.to_string (`Assoc [ ("imports", imports) ])
        ^ "</script>" ]

let import_map ~url packages =
  let url =
    if String.length url > 0 && url.[String.length url - 1] = '/' then
      String.sub url 0 (String.length url - 1)
    else url
  in
  List.map
    (fun pkg -> (pkg ^ "/", url ^ "/node_modules/" ^ pkg ^ "/"))
    packages

let head ~extra ?head ?(early = false) ?(import_map = []) ?(title = "")
    ?(styles = []) ?(scripts = []) () =
  let attr = Printer.escape ~quote:true in
  let styles =
    List.map
      (fun s -> "<link rel=\"stylesheet\" href=\"" ^ attr s ^ "\">")
      styles
  in
  let scripts =
    List.map
      (fun s ->
        "<script type=\"module\""
        ^ (if early then " async" else "")
        ^ " src=\"" ^ attr s ^ "\"></script>")
      scripts
  in
  String.concat ""
    ([ "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>";
       Printer.escape ~quote:false title;
       "</title>" ]
    @ import_map_script import_map
    @ [ extra; Option.value head ~default:"" ]
    @ styles @ scripts @ [ "</head><body>" ])

let document ?head:head_html ?early ?import_map ?title ?styles ?scripts build =
  head ~extra:"" ?head:head_html ?early ?import_map ?title ?styles ?scripts ()
  ^ to_string build ^ "</body></html>"

let fill_script = Printer.fill_script

let value_script id (json : Json.t) =
  "<script type=\"application/json\" data-yuka-async=\"" ^ id ^ "\">"
  ^ Json.to_string json ^ "</script>"

let fill_chunk id html =
  "<template data-yuka-fill=\"" ^ id ^ "\">" ^ html
  ^ "</template><script>__yukaFill(\"" ^ id ^ "\")</script>"

let reject_prefix = Types.reject_prefix
let rejection = Types.rejection

let timeout_answer () : Json.t =
  `Assoc [ ("error", Status.error_codec.encode (Status.Network "timeout")) ]

let pending_id = function
  | Types.Pending_await { id; _ } | Types.Pending_async { id; _ } -> id
  | Types.Pending_answer { key; _ } -> "answer:" ^ key

let drive ?preload ?entry ?current ?(id_prefix = "") ?form ?csrf ~timeout ~sleep build ~on_shell
    ~on_fill ~on_value =
  let session = Printer.session ~streaming:true ~islands_only:true in
  session.form <- form;
  session.csrf <- csrf;
  session.preload <- preload;
  session.entry <- entry;
  session.current <- current;
  session.id_prefix <- id_prefix;
  let shell = Printer.print session (fun () -> build ()) in
  let fills =
    List.exists
      (function Types.Pending_await _ -> true | Types.Pending_async _ | Types.Pending_answer _ -> false)
      session.pending
  in
  let result, resolve, fail = Async.make () in
  let chain = ref (on_shell ~fills shell) in
  let emit f = chain := Async.bind !chain f in
  let outstanding = ref [] in
  let finished = ref false in
  let on_timeout : (unit -> unit) option ref = ref None in
  let conclude () =
    if not !finished then begin
      finished := true;
      on_timeout := None;
      Async.on_settled !chain (function
        | Async.Done () -> resolve ()
        | Async.Failed m -> fail m
        | Async.Pending -> ())
    end
  in
  let abort exn =
    if not !finished then begin
      finished := true;
      on_timeout := None;
      let message = Web.exn_to_string exn in
      Async.on_settled !chain (fun _ -> fail message)
    end
  in
  let remove id =
    outstanding := List.filter (fun p -> pending_id p <> id) !outstanding
  in
  let is_outstanding id = List.exists (fun p -> pending_id p = id) !outstanding in
  let rec register () =
    let items = Printer.take_pending session in
    outstanding := !outstanding @ items;
    List.iter
      (fun pending ->
        match pending with
        | Types.Pending_await { id; subscribe; fill; inside_island; _ } ->
            subscribe (fun () -> settled_fill id inside_island fill)
        | Types.Pending_async { id; async } ->
            Async.on_settled async (fun status -> settled_value id status)
        | Types.Pending_answer { key; answer } ->
            Async.on_settled answer (fun status -> settled_answer key status))
      items
  and check_done () = if !outstanding = [] then conclude ()
  and settled_fill id inside fill =
    if (not !finished) && is_outstanding id then begin
      remove id;
      match fill () with
      | html ->
          register ();
          let links = Printer.take_answers session ^ Printer.take_links session in
          emit (fun () -> on_fill id inside links html);
          check_done ()
      | exception exn -> abort exn
    end
  and settled_value id status =
    if (not !finished) && is_outstanding id then begin
      remove id;
      let json : Json.t =
        match status with
        | Async.Done v -> `Assoc [ ("ok", v) ]
        | Async.Failed m -> `Assoc [ ("error", `String (Types.async_error id m)) ]
        | Async.Pending -> `Assoc [ ("error", `String "pending") ]
      in
      emit (fun () -> on_value (value_script id json));
      check_done ()
    end
  and settled_answer key status =
    let id = "answer:" ^ key in
    if (not !finished) && is_outstanding id then begin
      remove id;
      let json : Json.t =
        match status with
        | Async.Done j -> j
        | Async.Failed _ | Async.Pending -> timeout_answer ()
      in
      emit (fun () -> on_value (Printer.answer_script key json));
      check_done ()
    end
  in
  let rec expire () =
    match !outstanding with
    | [] -> conclude ()
    | pending :: _ -> (
        remove (pending_id pending);
        match pending with
        | Types.Pending_await { id; fill_failed; inside_island; _ } -> (
            match fill_failed "timeout" with
            | html ->
                register ();
                let links = Printer.take_answers session ^ Printer.take_links session in
                emit (fun () -> on_fill id inside_island links html);
                expire ()
            | exception exn -> abort exn)
        | Types.Pending_async { id; _ } ->
            emit (fun () ->
                on_value (value_script id (`Assoc [ ("error", `String "timeout") ])));
            expire ()
        | Types.Pending_answer { key; _ } ->
            emit (fun () -> on_value (Printer.answer_script key (timeout_answer ())));
            expire ())
  in
  register ();
  if !outstanding = [] then conclude ()
  else
    begin
      on_timeout := Some expire;
      Async.on_settled (sleep timeout) (fun _ ->
          match !on_timeout with
          | None -> ()
          | Some f ->
              on_timeout := None;
              f ())
    end;
  result

let stream ?head:head_html ?early ?import_map ?(timeout = 10.) ?title ?styles
    ?scripts ?preload ~sleep ~write build =
  let ( >>= ) = Async.bind in
  drive ?preload ~timeout ~sleep
    (fun () -> build ())
    ~on_shell:(fun ~fills shell ->
      write
        (head ~extra:(if fills then fill_script else "") ?head:head_html ?early ?import_map ?title
           ?styles ?scripts ())
      >>= fun () -> write shell)
    ~on_fill:(fun id _ links html -> write (links ^ fill_chunk id html))
    ~on_value:write
  >>= fun () -> write "</body></html>"

let find_from text part from =
  let n = String.length part in
  let rec at i =
    if i + n > String.length text then None
    else if String.sub text i n = part then Some i
    else at (i + 1)
  in
  at from

let fill_marker doc id ~inside html =
  let start_marker = "<!--[" ^ id ^ "-->" in
  match find_from doc start_marker 0 with
  | None -> doc
  | Some start ->
      let content = start + String.length start_marker in
      let rec close depth from =
        match find_from doc "<!--" from with
        | None -> String.length doc
        | Some i ->
            let at part =
              i + String.length part <= String.length doc
              && String.sub doc i (String.length part) = part
            in
            if at "<!--]-->" then
              if depth = 1 then i else close (depth - 1) (i + 8)
            else if at "<!--[" then close (depth + 1) (i + 5)
            else close depth (i + 4)
      in
      let stop = close 1 content in
      let opening = if inside then "<!--[-->" else "" in
      let closing = if inside then 0 else min 8 (String.length doc - stop) in
      String.sub doc 0 start ^ opening ^ html
      ^ String.sub doc (stop + closing) (String.length doc - stop - closing)

let settled ?(timeout = 10.) ?preload ?entry ?current ?id_prefix ?form ?csrf ~sleep build =
  let document = ref "" in
  let values = Buffer.create 64 in
  Async.map
    (fun () -> !document ^ Buffer.contents values)
    (drive ?preload ?entry ?current ?id_prefix ?form ?csrf ~timeout ~sleep
       (fun () -> build ())
       ~on_shell:(fun ~fills:_ shell ->
         document := shell;
         Async.return ())
       ~on_fill:(fun id inside links html ->
         document := fill_marker !document id ~inside html;
         Buffer.add_string values links;
         Async.return ())
       ~on_value:(fun html ->
         Buffer.add_string values html;
         Async.return ()))

let normalize path =
  let rec go p =
    if String.length p >= 2 && String.sub p 0 2 = "./" then
      go (String.sub p 2 (String.length p - 2))
    else p
  in
  go path

let preload_urls ~manifest ~base ?metafile () =
  let parse what text =
    match Json.of_string text with
    | Ok j -> j
    | Error m ->
        invalid_arg ("Yuka.Server.preload_urls: bad " ^ what ^ " JSON: " ^ m)
  in
  let paths =
    match parse "manifest" manifest with
    | `Assoc fields ->
        List.map
          (fun (name, v) ->
            match v with
            | `String p -> (name, normalize p)
            | _ ->
                invalid_arg
                  ("Yuka.Server.preload_urls: manifest entry " ^ name
                 ^ " is not a string"))
          fields
    | _ -> invalid_arg "Yuka.Server.preload_urls: manifest is not an object"
  in
  let outputs =
    match metafile with
    | None -> None
    | Some text -> (
        match parse "metafile" text with
        | `Assoc top -> (
            match List.assoc_opt "outputs" top with
            | Some (`Assoc outs) ->
                Some
                  (List.filter_map
                     (fun (file, v) ->
                       match v with
                       | `Assoc o -> (
                           match List.assoc_opt "entryPoint" o with
                           | Some (`String e) -> Some (file, normalize e)
                           | _ -> None)
                       | _ -> None)
                     outs)
            | _ ->
                invalid_arg
                  "Yuka.Server.preload_urls: metafile has no outputs object")
        | _ -> invalid_arg "Yuka.Server.preload_urls: metafile is not an object")
  in
  fun name ->
    match List.assoc_opt name paths with
    | None -> None
    | Some path -> (
        match outputs with
        | None -> Some (base ^ path)
        | Some outs -> (
            match List.find_opt (fun (_, e) -> e = path) outs with Some (file, _) -> Some (base ^ file) | None -> None))

exception Rejected of string

let reject message = raise (Rejected message)
let rejected message = Async.failed (reject_prefix ^ message)
let guarded f x = Async.guard (fun x -> match f x with a -> a | exception Rejected m -> rejected m) x

type answer = Output of Json.t | Bad_input of string

let registry : (string * (Json.t -> answer Async.t)) list ref = ref []

let find_action name =
  Option.map snd (List.find_opt (fun (n, _) -> String.equal n name) !registry)


type failure = Unknown | Bad of string | Refused of string | Broke of string

let run name input k =
  match find_action name with
  | None ->
      k (Error Unknown);
      ignore
  | Some handler ->
      let live = ref true in
      Async.on_settled (handler input) (fun st ->
          if !live then
            match st with
            | Async.Done (Output j) -> k (Ok j)
            | Async.Done (Bad_input m) -> k (Error (Bad m))
            | Async.Failed m -> (
                match rejection m with
                | Some message -> k (Error (Refused message))
                | None -> k (Error (Broke m)))
            | Async.Pending -> ());
      fun () -> live := false

let transport name input =
  let settled, resolve, fail = Async.make () in
  let (_ : unit -> unit) =
    run name input (function
      | Ok j -> resolve j
      | Error Unknown -> fail ("unknown action " ^ name)
      | Error (Bad m | Refused m | Broke m) -> fail m)
  in
  settled

let send name input k =
  run name input (fun r ->
      k
        (match r with
        | Ok j -> Ok j
        | Error Unknown -> Error Status.Not_found
        | Error (Bad m) -> Error (Status.Rejected ("invalid input: " ^ m))
        | Error (Refused m) -> Error (Status.Rejected m)
        | Error (Broke m) ->
            !log_error ("action " ^ name ^ " failed: " ^ m);
            Error Status.Server))

let register action f encode =
  let name = Action.name action in
  if Option.is_some (find_action name) then
    invalid_arg ("Yuka.Server.Action.implement: already implemented: " ^ name);
  let input = action.Action.input in
  registry :=
    ( name,
      fun json ->
        match Codec.decode input json with
        | Error m -> Async.return (Bad_input m)
        | Ok v ->
            Async.map (fun o -> Output (encode o)) (guarded f v) )
    :: !registry;
  Action.transport := transport;
  Remote.server_send := send

let implement action f = register action f (Codec.encode action.Action.output)

type form_outcome = Saved of string option | Unprocessable of (string option * string) list

let forms : (string * ((string * string) list -> form_outcome Async.t)) list ref = ref []
let find_form name = List.assoc_opt name !forms

let implement_form (type i o f) (action : (i, (o, f Form_core.errors) result, _) Action.t) ?redirect
    (f : i -> (o, f Form_core.errors) result Async.t) =
  let t : (i, f) Form_core.t =
    match action.Action.form with
    | Some (Action.Form (t, _)) -> t
    | None -> invalid_arg ("Yuka.Server.Form.implement: " ^ Action.name action ^ " is not a form action")
  in
  let output = action.Action.output in
  let encode result =
    match (result, Codec.encode output result) with
    | Ok o, `Assoc fields -> (
        match redirect with
        | Some r -> `Assoc (fields @ [ ("redirect", `String (r o)) ])
        | None -> `Assoc fields)
    | _, j -> j
  in
  register action f encode;
  let run values =
    match Form_core.decode t values with
    | Error e -> Async.return (Unprocessable (Form_core.named t e))
    | Ok input ->
        Async.map
          (function
            | Ok o -> Saved (Option.map (fun r -> r o) redirect)
            | Error e -> Unprocessable (Form_core.named t e))
          (guarded f input)
  in
  forms := (Action.name action, run) :: !forms

let max_body = 1_048_576

let authority url =
  match String.index_opt url ':' with
  | Some i when i + 3 <= String.length url && String.sub url (i + 1) 2 = "//" ->
      let rest = String.sub url (i + 3) (String.length url - i - 3) in
      let stop =
        Option.value ~default:(String.length rest)
          (String.index_opt (String.map (function '?' | '#' -> '/' | c -> c) rest) '/')
      in
      Some (String.sub rest 0 stop)
  | _ -> None

let same_origin ~origin ~host =
  match (authority origin, host) with
  | Some a, Some h -> String.equal (String.lowercase_ascii a) (String.lowercase_ascii h)
  | _ -> false

let trusted_origin header =
  match header "origin" with
  | Some origin -> same_origin ~origin ~host:(header "host")
  | None -> header "sec-fetch-site" = Some "same-origin"

let local_location ~host location =
  (not (String.exists (fun c -> c < ' ' || c = '\127') location))
  &&
  match location with
  | "" -> false
  | l when l.[0] = '/' -> not (String.length l > 1 && (l.[1] = '/' || l.[1] = '\\'))
  | l -> same_origin ~origin:l ~host

let media_type = function
  | None -> None
  | Some ct -> Some (String.lowercase_ascii (String.trim (List.hd (String.split_on_char ';' ct))))

let is_json ct = media_type ct = Some "application/json"
let action_error status message = (status, Json.to_string (`Assoc [ ("error", `String message) ]))

let accept_action ~name header =
  if not (trusted_origin header) then Error (action_error 403 "origin mismatch")
  else
    match find_action name with
    | None -> Error (action_error 404 ("unknown action " ^ name))
    | Some handler ->
        if is_json (header "content-type") then Ok handler
        else Error (action_error 415 "content type must be application/json")

let answer_action ~name handler body =
  match Json.of_string body with
  | Error m -> Async.return (action_error 400 ("invalid JSON: " ^ m))
  | Ok json ->
      let result, resolve, _ = Async.make () in
      Async.on_settled (handler json) (function
        | Async.Done (Bad_input m) -> resolve (action_error 400 ("invalid input: " ^ m))
        | Async.Done (Output j) -> resolve (200, Json.to_string (`Assoc [ ("ok", j) ]))
        | Async.Failed m -> (
            match rejection m with
            | Some message -> resolve (action_error 400 message)
            | None ->
                !log_error ("action " ^ name ^ " failed: " ^ m);
                resolve (action_error 500 "action failed"))
        | Async.Pending -> ());
      result

let handle_action ~name ~header ~body =
  match accept_action ~name header with
  | Error e -> Async.return e
  | Ok handler -> answer_action ~name handler body
