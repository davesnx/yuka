open Tiny_hashtbl

module Shared_action = Action

let log_error : (string -> unit) ref = ref (fun m -> prerr_endline m)

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

let page ?head:head_html ?early ?import_map ?title ?styles ?scripts build =
  head ~extra:"" ?head:head_html ?early ?import_map ?title ?styles ?scripts ()
  ^ to_string build ^ "</body></html>"

let fill_script = Printer.fill_script

let value_script id (json : Json.t) =
  "<script type=\"application/json\" data-yuka-async=\"" ^ id ^ "\">"
  ^ Json.to_string json ^ "</script>"

let fill_chunk id html =
  "<template data-yuka-fill=\"" ^ id ^ "\">" ^ html
  ^ "</template><script>__yukaFill(\"" ^ id ^ "\")</script>"

let pending_id = function
  | Types.Pending_await { id; _ } | Types.Pending_async { id; _ } -> id

let drive ?preload ~timeout ~sleep build ~on_shell ~on_fill ~on_value =
  let session = Printer.session ~streaming:true ~islands_only:true in
  session.preload <- preload;
  let shell = Printer.print session (fun () -> build ()) in
  let result, resolve, fail = Async.make () in
  let chain = ref (on_shell shell) in
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
      fail (Web.exn_to_string exn)
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
            Async.on_settled async (fun status -> settled_value id status))
      items
  and check_done () = if !outstanding = [] then conclude ()
  and settled_fill id inside fill =
    if (not !finished) && is_outstanding id then begin
      remove id;
      match fill () with
      | html ->
          register ();
          let links = Printer.take_links session in
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
        | Async.Failed m -> `Assoc [ ("error", `String m) ]
        | Async.Pending -> `Assoc [ ("error", `String "pending") ]
      in
      emit (fun () -> on_value id json);
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
                let links = Printer.take_links session in
                emit (fun () -> on_fill id inside_island links html);
                expire ()
            | exception exn -> abort exn)
        | Types.Pending_async { id; _ } ->
            emit (fun () ->
                on_value id (`Assoc [ ("error", `String "timeout") ]));
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
    ~on_shell:(fun shell ->
      write
        (head ~extra:fill_script ?head:head_html ?early ?import_map ?title
           ?styles ?scripts ())
      >>= fun () -> write shell)
    ~on_fill:(fun id _ links html -> write (links ^ fill_chunk id html))
    ~on_value:(fun id json -> write (value_script id json))
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

let render_settled ?(timeout = 10.) ?preload ~sleep build =
  let document = ref "" in
  let values = Buffer.create 64 in
  Async.map
    (fun () -> !document ^ Buffer.contents values)
    (drive ?preload ~timeout ~sleep
       (fun () -> build ())
       ~on_shell:(fun shell ->
         document := shell;
         Async.resolved ())
       ~on_fill:(fun id inside links html ->
         document := fill_marker !document id ~inside html;
         Buffer.add_string values links;
         Async.resolved ())
       ~on_value:(fun id json ->
         Buffer.add_string values (value_script id json);
         Async.resolved ()))

let respond ?(navigating = false) ?head:head_html ?early ?import_map ?timeout
    ?title ?styles ?scripts ?preload ~sleep ~write build =
  if navigating then
    Async.bind (render_settled ?timeout ?preload ~sleep build) (fun body ->
        write
          (head ~extra:"" ?head:head_html ?early ?import_map ?title ?styles
             ?scripts ()
          ^ body ^ "</body></html>"))
  else
    stream ?head:head_html ?early ?import_map ?timeout ?title ?styles ?scripts
      ?preload ~sleep ~write build

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

module Action = struct
  exception Rejected of string

  let reject message = raise (Rejected message)
  let reject_prefix = "yuka.reject:"
  let rejected message = Async.failed (reject_prefix ^ message)

  type outcome = Output of Json.t | Bad_input of string

  let registry : (string, Json.t -> outcome Async.t) Hashtbl.t =
    Hashtbl.create 16

  let rejection message =
    let n = String.length reject_prefix in
    if String.length message >= n && String.sub message 0 n = reject_prefix then
      Some (String.sub message n (String.length message - n))
    else None

  let transport name input =
    match Hashtbl.find_opt registry name with
    | None -> Async.failed ("unknown action " ^ name)
    | Some handler ->
        let settled, resolve, fail = Async.make () in
        Async.on_settled (handler input) (function
          | Async.Done (Output j) -> resolve j
          | Async.Done (Bad_input m) -> fail m
          | Async.Failed m -> fail (Option.value (rejection m) ~default:m)
          | Async.Pending -> ());
        settled

  let install () = Shared_action.transport := transport

  let implement action f =
    let name = Shared_action.name action in
    if Hashtbl.mem registry name then
      invalid_arg ("Yuka.Server.Action.implement: already implemented: " ^ name);
    let input = action.Shared_action.input
    and output = action.Shared_action.output in
    Hashtbl.replace registry name (fun json ->
        match Codec.decode input json with
        | Error m -> Async.resolved (Bad_input m)
        | Ok v ->
            let run =
              match f v with
              | async -> async
              | exception Rejected m -> rejected m
              | exception exn -> Async.failed (Web.exn_to_string exn)
            in
            Async.map (fun o -> Output (Codec.encode output o)) run);
    install ()
end

let max_body = 1_048_576

let same_origin ~origin ~host =
  match origin with
  | None -> true
  | Some origin -> (
      let origin_host =
        match String.index_opt origin ':' with
        | Some i when i + 3 <= String.length origin ->
            String.sub origin (i + 3) (String.length origin - i - 3)
        | _ -> origin
      in
      match host with
      | Some h ->
          String.equal (String.lowercase_ascii h)
            (String.lowercase_ascii origin_host)
      | None -> false)

let is_json = function
  | None -> false
  | Some ct ->
      let media = List.hd (String.split_on_char ';' ct) in
      String.equal
        (String.lowercase_ascii (String.trim media))
        "application/json"

let handle_action ~name ~content_type ~origin ~host ~body =
  let error_body message =
    Json.to_string (`Assoc [ ("error", `String message) ])
  in
  let error status message = Async.resolved (status, error_body message) in
  if not (same_origin ~origin ~host) then error 403 "origin mismatch"
  else
    match Hashtbl.find_opt Action.registry name with
    | None -> error 404 ("unknown action " ^ name)
    | Some handler ->
        if not (is_json content_type) then
          error 415 "content type must be application/json"
        else if String.length body > max_body then
          error 413 "request too large"
        else (
          match Json.of_string body with
          | Error m -> error 400 ("invalid JSON: " ^ m)
          | Ok json ->
              let result, resolve, _ = Async.make () in
              Async.on_settled (handler json) (function
                | Async.Done (Action.Bad_input m) ->
                    resolve (400, error_body ("invalid input: " ^ m))
                | Async.Done (Action.Output j) ->
                    resolve (200, Json.to_string (`Assoc [ ("ok", j) ]))
                | Async.Failed m -> (
                    match Action.rejection m with
                    | Some message -> resolve (400, error_body message)
                    | None ->
                        !log_error
                          ("action " ^ name ^ " failed: " ^ m);
                        resolve (500, error_body "action failed"))
                | Async.Pending -> ());
              result)
