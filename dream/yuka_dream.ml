let to_async p =
  let async, resolve, fail = Yuka.Async.make () in
  Lwt.on_any p resolve (fun e -> fail (Printexc.to_string e));
  async

let to_lwt async =
  let p, w = Lwt.wait () in
  Yuka.Async.on_result async (function
    | Ok v -> Lwt.wakeup w v
    | Error m -> Lwt.wakeup_exn w (Failure m));
  p

module Adapter = struct
  type request = Dream.request
  type response = Dream.response
  type 'a io = 'a Lwt.t

  let meth request : Yuka.Router.meth =
    match Dream.method_ request with
    | `GET -> `GET
    | `HEAD -> `HEAD
    | `POST -> `POST
    | `PUT -> `PUT
    | `PATCH -> `PATCH
    | `DELETE -> `DELETE
    | `OPTIONS -> `OPTIONS
    | `CONNECT -> `Other "CONNECT"
    | `TRACE -> `Other "TRACE"
    | `Method m -> `Other m

  let target = Dream.target
  let header = Dream.header
  let body request ~limit =
    let stream = Dream.body_stream request in
    let refuse () = Lwt.map (fun () -> None) (Dream.close stream) in
    let buffer = Buffer.create 1024 in
    let rec read () =
      Lwt.bind (Dream.read stream) (function
        | None -> Lwt.return_some (Buffer.contents buffer)
        | Some chunk ->
            Buffer.add_string buffer chunk;
            if Buffer.length buffer > limit then refuse () else read ())
    in
    match Option.bind (Dream.header request "Content-Length") int_of_string_opt with
    | Some n when n > limit -> to_async (refuse ())
    | _ -> to_async (read ())

  let respond ({ status; headers; body } : Yuka.Server.http_response) =
    match body with
    | Yuka.Server.String text -> Dream.respond ~code:status ~headers text
    | Yuka.Server.Stream f ->
        Dream.stream ~code:status ~headers (fun stream ->
            to_lwt
              (f (fun text ->
                   to_async (Lwt.bind (Dream.write stream text) (fun () -> Dream.flush stream)))))

  let file request ~root ~path ~headers =
    Lwt.map
      (fun response ->
        (match Dream.status response with
        | `Not_Found -> Dream.set_header response "cache-control" "no-store"
        | _ -> List.iter (fun (name, value) -> Dream.set_header response name value) headers);
        response)
      (Dream.from_filesystem root path request)

  let exists ~root ~path =
    let file = Filename.concat root path in
    Sys.file_exists file && not (Sys.is_directory file)

  let of_async = to_lwt
  let bind = Lwt.bind
  let sleep seconds = to_async (Lwt_unix.sleep seconds)
end

module Live = Yuka.Server.Make (Adapter)

module Fresh = Yuka.Server.Make (struct
  include Adapter

  let exists ~root:_ ~path:_ = false
end)

let tree_digest dir =
  let rec files rel =
    let path = if rel = "" then dir else Filename.concat dir rel in
    if Sys.is_directory path then
      Sys.readdir path |> Array.to_list |> List.sort compare
      |> List.concat_map (fun name -> files (if rel = "" then name else Filename.concat rel name))
    else [ rel ^ "\000" ^ Digest.to_hex (Digest.file path) ]
  in
  Digest.to_hex (Digest.string (String.concat "\n" (files "")))

let log_to_dream () =
  Yuka.Server.log_error := fun message -> Dream.error (fun log -> log "%s" message)

let handler config app =
  log_to_dream ();
  Live.handler config app

let rec make_dirs dir =
  if not (Sys.file_exists dir) then begin
    make_dirs (Filename.dirname dir);
    Sys.mkdir dir 0o755
  end

let write_file path text =
  make_dirs (Filename.dirname path);
  Out_channel.with_open_bin path (fun oc -> Out_channel.output_string oc text)

let rec copy source target =
  if Sys.is_directory source then
    Array.iter
      (fun name -> copy (Filename.concat source name) (Filename.concat target name))
      (Sys.readdir source)
  else write_file target (In_channel.with_open_bin source In_channel.input_all)

let is_html response =
  match Dream.header response "content-type" with
  | Some t -> String.starts_with ~prefix:"text/html" t
  | None -> false

let drain (r : Yuka.Server.http_response) =
  match r.body with
  | Yuka.Server.String text -> Yuka.Async.return text
  | Yuka.Server.Stream f ->
      let b = Buffer.create 4096 in
      Yuka.Async.map
        (fun () -> Buffer.contents b)
        (f (fun text ->
             Buffer.add_string b text;
             Yuka.Async.return ()))

let absolute path =
  let path = if Filename.is_relative path then Filename.concat (Sys.getcwd ()) path else path in
  List.fold_left
    (fun acc part ->
      match (part, acc) with
      | ("" | "."), _ -> acc
      | "..", _ :: rest -> rest
      | "..", [] -> []
      | part, _ -> part :: acc)
    [] (String.split_on_char '/' path)
  |> List.rev

let rec inside ~dir path =
  match (dir, path) with
  | [], _ -> true
  | d :: dir, p :: path -> String.equal d p && inside ~dir path
  | _ :: _, [] -> false

let check_out out config =
  let target = absolute out in
  List.iter
    (fun (_, dir) ->
      if inside ~dir:(absolute dir) target then
        invalid_arg
          (Printf.sprintf "Yuka_dream.prerender: out %S is inside the served directory %S" out dir))
    (Yuka.Server.served_dirs config)

let prerender ~out config app =
  check_out out config;
  let ( let* ) = Lwt.bind in
  let request path = Dream.request ~method_:`GET ~target:path "" in
  let seen = Hashtbl.create 64 and queue = Queue.create () in
  let add path =
    if not (Hashtbl.mem seen path) then begin
      Hashtbl.add seen path ();
      Queue.add path queue
    end
  in
  let warn path fmt = Printf.eprintf ("yuka-dream prerender: %s " ^^ fmt ^^ "\n%!") path in
  let rec visit () =
    match Queue.take_opt queue with
    | None -> Lwt.return_unit
    | Some path -> (
        let* response = Fresh.handler config app (request path) in
        let status = Dream.status_to_int (Dream.status response) in
        let* body = Dream.body response in
        let ok = status >= 200 && status < 300 in
        match Yuka.Server.prerender_file path with
        | Some file when ok ->
            write_file (Filename.concat out file) body;
            if is_html response then
              List.iter
                (fun link ->
                  if (not (Hashtbl.mem seen link))
                     && Yuka.Server.prerenderable config app (request link) link
                  then add link)
                (Yuka.Server.links body);
            visit ()
        | None when ok ->
            warn path "answered %d but cannot be a file name, not written" status;
            visit ()
        | _ ->
            warn path "answered %d, not written" status;
            visit ())
  in
  List.iter add (Yuka.Server.prerender_seeds app);
  let* () = visit () in
  let* page = to_lwt (Yuka.Server.missing_page config app ~sleep:Adapter.sleep) in
  let* text = to_lwt (drain page) in
  write_file (Filename.concat out "404.html") text;
  List.iter (fun (path, css) -> write_file (Filename.concat out path) css) (Yuka.Server.css_files config);
  List.iter
    (fun (prefix, dir) -> copy dir (Filename.concat out (String.sub prefix 1 (String.length prefix - 1))))
    (Yuka.Server.served_dirs config);
  Lwt.return_unit
