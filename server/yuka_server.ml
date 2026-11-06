let to_string build =
  Yuka.Internal.render_html (fun () -> Yuka.Internal.node (build ()))

let import_map_script = function
  | [] -> []
  | entries ->
      let imports : Yuka.Json.t =
        `Assoc (List.map (fun (k, v) -> (k, `String v)) entries)
      in
      [ "<script type=\"importmap\">"
        ^ Yuka.Json.to_string (`Assoc [ ("imports", imports) ])
        ^ "</script>" ]

let import_map ~url ~dir =
  let root = Filename.concat dir "node_modules" in
  let url =
    if String.length url > 0 && url.[String.length url - 1] = '/' then
      String.sub url 0 (String.length url - 1)
    else url
  in
  let subdirs path =
    match Sys.readdir path with
    | names ->
        let names = Array.to_list names in
        List.sort String.compare
          (List.filter
             (fun n ->
               n <> "" && n.[0] <> '.' && Sys.is_directory (Filename.concat path n))
             names)
    | exception Sys_error _ -> []
  in
  List.concat_map
    (fun name ->
      let packages =
        if name.[0] = '@' then
          List.map (fun sub -> name ^ "/" ^ sub) (subdirs (Filename.concat root name))
        else [ name ]
      in
      List.map
        (fun pkg -> (pkg ^ "/", url ^ "/node_modules/" ^ pkg ^ "/"))
        packages)
    (subdirs root)

let head ~extra ?head ?(early = false) ?(import_map = []) ?(title = "") ?(styles = []) ?(scripts = []) () =
  let esc = Dream.html_escape in
  let styles =
    List.map (fun s -> Printf.sprintf "<link rel=\"stylesheet\" href=\"%s\">" (esc s)) styles
  in
  let scripts =
    List.map
      (fun s ->
        Printf.sprintf "<script type=\"module\"%s src=\"%s\"></script>"
          (if early then " async" else "")
          (esc s))
      scripts
  in
  String.concat ""
    ([ "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>"; esc title; "</title>" ]
    @ import_map_script import_map
    @ [ extra; Option.value head ~default:"" ]
    @ styles @ scripts @ [ "</head><body>" ])

let page ?head:head_html ?early ?import_map ?title ?styles ?scripts build =
  head ~extra:"" ?head:head_html ?early ?import_map ?title ?styles ?scripts () ^ to_string build ^ "</body></html>"

let fill_script = Yuka.Internal.fill_script

type event =
  | Fill of string * (unit -> string)
  | Value of string * Yuka.Json.t Yuka.Async.status

let value_script id (json : Yuka.Json.t) =
  Printf.sprintf
    "<script type=\"application/json\" data-yuka-async=\"%s\">%s</script>"
    id (Yuka.Json.to_string json)

let drive ~timeout build ~on_shell ~on_fill ~on_value =
  let open Lwt.Syntax in
  let session = Yuka.Internal.session ~streaming:true in
  let shell =
    Yuka.Internal.print session (fun () -> Yuka.Internal.node (build ()))
  in
  let* () = on_shell shell in
  let events, push = Lwt_stream.create () in
  let outstanding = ref [] in
  let id_of = function
    | Yuka.Internal.Pending_await { id; _ } | Yuka.Internal.Pending_async { id; _ } -> id
  in
  let register () =
    List.iter
      (fun pending ->
        outstanding := !outstanding @ [ pending ];
        match pending with
        | Yuka.Internal.Pending_await { id; subscribe; fill; _ } ->
            subscribe (fun () -> push (Some (Fill (id, fill))))
        | Yuka.Internal.Pending_async { id; async } ->
            Yuka.Async.on_settled async (fun st -> push (Some (Value (id, st)))))
      (Yuka.Internal.take_pending session)
  in
  let remove id =
    outstanding := List.filter (fun p -> id_of p <> id) !outstanding
  in
  let write_fill = on_fill in
  let write_value = on_value in
  register ();
  let timer = Lwt_unix.sleep timeout in
  let rec expire () =
    match !outstanding with
    | [] -> Lwt.return_unit
    | pending :: _ -> (
        remove (id_of pending);
        match pending with
        | Yuka.Internal.Pending_await { id; fill_failed; _ } ->
            let html = fill_failed "timeout" in
            register ();
            let* () = write_fill id html in
            expire ()
        | Yuka.Internal.Pending_async { id; _ } ->
            let* () = write_value id (`Assoc [ ("error", `String "timeout") ]) in
            expire ())
  in
  let rec loop () =
    if !outstanding = [] then Lwt.return_unit
    else
      let* next =
        Lwt.choose
          [ Lwt.map (fun e -> `Event e) (Lwt_stream.get events);
            Lwt.map (fun () -> `Timeout) timer ]
      in
      match next with
      | `Timeout | `Event None -> expire ()
      | `Event (Some (Fill (id, fill))) ->
          remove id;
          let html = fill () in
          register ();
          let* () = write_fill id html in
          loop ()
      | `Event (Some (Value (id, status))) ->
          remove id;
          let json : Yuka.Json.t =
            match status with
            | Yuka.Async.Done v -> `Assoc [ ("ok", v) ]
            | Yuka.Async.Failed m -> `Assoc [ ("error", `String m) ]
            | Yuka.Async.Pending -> `Assoc [ ("error", `String "pending") ]
          in
          let* () = write_value id json in
          loop ()
  in
  let* () = loop () in
  Lwt.cancel timer;
  Lwt.return_unit

let stream ?head:head_html ?early ?import_map ?(timeout = 10.) ?title ?styles ?scripts
    build write =
  let open Lwt.Syntax in
  let* () =
    drive ~timeout build
      ~on_shell:(fun shell ->
        let* () =
          write
            (head ~extra:fill_script ?head:head_html ?early ?import_map ?title ?styles
               ?scripts ())
        in
        write shell)
      ~on_fill:(fun id html ->
        write
          (Printf.sprintf
             "<template data-yuka-fill=\"%s\">%s</template><script>__yukaFill(\"%s\")</script>"
             id html id))
      ~on_value:(fun id json -> write (value_script id json))
  in
  write "</body></html>"

let find_from text part from =
  let n = String.length part in
  let rec at i =
    if i + n > String.length text then None
    else if String.sub text i n = part then Some i
    else at (i + 1)
  in
  at from

let fill_marker doc id html =
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
      String.sub doc 0 start ^ "<!--[-->" ^ html
      ^ String.sub doc stop (String.length doc - stop)

let render_settled ?(timeout = 10.) build =
  let document = ref "" in
  let values = Buffer.create 64 in
  let open Lwt.Syntax in
  let* () =
    drive ~timeout build
      ~on_shell:(fun shell -> document := shell; Lwt.return_unit)
      ~on_fill:(fun id html ->
        document := fill_marker !document id html;
        Lwt.return_unit)
      ~on_value:(fun id json ->
        Buffer.add_string values (value_script id json);
        Lwt.return_unit)
  in
  Lwt.return (!document ^ Buffer.contents values)

let respond ?status ?request ?head:head_html ?early ?import_map ?timeout ?title
    ?styles ?scripts build =
  let navigating =
    match request with
    | Some request -> Dream.header request "Yuka-Navigate" = Some "1"
    | None -> false
  in
  let headers =
    [ ("Content-Type", "text/html; charset=utf-8"); ("Vary", "Yuka-Navigate") ]
  in
  if navigating then
    Lwt.bind (render_settled ?timeout build) (fun body ->
        Dream.html ?status ~headers:[ ("Vary", "Yuka-Navigate") ]
          (head ~extra:"" ?head:head_html ?early ?import_map ?title ?styles
             ?scripts ()
          ^ body ^ "</body></html>"))
  else
    Dream.stream ?status ~headers (fun out ->
        stream ?head:head_html ?early ?import_map ?timeout ?title ?styles
          ?scripts build (fun chunk ->
            let open Lwt.Syntax in
            let* () = Dream.write out chunk in
            Dream.flush out))

module Action = struct
  exception Rejected of string

  let reject message = raise (Rejected message)

  type outcome = Output of Yuka.Json.t | Bad_input of string

  let registry : (string, Yuka.Json.t -> outcome Lwt.t) Hashtbl.t =
    Hashtbl.create 16

  let transport name input =
    match Hashtbl.find_opt registry name with
    | None -> Yuka.Async.failed ("unknown action " ^ name)
    | Some handler ->
        let async, resolve, fail = Yuka.Async.make () in
        ignore
          (Lwt.try_bind
             (fun () -> handler input)
             (function Output j -> resolve j; Lwt.return_unit
                     | Bad_input m -> fail m; Lwt.return_unit)
             (function
               | Rejected m -> fail m; Lwt.return_unit
               | e -> fail (Printexc.to_string e); Lwt.return_unit));
        async

  let install () = Yuka.Internal.call_action := transport

  let implement action f =
    let name = Yuka.Action.name action in
    if Hashtbl.mem registry name then
      invalid_arg ("Yuka_server.Action.implement: already implemented: " ^ name);
    let input, output = Yuka.Internal.action_codecs action in
    Hashtbl.replace registry name (fun json ->
        match Yuka.Codec.decode input json with
        | Error m -> Lwt.return (Bad_input m)
        | Ok v -> Lwt.map (fun o -> Output (Yuka.Codec.encode output o)) (f v));
    install ()
end

let reply status (json : Yuka.Json.t) =
  Dream.json ~status (Yuka.Json.to_string json)

let error status message = reply status (`Assoc [ ("error", `String message) ])

let same_origin request =
  match Dream.header request "Origin" with
  | None -> true
  | Some origin -> (
      let host =
        match String.index_opt origin ':' with
        | Some i when i + 3 <= String.length origin ->
            String.sub origin (i + 3) (String.length origin - i - 3)
        | _ -> origin
      in
      match Dream.header request "Host" with
      | Some h -> String.equal (String.lowercase_ascii h) (String.lowercase_ascii host)
      | None -> false)

let is_json request =
  match Dream.header request "Content-Type" with
  | None -> false
  | Some ct ->
      let media = List.hd (String.split_on_char ';' ct) in
      String.equal (String.lowercase_ascii (String.trim media)) "application/json"

let max_body = 1_048_576

let read_limited request =
  let open Lwt.Syntax in
  match Option.bind (Dream.header request "Content-Length") int_of_string_opt with
  | Some n when n > max_body -> Lwt.return_none
  | _ ->
      let stream = Dream.body_stream request in
      let buffer = Buffer.create 256 in
      let rec loop () =
        let* chunk = Dream.read stream in
        match chunk with
        | None -> Lwt.return_some (Buffer.contents buffer)
        | Some data ->
            Buffer.add_string buffer data;
            if Buffer.length buffer > max_body then Lwt.return_none else loop ()
      in
      loop ()

let handle request =
  let name = Dream.param request "name" in
  if not (same_origin request) then error `Forbidden "origin mismatch"
  else
    match Hashtbl.find_opt Action.registry name with
    | None -> error `Not_Found ("unknown action " ^ name)
    | Some handler ->
        if not (is_json request) then
          error `Unsupported_Media_Type "content type must be application/json"
        else
          let open Lwt.Syntax in
          let* body = read_limited request in
          match body with
          | None -> error `Payload_Too_Large "request too large"
          | Some body ->
          match Yuka.Json.of_string body with
          | Error m -> error `Bad_Request ("invalid JSON: " ^ m)
          | Ok json ->
              Lwt.catch
                (fun () ->
                  let* outcome = handler json in
                  match outcome with
                  | Action.Bad_input m ->
                      error `Bad_Request ("invalid input: " ^ m)
                  | Action.Output j -> reply `OK (`Assoc [ ("ok", j) ]))
                (function
                | Action.Rejected m -> error `Bad_Request m
                | exn ->
                  Dream.error (fun log ->
                      log ~request "action %s failed: %s" name
                        (Printexc.to_string exn));
                  error `Internal_Server_Error "action failed")

let route = Dream.post "/_yuka/action/:name" handle

module Async = struct
  let of_lwt promise =
    let async, resolve, fail = Yuka.Async.make () in
    Lwt.on_any promise resolve (fun exn ->
        Dream.error (fun log -> log "async failed: %s" (Printexc.to_string exn));
        fail "failed");
    async
end
