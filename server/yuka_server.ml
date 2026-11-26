module Reqd = Ache.Request_descriptor
module Writer = Ache.Body.Writer

type sessions = Session.t

let sessions = Session.make

module Signed_cookie = struct
  let set = Session.signed_cookie
  let get = Session.verified_cookie
end

type connection = {
  fd : Lwt_unix.file_descr;
  peer : Unix.sockaddr;
  closed : unit Lwt.t;
  close_done : unit Lwt.u;
  write_timer : Ache_lwt.Timeout.t;
  live_timeout : float;
  mutable heard : Ache_lwt.Timeout.t option;
  mutable request : Reqd.t option;
  mutable going_away : (unit -> unit) option;
  mutable winding_down : bool;
}

type handler = connection -> Reqd.t -> unit

let peer c = c.peer

let to_async p =
  let async, resolve, fail = Yuka.Async.make () in
  Lwt.on_any p resolve (fun e -> fail (Printexc.to_string e));
  async

let to_lwt async =
  let p, w = Lwt.wait () in
  Yuka.Async.on_result async (function Ok v -> Lwt.wakeup w v | Error m -> Lwt.wakeup_exn w (Failure m));
  p

let default_log level message = try Yuka.Server.Adapter.default_sink level message with _ -> ()

let address = function
  | Unix.ADDR_INET (a, port) -> Printf.sprintf "%s:%d" (Unix.string_of_inet_addr a) port
  | Unix.ADDR_UNIX path -> if path = "" then "a local socket" else path

let mark_closed c = if Lwt.is_sleeping c.closed then Lwt.wakeup_later c.close_done ()

let close_socket c =
  mark_closed c;
  match Lwt_unix.state c.fd with
  | Lwt_unix.Closed -> Lwt.return_unit
  | Lwt_unix.Opened | Lwt_unix.Aborted _ ->
      (try Lwt_unix.shutdown c.fd Unix.SHUTDOWN_ALL with Unix.Unix_error _ -> ());
      Lwt.catch (fun () -> Lwt_unix.close c.fd) (fun _ -> Lwt.return_unit)

let force_close c =
  if Lwt.is_sleeping c.closed then begin
    (try Lwt_unix.shutdown c.fd Unix.SHUTDOWN_ALL with Unix.Unix_error _ -> ());
    Lwt.async (fun () -> close_socket c)
  end

module Io = struct
  type socket = connection
  type addr = connection

  let close = close_socket

  let read c buffer ~off ~len =
    Lwt.bind
      (Lwt.catch
         (fun () -> Lwt_bytes.read c.fd buffer off len)
         (function
           | Unix.Unix_error ((Unix.EBADF | Unix.ECONNRESET | Unix.ENOTCONN), _, _) -> Lwt.return 0
           | e -> Lwt.fail e))
      (function
        | 0 -> Lwt.fail End_of_file
        | n ->
            Option.iter Ache_lwt.Timeout.set c.heard;
            Lwt.return n)

  let writev c iovecs =
    let vectors = Lwt_unix.IO_vectors.create () in
    List.iter (fun { Ache.IOVec.buffer; off; len } -> Lwt_unix.IO_vectors.append_bigarray vectors buffer off len) iovecs;
    let writing =
      Lwt.catch
        (fun () -> Lwt.map (fun n -> `Ok n) (Lwt_unix.writev c.fd vectors))
        (function
          | Unix.Unix_error ((Unix.EBADF | Unix.EPIPE | Unix.ECONNRESET | Unix.ENOTCONN), _, _) -> Lwt.return `Closed
          | e -> Lwt.fail e)
    in
    if not (Lwt.is_sleeping writing) then writing
    else begin
      Ache_lwt.Timeout.set c.write_timer;
      let stalled =
        Lwt.map
          (fun () ->
            force_close c;
            `Closed)
          (Ache_lwt.Timeout.expired c.write_timer)
      in
      Lwt.finalize
        (fun () -> Lwt.pick [ writing; stalled ])
        (fun () ->
          Ache_lwt.Timeout.stop c.write_timer;
          Lwt.return_unit)
    end

  let shutdown_receive c =
    if Lwt_unix.state c.fd = Lwt_unix.Opened then
      try Lwt_unix.shutdown c.fd Unix.SHUTDOWN_RECEIVE with Unix.Unix_error _ -> ()

  (* ache calls it once the last bytes are written, and then reads until the end
     of input (a lingering close). On a live socket that is after the close frames
     of both ends, and the server closes the TCP connection first (RFC 6455
     7.1.1): both directions shut, so the read ends at once. [heard] is set only
     on a live socket. *)
  let shutdown_send c =
    if Lwt_unix.state c.fd = Lwt_unix.Opened then
      let how = if Option.is_some c.heard then Unix.SHUTDOWN_ALL else Unix.SHUTDOWN_SEND in
      try Lwt_unix.shutdown c.fd how with Unix.Unix_error _ -> ()
end

module Ache_io = Ache_lwt.Make (Io)
module Server = Ache_io.Server

type session = Unasked | Known of Session.found

type request = {
  reqd : Reqd.t;
  conn : connection;
  store : Session.t option;
  mutable session : session;
  mutable head_sent : bool;
  log : Yuka.Server.log_level -> string -> unit;
  finish : int -> unit;
}

type reply =
  | Respond of Yuka.Server.response
  | File of { path : string; headers : (string * string) list }
  | Upgrade of (Yuka.Server.Live.connection -> unit Yuka.Async.t)

let ache_request r = Reqd.request r.reqd
let target r = (ache_request r).target
let path r = match String.index_opt (target r) '?' with Some i -> String.sub (target r) 0 i | None -> target r

let header r name =
  match Ache.Headers.get_multi (ache_request r).headers name with
  | [] -> None
  | values -> Some (String.concat (if String.lowercase_ascii name = "cookie" then "; " else ", ") values)

let found r store =
  match r.session with
  | Known f -> f
  | Unasked ->
      let f = Session.find store ~now:(Unix.gettimeofday ()) (header r "cookie") in
      r.session <- Known f;
      if r.head_sent && f.set_cookie <> None then
        r.log `Warn ("Yuka_server: " ^ path r ^ " asked for a new session after its head was sent; no cookie set");
      f

let client_closed = "the client closed the connection"
let plain_headers = [ ("content-type", "text/plain; charset=utf-8"); ("cache-control", "no-store") ]

let flush writer =
  let result, ok, fail = Yuka.Async.make () in
  Writer.flush writer (function `Written -> ok () | `Closed -> fail client_closed);
  result

let expects_continue r =
  List.exists
    (fun value ->
      List.exists (fun v -> String.lowercase_ascii (String.trim v) = "100-continue") (String.split_on_char ',' value))
    (Ache.Headers.get_multi (ache_request r).headers "expect")

let continue r =
  let request = ache_request r in
  if
    expects_continue r
    && Ache.Version.compare request.version Ache.Version.v1_1 >= 0
    && Ache.Request.body_length request <> `Fixed 0L
    && Reqd.response r.reqd = None
  then Reqd.respond_with_informational r.reqd (Ache.Response.create `Continue)

module Backend = struct
  type nonrec request = request
  type nonrec reply = reply

  let meth r : Yuka.Router.meth =
    match (ache_request r).meth with
    | (`GET | `HEAD | `POST | `PUT | `DELETE | `OPTIONS) as m -> m
    | `CONNECT -> `Other "CONNECT"
    | `TRACE -> `Other "TRACE"
    | `Other "PATCH" -> `PATCH
    | `Other m -> `Other m

  let target = target
  let header = header

  let body r ~limit =
    let reader = Reqd.request_body r.reqd in
    let refuse () =
      Ache.Body.Reader.close reader;
      Yuka.Async.return None
    in
    match Ache.Request.body_length (ache_request r) with
    | `Error `Bad_request -> Yuka.Async.failed "the request body has no valid length"
    | `Fixed n when Int64.compare n (Int64.of_int limit) > 0 -> refuse ()
    | `Fixed _ | `Chunked ->
        continue r;
        let result, ok, fail = Yuka.Async.make () in
        let buffer = Buffer.create 1024 in
        let rec next () =
          Ache.Body.Reader.schedule_read reader
            ~on_eof:(fun () -> ok (Some (Buffer.contents buffer)))
            ~on_error:(fun () -> fail "the request body ended before its framing")
            ~on_read:(fun data ~off ~len ->
              if Buffer.length buffer + len > limit then begin
                Ache.Body.Reader.close reader;
                ok None
              end
              else begin
                Buffer.add_string buffer (Ache.Bigstring.substring data ~off ~len);
                next ()
              end)
        in
        next ();
        result

  let session r = Option.map (fun store -> (found r store).id) r.store

  let csrf_token r =
    Option.map (fun store -> Session.token store ~id:(found r store).id ~now:(Unix.gettimeofday ())) r.store

  let verify_csrf r token =
    Yuka.Async.return
      (match r.store with
      | None -> false
      | Some store -> Session.verify store ~id:(found r store).id ~now:(Unix.gettimeofday ()) token)

  let respond response = Yuka.Async.return (Respond response)
  let file _ ~root ~path ~headers = Yuka.Async.return (File { path = Filename.concat root path; headers })

  let exists ~root ~path =
    let file = Filename.concat root path in
    Sys.file_exists file && not (Sys.is_directory file)

  let upgrade _ run = Yuka.Async.return (Upgrade run)

  let sleep seconds =
    let slept, ok, _ = Yuka.Async.make () in
    Lwt.on_success (Lwt_unix.sleep seconds) (fun () ->
        try ok () with e -> default_log `Error ("Yuka_server: after a sleep: " ^ Printexc.to_string e));
    slept
end

module Cycle = Yuka.Server.Adapter.Make (Backend)

let request yuka_request = Option.map (fun r -> r.reqd) (Cycle.backend_request yuka_request)
let framing = [ "content-length"; "transfer-encoding" ]
let without names headers = List.filter (fun (n, _) -> not (List.mem (String.lowercase_ascii n) names)) headers
let has name headers = List.exists (fun (n, _) -> String.lowercase_ascii n = name) headers
let is_head r = (ache_request r).meth = `HEAD
let bodyless status = status = 204 || status = 304

let answer_headers r status headers =
  if bodyless status then without framing headers else if is_head r then headers else without framing headers

let cookie_headers r =
  match r.session with Known { set_cookie = Some c; _ } -> [ ("set-cookie", c) ] | Known _ | Unasked -> []

let start r ~status ~headers respond =
  r.head_sent <- true;
  let headers = headers @ cookie_headers r in
  let refused reason =
    r.log `Error ("Yuka_server: the answer to " ^ path r ^ " cannot be sent (" ^ reason ^ "); answered 500");
    let text = "Internal Server Error" in
    Reqd.respond_with_string r.reqd
      (Ache.Response.create ~headers:(Ache.Headers.of_list plain_headers) `Internal_server_error)
      (if is_head r then "" else text);
    r.finish 500;
    None
  in
  if status < 200 || status > 599 then refused (Printf.sprintf "status %d" status)
  else
    match respond (Ache.Response.create ~headers:(Ache.Headers.of_list headers) (Ache.Status.of_code status)) with
    | v -> Some v
    | exception Invalid_argument m -> refused m

let failure r what = function
  | Failure m when m = client_closed -> r.log `Debug ("Yuka_server: " ^ path r ^ ": " ^ m)
  | e -> r.log `Error ("Yuka_server: " ^ what ^ " of " ^ path r ^ " failed: " ^ Printexc.to_string e)

let respond_string r status headers text =
  let text = if is_head r || bodyless status then "" else text in
  match start r ~status ~headers:(answer_headers r status headers) (fun res -> Reqd.respond_with_string r.reqd res text) with
  | Some () -> r.finish status
  | None -> ()

let pages : Ache.Bigstring.t list ref = ref []
let pages_lock = Mutex.create ()
let kept_page = 1_048_576

let take_page n =
  let page =
    Mutex.protect pages_lock (fun () ->
        match !pages with
        | p :: rest ->
            pages := rest;
            Some p
        | [] -> None)
  in
  match page with Some p when Ache.Bigstring.length p >= n -> p | _ -> Ache.Bigstring.create ((n + 4095) land lnot 4095)

let give_page p =
  if Ache.Bigstring.length p <= kept_page then
    Mutex.protect pages_lock (fun () -> if List.compare_length_with !pages 8 < 0 then pages := p :: !pages)

let respond_fixed r status headers length write =
  let discard () = write (fun _ _ _ -> ()) in
  if is_head r || bodyless status then begin
    discard ();
    respond_string r status headers ""
  end
  else
    let page = take_page length and at = ref 0 in
    let copied =
      match
        write (fun s off len ->
            if len > length - !at then invalid_arg "Yuka_server: a Fixed body is longer than its length";
            Ache.Bigstring.blit_from_string s ~src_off:off page ~dst_off:!at ~len;
            at := !at + len)
      with
      | () when !at = length -> Ok ()
      | () -> Error (Invalid_argument "Yuka_server: a Fixed body is shorter than its length")
      | exception e -> Error e
    in
    match copied with
    | Error e ->
        give_page page;
        raise e
    | Ok () -> (
        let sent = ref false in
        let respond res =
          let res =
            { res with Ache.Response.headers = Ache.Headers.add res.Ache.Response.headers "content-length" (string_of_int length) }
          in
          let writer = Reqd.respond_with_streaming r.reqd res in
          sent := true;
          Writer.schedule_bigstring writer ~off:0 ~len:length page;
          (* On `Closed a write of the page may still be in flight: drop it. *)
          Writer.flush writer (function `Written -> give_page page | `Closed -> ());
          Writer.close writer
        in
        match start r ~status ~headers:(answer_headers r status headers) respond with
        | Some () -> r.finish status
        | None -> if not !sent then give_page page)

let stream_headers r status headers =
  let headers = answer_headers r status headers in
  if
    is_head r && (not (bodyless status))
    && (not (has "content-length" headers || has "transfer-encoding" headers))
    && Ache.Version.compare (ache_request r).version Ache.Version.v1_1 >= 0
    && Ache.Request.persistent_connection (ache_request r)
  then headers @ [ ("transfer-encoding", "chunked") ]
  else headers

let respond_stream r status headers produce =
  match start r ~status ~headers:(stream_headers r status headers) (Reqd.respond_with_streaming r.reqd) with
  | None -> ()
  | Some writer ->
      let write text =
        Writer.write_string writer text;
        flush writer
      in
      let written = try produce write with e -> Yuka.Async.failed (Printexc.to_string e) in
      Yuka.Async.on_result written (function
        | Ok () ->
            Writer.close writer;
            r.finish status
        | Error m ->
            failure r "the stream" (Failure m);
            Reqd.report_exn r.reqd (Failure m);
            r.finish status)

let content_type path = match Magic_mime.lookup path with "text/html" -> "text/html; charset=utf-8" | t -> t
let chunk_size = 65536

let open_file path =
  Lwt.catch
    (fun () ->
      Lwt.bind (Lwt_unix.openfile path [ Unix.O_RDONLY; Unix.O_CLOEXEC ] 0) (fun fd ->
          Lwt.try_bind
            (fun () -> Lwt_unix.fstat fd)
            (fun stat ->
              if stat.Unix.st_kind = Unix.S_REG then Lwt.return_some (fd, stat.Unix.st_size)
              else Lwt.map (fun () -> None) (Lwt_unix.close fd))
            (fun e -> Lwt.bind (Lwt_unix.close fd) (fun () -> Lwt.fail e))))
    (function Unix.Unix_error _ -> Lwt.return_none | e -> Lwt.fail e)

let send_file r ~path ~headers =
  Lwt.bind (open_file path) (function
    | None ->
        respond_string r 404 plain_headers "Not Found";
        Lwt.return_unit
    | Some (fd, size) ->
        let copy writer =
          let buffer = Lwt_bytes.create chunk_size in
          let rec next left =
            if left = 0 then Lwt.return_unit
            else
              Lwt.bind (Lwt_bytes.read fd buffer 0 (min chunk_size left)) (function
                | 0 -> Lwt.fail (Failure (Printf.sprintf "%s ended %d bytes before its size" path left))
                | n ->
                    Writer.write_bigstring writer ~off:0 ~len:n buffer;
                    Lwt.bind (to_lwt (flush writer)) (fun () -> next (left - n)))
          in
          Lwt.catch
            (fun () ->
              Lwt.map
                (fun () ->
                  Writer.close writer;
                  r.finish 200)
                (next size))
            (fun e ->
              failure r "the file answer" e;
              Reqd.report_exn r.reqd e;
              r.finish 200;
              Lwt.return_unit)
        in
        let headers =
          (if has "content-type" headers then [] else [ ("content-type", content_type path) ])
          @ without framing headers
          @ [ ("content-length", string_of_int size) ]
        in
        Lwt.finalize
          (fun () ->
            match start r ~status:200 ~headers (Reqd.respond_with_streaming r.reqd) with
            | None -> Lwt.return_unit
            | Some writer -> copy writer)
          (fun () -> Lwt_unix.close fd))

let linger = 5.

(* The live socket of a request: ache answers 101 and runs [session]. When the
   promise of [session] resolves, ache closes the socket with 1000 unless it
   has ended. *)
let upgrade r run =
  let session ws =
    r.head_sent <- true;
    r.finish 101;
    let lingering = ref false in
    let end_soon () =
      if not !lingering then begin
        lingering := true;
        Lwt.async (fun () ->
            Lwt.pick [ Lwt.protected r.conn.closed; Lwt.map (fun () -> force_close r.conn) (Lwt_unix.sleep linger) ])
      end
    in
    let close code =
      end_soon ();
      match Ache_lwt.Websocket.close ws code with
      | closing -> to_async closing
      | exception Invalid_argument m -> Yuka.Async.failed m
    in
    (* The live protocol is text; a binary message is dropped. *)
    let rec receive () =
      Lwt.bind (Ache_lwt.Websocket.receive ws) (function
        | Some (Ache.Websocket.Text text) -> Lwt.return (Some text)
        | Some (Ache.Websocket.Binary _) -> receive ()
        | None -> Lwt.return None)
    in
    let heard = Ache_lwt.Timeout.create r.conn.live_timeout in
    Ache_lwt.Timeout.set heard;
    r.conn.heard <- Some heard;
    r.conn.going_away <- Some (fun () -> ignore (close 1001));
    Lwt.async (fun () ->
        Lwt.pick
          [
            Lwt.protected r.conn.closed;
            Lwt.map
              (fun () ->
                r.log `Debug ("Yuka_server: the live socket of " ^ address r.conn.peer ^ " was silent; closed");
                force_close r.conn)
              (Ache_lwt.Timeout.expired heard);
          ]
        |> Lwt.map (fun () -> Ache_lwt.Timeout.stop heard));
    let connection =
      Yuka.Server.Live.connection
        ~send:(fun text -> to_async (Ache_lwt.Websocket.send_text ws text))
        ~receive:(fun () -> to_async (receive ()))
        ~close
    in
    let ended, end_ = Lwt.wait () in
    let ran = try run connection with e -> Yuka.Async.failed (Printexc.to_string e) in
    Yuka.Async.on_result ran (fun result ->
        (match result with Ok () -> () | Error m -> r.log `Error ("Yuka_server: the live socket failed: " ^ m));
        end_soon ();
        Lwt.wakeup_later end_ ());
    ended
  in
  match Ache_lwt.Websocket.upgrade r.reqd session with
  | Error `Unsupported_version ->
      respond_string r 426 (("sec-websocket-version", "13") :: plain_headers) "Upgrade Required"
  | Error (`Not_get | `Not_websocket | `Invalid_key) -> respond_string r 400 plain_headers "Bad Request"
  | Ok () -> ()

let send r = function
  | Respond { status; headers; body = Yuka.Server.String text } -> respond_string r status headers text
  | Respond { status; headers; body = Yuka.Server.Stream produce } -> respond_stream r status headers produce
  | Respond { status; headers; body = Yuka.Server.Fixed { length; write } } -> respond_fixed r status headers length write
  | File { path; headers } ->
      Lwt.async (fun () ->
          Lwt.catch
            (fun () -> send_file r ~path ~headers)
            (fun e ->
              failure r "the file answer" e;
              Reqd.report_exn r.reqd e;
              Lwt.return_unit))
  | Upgrade run -> upgrade r run

let method_name r = Ache.Method.to_string (ache_request r).meth

let request_line r status started =
  Printf.sprintf "%s %s %d %.1fms" (method_name r) (path r) status ((Unix.gettimeofday () -. started) *. 1000.)

let handler ?node ?sessions ?(log_requests = true) config app : handler =
  let log level message = try Yuka.Server.Adapter.log config level message with _ -> () in
  fun conn reqd ->
    let started = Unix.gettimeofday () in
    let rec r =
      {
        reqd;
        conn;
        store = sessions;
        session = Unasked;
        head_sent = false;
        log;
        finish = (fun status -> if log_requests then log `Info (request_line r status started));
      }
    in
    let fail e =
      failure r "the answer" e;
      if not r.head_sent then r.finish 500;
      Reqd.report_exn reqd e
    in
    match Cycle.handler ?node config app r with
    | exception e -> fail e
    | answer ->
        Yuka.Async.on_result answer (function
          | Ok reply -> ( try send r reply with e -> fail e)
          | Error m -> fail (Failure m))

let error_text = function
  | `Bad_request _ -> (400, "Bad Request")
  | `Not_implemented -> (501, "Not Implemented")
  | `Http_version_not_supported -> (505, "HTTP Version Not Supported")
  | `Uri_too_long -> (414, "URI Too Long")
  | `Request_header_fields_too_large -> (431, "Request Header Fields Too Large")
  | `Request_timeout -> (408, "Request Timeout")
  | `Bad_gateway -> (502, "Bad Gateway")
  | `Internal_server_error | `Exn _ -> (500, "Internal Server Error")

let error_handler conn ?request error start =
  let status, text = error_text error in
  let body =
    start
      (Ache.Headers.of_list
         [
           ("content-type", "text/plain; charset=utf-8");
           ("content-length", string_of_int (String.length text));
           ("connection", "close");
         ])
  in
  (match request with Some { Ache.Request.meth = `HEAD; _ } -> () | _ -> Writer.write_string body text);
  Writer.close body;
  match error with
  | `Exn e -> default_log `Error ("Yuka_server: " ^ Printexc.to_string e ^ " for " ^ address conn.peer)
  | _ when status >= 500 -> default_log `Error (Printf.sprintf "Yuka_server: %d for %s" status (address conn.peer))
  | _ -> default_log `Warn (Printf.sprintf "Yuka_server: %d %s for %s" status text (address conn.peer))

let config = { Ache.Config.default with read_buffer_size = 0x4000 }

let positive fn name seconds =
  if not (seconds > 0. && seconds < infinity) then
    invalid_arg (Printf.sprintf "Yuka_server.%s: %s %g is not a positive number of seconds" fn name seconds)

let open_connection ~write_timeout ~live_timeout ~opened handler peer fd =
  let closed, close_done = Lwt.wait () in
  let conn =
    {
      fd;
      peer;
      closed;
      close_done;
      write_timer = Ache_lwt.Timeout.create write_timeout;
      live_timeout;
      heard = None;
      request = None;
      going_away = None;
      winding_down = false;
    }
  in
  opened conn;
  (try Lwt_unix.setsockopt fd Unix.TCP_NODELAY true with Unix.Unix_error _ -> ());
  Lwt.catch
    (fun () ->
      (* ache also closes a live socket that sends no frame for [idle_timeout]:
         it must not come before [live_timeout]. *)
      Server.create_connection_handler ~config
        ~idle_timeout:(Some (Float.max 60. live_timeout))
        ~head_timeout:(Some 10.)
        ~request_handler:(fun conn reqd ->
          conn.request <- Some reqd;
          try handler conn reqd with e -> Reqd.report_exn reqd e)
        ~error_handler conn conn)
    (fun e ->
      default_log `Error ("Yuka_server: connection of " ^ address peer ^ ": " ^ Printexc.to_string e);
      Io.close conn)

let connection ?(write_timeout = 30.) ?(live_timeout = 60.) handler peer fd =
  positive "connection" "write_timeout" write_timeout;
  positive "connection" "live_timeout" live_timeout;
  open_connection ~write_timeout ~live_timeout ~opened:ignore handler peer fd

let reading_body c =
  match c.request with Some reqd -> not (Ache.Body.Reader.is_closed (Reqd.request_body reqd)) | None -> false

let wind_down c =
  if not (c.winding_down || reading_body c) then begin
    c.winding_down <- true;
    match c.going_away with Some go -> go () | None -> Io.shutdown_receive c
  end

let rec settle connections deadline =
  if Hashtbl.length connections = 0 || not (Lwt.is_sleeping deadline) then Lwt.return_unit
  else begin
    Hashtbl.iter (fun _ c -> wind_down c) connections;
    Lwt.bind (Lwt.pick [ Lwt_unix.sleep 0.05; Lwt.protected deadline ]) (fun () -> settle connections deadline)
  end

let rec closed_all connections =
  if Hashtbl.length connections = 0 then Lwt.return_unit
  else Lwt.bind (Lwt_unix.sleep 0.01) (fun () -> closed_all connections)

let drain connections drain_timeout =
  Lwt.bind (settle connections (Lwt_unix.sleep drain_timeout)) (fun () ->
      Hashtbl.iter (fun _ c -> force_close c) connections;
      closed_all connections)

let check_serve ~interface ~port ~write_timeout ~live_timeout ~max_connections ~drain_timeout =
  let address =
    match Unix.inet_addr_of_string interface with
    | a -> a
    | exception Failure _ -> invalid_arg (Printf.sprintf "Yuka_server.serve: %S is not an IP address" interface)
  in
  if port < 0 || port > 65535 then invalid_arg (Printf.sprintf "Yuka_server.serve: port %d is not in 0-65535" port);
  positive "serve" "write_timeout" write_timeout;
  positive "serve" "live_timeout" live_timeout;
  positive "serve" "drain_timeout" drain_timeout;
  if max_connections < 1 then invalid_arg (Printf.sprintf "Yuka_server.serve: max_connections %d is not positive" max_connections);
  Unix.ADDR_INET (address, port)

let serve_on ~reuse_port ?(interface = "127.0.0.1") ?(port = 8080) ?(stop = fst (Lwt.wait ())) ?(listening = ignore)
    ?(write_timeout = 30.) ?(live_timeout = 60.) ?(max_connections = 1024) ?(drain_timeout = 10.) handler =
  let address = check_serve ~interface ~port ~write_timeout ~live_timeout ~max_connections ~drain_timeout in
  Sys.set_signal Sys.sigpipe Sys.Signal_ignore;
  let socket = Lwt_unix.socket (Unix.domain_of_sockaddr address) Unix.SOCK_STREAM 0 in
  let connections = Hashtbl.create 64 and freed = Lwt_condition.create () and next_id = ref 0 in
  let opened c =
    let id = !next_id in
    incr next_id;
    Hashtbl.replace connections id c;
    Lwt.on_termination c.closed (fun () ->
        Hashtbl.remove connections id;
        Lwt_condition.signal freed ())
  in
  let stop_settled () = Lwt.catch (fun () -> Lwt.protected stop) (fun _ -> Lwt.return_unit) in
  let stopped () = Lwt.map (fun () -> `Stop) (stop_settled ()) in
  let rec accept failing =
    match Lwt.state stop with
    | Lwt.Return () | Lwt.Fail _ -> Lwt.return_unit
    | Lwt.Sleep when Hashtbl.length connections >= max_connections ->
        Lwt.bind (Lwt.pick [ stopped (); Lwt.map (fun () -> `Freed) (Lwt_condition.wait freed) ]) (fun _ -> accept failing)
    | Lwt.Sleep ->
        Lwt.bind
          (Lwt.pick
             [
               stopped ();
               Lwt.catch
                 (fun () -> Lwt.map (fun c -> `Accepted c) (Lwt_unix.accept ~cloexec:true socket))
                 (function Unix.Unix_error (e, _, _) -> Lwt.return (`Failed e) | e -> Lwt.fail e);
             ])
          (function
            | `Stop -> accept failing
            | `Accepted (fd, client) ->
                Lwt.async (fun () -> open_connection ~write_timeout ~live_timeout ~opened handler client fd);
                accept false
            | `Failed e ->
                if not failing then default_log `Error ("Yuka_server: accept failed, trying again: " ^ Unix.error_message e);
                Lwt.bind (Lwt.pick [ Lwt_unix.sleep 0.1; stop_settled () ]) (fun () -> accept true))
  in
  let listened = ref false in
  Lwt.bind
    (Lwt.catch
       (fun () ->
         Lwt.map Result.ok
           (Lwt.finalize
              (fun () ->
                Lwt_unix.setsockopt socket Unix.SO_REUSEADDR true;
                if reuse_port then Lwt_unix.setsockopt socket Unix.SO_REUSEPORT true;
                Lwt.bind (Lwt_unix.bind socket address) (fun () ->
                    Lwt_unix.listen socket 1024;
                    listened := true;
                    (match Lwt_unix.getsockname socket with Unix.ADDR_INET (_, port) -> listening port | Unix.ADDR_UNIX _ -> ());
                    accept false))
              (fun () -> Lwt_unix.close socket)))
       (fun e -> Lwt.return (Error e)))
    (fun outcome ->
      Lwt.bind (if !listened then drain connections drain_timeout else Lwt.return_unit) (fun () ->
          match (outcome, Lwt.state stop) with
          | Error e, _ | Ok (), Lwt.Fail e -> Lwt.fail e
          | Ok (), (Lwt.Return () | Lwt.Sleep) -> Lwt.return_unit))

let serve = serve_on ~reuse_port:false

(* [second] runs on a second signal. [installed] runs once the handlers are in place (a
   worker unblocks its signals there). [parent] is a pipe that the parent never writes to:
   its end (the parent died) starts the drain as a signal does. *)
let until_signal ?(second = fun () -> exit 1) ?(installed = ignore) ?parent ~signals serving =
  let stop, stopping = Lwt.wait () in
  let start message =
    if Lwt.is_sleeping stop then begin
      default_log `Info message;
      Lwt.wakeup_later stopping ()
    end
  in
  let quit _ =
    if Lwt.is_sleeping stop then start "Yuka_server: stopping after the answers in progress; a second signal stops at once"
    else second ()
  in
  let handlers = List.map (fun signal -> Lwt_unix.on_signal signal quit) signals in
  installed ();
  let watch fd =
    Unix.set_nonblock fd;
    let fd = Lwt_unix.of_unix_file_descr ~blocking:false fd in
    Lwt.bind
      (Lwt.catch (fun () -> Lwt.map ignore (Lwt_unix.read fd (Bytes.create 1) 0 1)) (fun _ -> Lwt.return_unit))
      (fun () ->
        start "Yuka_server: the parent process ended; stopping after the answers in progress";
        Lwt.return_unit)
  in
  Fun.protect
    ~finally:(fun () -> List.iter Lwt_unix.disable_signal_handler handlers)
    (fun () ->
      Lwt_main.run
        (Option.iter (fun fd -> Lwt.async (fun () -> watch fd)) parent;
         serving stop))

let status_text = function
  | Unix.WEXITED n -> Printf.sprintf "exited with code %d" n
  | Unix.WSIGNALED n -> Printf.sprintf "was killed by signal %d" n
  | Unix.WSTOPPED n -> Printf.sprintf "was stopped by signal %d" n

(* A worker is a child of [Lwt_unix.fork] that serves until SIGTERM (SIGINT is ignored:
   the parent forwards it as SIGTERM, so a Ctrl-C to the process group counts once), then
   leaves with [Unix._exit]: the at_exit functions of the parent never run twice. The
   parent forks with SIGINT and SIGTERM blocked; the worker unblocks them once its own
   handlers are in place, so a signal sent meanwhile is delivered then, not lost. *)
let fork_worker ~closing work =
  flush_all ();
  match Lwt_unix.fork () with
  | 0 ->
      List.iter (fun fd -> try Unix.close fd with Unix.Unix_error _ -> ()) closing;
      Sys.set_signal Sys.sigint Sys.Signal_ignore;
      let code =
        match work () with
        | () -> 0
        | exception e ->
            default_log `Error (Printf.sprintf "Yuka_server: worker %d failed: %s" (Unix.getpid ()) (Printexc.to_string e));
            1
      in
      flush_all ();
      Unix._exit code
  | pid -> pid

let restart_after = 1.
let restart_limit = 10
let restart_window = 60.

let supervise ~workers ~address ~listening work =
  let holder = Unix.socket ~cloexec:true (Unix.domain_of_sockaddr address) Unix.SOCK_STREAM 0 in
  let parent = Unix.getpid () and live = Hashtbl.create workers and stopping = ref false and failed = ref None and port = ref 0 in
  (* Only this process holds the write end: a worker reads the end of the file when this
     process ends, even by SIGKILL, and drains. *)
  let alive_in, alive_out = Unix.pipe ~cloexec:true () in
  let deaths = Queue.create () in
  let spawn ~closing ready =
    let blocked = Unix.sigprocmask Unix.SIG_BLOCK [ Sys.sigint; Sys.sigterm ] in
    let unblock () = ignore (Unix.sigprocmask Unix.SIG_SETMASK blocked) in
    (* A signal that came before the block set [stopping]: no worker then, it would miss it. *)
    Fun.protect ~finally:unblock (fun () ->
        if not !stopping then begin
          let pid = fork_worker ~closing:(alive_out :: holder :: closing) (work !port ready alive_in unblock) in
          Hashtbl.replace live pid (Unix.gettimeofday ())
        end)
  in
  let forward () = Hashtbl.iter (fun pid _ -> try Unix.kill pid Sys.sigterm with Unix.Unix_error _ -> ()) live in
  let quit _ =
    if Unix.getpid () = parent then
      if !stopping then begin
        forward ();
        exit 1
      end
      else begin
        stopping := true;
        default_log `Info "Yuka_server: stopping the workers after the answers in progress; a second signal stops at once";
        forward ()
      end
  in
  let previous = List.map (fun signal -> (signal, Sys.signal signal (Sys.Signal_handle quit))) [ Sys.sigint; Sys.sigterm ] in
  let stop_all reason =
    if not !stopping then begin
      stopping := true;
      failed := Some reason;
      forward ()
    end
  in
  let rec reap () =
    if Hashtbl.length live > 0 then begin
      let ended =
        Hashtbl.fold
          (fun pid started ended ->
            match Unix.waitpid [ Unix.WNOHANG ] pid with
            | 0, _ -> ended
            | _, status -> (pid, started, status) :: ended
            | exception Unix.Unix_error (Unix.EINTR, _, _) -> ended
            | exception Unix.Unix_error (Unix.ECHILD, _, _) -> (pid, started, Unix.WEXITED 0) :: ended)
          live []
      in
      List.iter
        (fun (pid, started, status) ->
          Hashtbl.remove live pid;
          if !stopping then begin
            if status <> Unix.WEXITED 0 then default_log `Warn (Printf.sprintf "Yuka_server: worker %d %s" pid (status_text status))
          end
          else if Unix.gettimeofday () -. started < restart_after then begin
            let reason = Printf.sprintf "Yuka_server.run: worker %d %s at its start" pid (status_text status) in
            default_log `Error (reason ^ "; stopping the other workers");
            stop_all reason
          end
          else begin
            let now = Unix.gettimeofday () in
            Queue.push now deaths;
            while now -. Queue.peek deaths > restart_window do
              ignore (Queue.pop deaths)
            done;
            if Queue.length deaths > restart_limit then begin
              let reason =
                Printf.sprintf "Yuka_server.run: workers ended %d times within %.0f seconds; the last, worker %d, %s"
                  (Queue.length deaths) restart_window pid (status_text status)
              in
              default_log `Error (reason ^ "; stopping the other workers");
              stop_all reason
            end
            else begin
              default_log `Error (Printf.sprintf "Yuka_server: worker %d %s; starting another" pid (status_text status));
              spawn ~closing:[] None
            end
          end)
        ended;
      (try Unix.sleepf 0.05 with Unix.Unix_error (Unix.EINTR, _, _) -> ());
      reap ()
    end
  in
  Fun.protect
    ~finally:(fun () ->
      List.iter (fun (signal, behavior) -> Sys.set_signal signal behavior) previous;
      Unix.close alive_out;
      Unix.close alive_in;
      Unix.close holder)
    (fun () ->
      (* The holder keeps the port (chosen by the system for port 0) for the life of [run];
         it never listens, so the kernel spreads connections over the listening workers only. *)
      Unix.setsockopt holder Unix.SO_REUSEADDR true;
      Unix.setsockopt holder Unix.SO_REUSEPORT true;
      Unix.bind holder address;
      (match Unix.getsockname holder with Unix.ADDR_INET (_, p) -> port := p | Unix.ADDR_UNIX _ -> ());
      let ready_in, ready_out = Unix.pipe ~cloexec:true () in
      (* A signal during this loop stops it: the handler runs when [spawn] unblocks, after
         the new worker is in [live], so every forked worker gets SIGTERM. *)
      let rec start n =
        if n < workers && not !stopping then begin
          spawn ~closing:[ ready_in ] (Some ready_out);
          start (n + 1)
        end
        else n
      in
      let started = start 0 in
      Unix.close ready_out;
      let buffer = Bytes.create workers in
      let rec count n =
        if n >= started then n
        else
          match Unix.read ready_in buffer 0 workers with
          | 0 -> n
          | k -> count (n + k)
          | exception Unix.Unix_error (Unix.EINTR, _, _) -> count n
      in
      let ready = count 0 in
      Unix.close ready_in;
      if ready < started then stop_all "Yuka_server.run: a worker stopped before it listened"
      else if not !stopping then listening !port;
      reap ();
      Option.iter failwith !failed)

let run ?interface ?port ?listening ?(workers = 1) ?sessions ?node ?log_requests ?write_timeout ?live_timeout ?max_connections
    ?drain_timeout config app =
  if workers < 1 then invalid_arg (Printf.sprintf "Yuka_server.run: workers %d is not positive" workers);
  let handler = handler ?node ?sessions ?log_requests config app in
  if workers = 1 then
    until_signal ~signals:[ Sys.sigint; Sys.sigterm ] (fun stop ->
        serve ?interface ?port ~stop ?listening ?write_timeout ?live_timeout ?max_connections ?drain_timeout handler)
  else begin
    let address =
      check_serve ~interface:(Option.value interface ~default:"127.0.0.1") ~port:(Option.value port ~default:8080)
        ~write_timeout:(Option.value write_timeout ~default:30.) ~live_timeout:(Option.value live_timeout ~default:60.)
        ~max_connections:(Option.value max_connections ~default:1024) ~drain_timeout:(Option.value drain_timeout ~default:10.)
    in
    Sys.set_signal Sys.sigpipe Sys.Signal_ignore;
    let work port ready parent unblock () =
      let listening _ =
        Option.iter
          (fun fd ->
            (try ignore (Unix.write_substring fd "r" 0 1) with Unix.Unix_error _ -> ());
            try Unix.close fd with Unix.Unix_error _ -> ())
          ready
      in
      until_signal
        ~second:(fun () ->
          flush_all ();
          Unix._exit 1)
        ~installed:unblock ~parent ~signals:[ Sys.sigterm ]
        (fun stop ->
          serve_on ~reuse_port:true ?interface ~port ~stop ~listening ?write_timeout ?live_timeout ?max_connections
            ?drain_timeout handler)
    in
    supervise ~workers ~address ~listening:(Option.value listening ~default:ignore) work
  end
