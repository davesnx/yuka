module Async = Yuka.Async

let ( let* ) = Lwt.bind

let to_async p =
  let a, resolve, fail = Async.make () in
  Lwt.on_any p resolve (fun e -> fail (Printexc.to_string e));
  a

let quote_ident s = "\"" ^ String.concat "\"\"" (String.split_on_char '"' s) ^ "\""

let descr (c : Postgresql.connection) =
  Lwt_unix.of_unix_file_descr ~blocking:false ~set_flags:false c#socket_descr

let rec flush c fd =
  match c#flush with
  | Postgresql.Successful -> Lwt.return_unit
  | Postgresql.Data_left_to_send ->
      let* () = Lwt_unix.wait_write fd in
      flush c fd

let query (c : Postgresql.connection) ?params sql =
  let fd = descr c in
  c#send_query ?params sql;
  let* () = flush c fd in
  let rec results acc =
    c#consume_input;
    if c#is_busy then
      let* () = Lwt_unix.wait_read fd in
      results acc
    else
      match c#get_result with
      | None -> Lwt.return (List.rev acc)
      | Some r -> results (r :: acc)
  in
  let* rs = results [] in
  match
    List.find_opt
      (fun (r : Postgresql.result) ->
        match r#status with Postgresql.Command_ok | Postgresql.Tuples_ok -> false | _ -> true)
      rs
  with
  | Some r -> Lwt.fail_with r#error
  | None -> Lwt.return_unit

let connect conninfo =
  let c = new Postgresql.connection ~conninfo () in
  c#set_nonblocking true;
  c

let close (c : Postgresql.connection) = try c#finish with _ -> ()

let bus ?(retry = 1.) ~conninfo ~channel () : Yuka.Server.Live.bus =
  let listeners = ref [] and restarts = ref [] and started = ref None in
  let sender = ref None and sending = Lwt_mutex.create () in
  let send note =
    to_async
      (Lwt_mutex.with_lock sending (fun () ->
           let c = match !sender with Some c -> c | None -> connect conninfo in
           sender := Some c;
           Lwt.catch
             (fun () -> query c ~params:[| channel; note |] "SELECT pg_notify($1, $2)")
             (fun e ->
               if c#status = Postgresql.Bad then begin
                 sender := None;
                 close c
               end;
               Lwt.fail e)))
  in
  let deliver (c : Postgresql.connection) =
    let rec next () =
      match c#notifies with
      | Some n ->
          if n.Postgresql.Notification.name = channel then
            List.iter (fun l -> try l n.extra with _ -> ()) (List.rev !listeners);
          next ()
      | None -> ()
    in
    next ()
  in
  let rec open_listener () =
    match connect conninfo with
    | c -> (
        let* r = Lwt.catch (fun () -> Lwt.map Result.ok (query c ("LISTEN " ^ quote_ident channel))) (fun e -> Lwt.return (Error e)) in
        match r with
        | Ok () -> Lwt.return c
        | Error _ ->
            close c;
            let* () = Lwt_unix.sleep retry in
            open_listener ())
    | exception Postgresql.Error _ ->
        let* () = Lwt_unix.sleep retry in
        open_listener ()
  in
  let rec watch c =
    let* alive =
      Lwt.catch
        (fun () ->
          let* () = Lwt_unix.wait_read (descr c) in
          c#consume_input;
          deliver c;
          Lwt.return (c#status <> Postgresql.Bad))
        (fun _ -> Lwt.return false)
    in
    if alive then watch c
    else begin
      close c;
      let* () = Lwt_unix.sleep retry in
      let* c = open_listener () in
      List.iter (fun f -> try f () with _ -> ()) (List.rev !restarts);
      watch c
    end
  in
  let listen l =
    listeners := l :: !listeners;
    match !started with
    | Some ready -> ready
    | None ->
        let ready =
          to_async
            (let* c =
               match connect conninfo with
               | c -> (
                   let* () = query c ("LISTEN " ^ quote_ident channel) in
                   Lwt.return c)
               | exception Postgresql.Error e -> Lwt.fail_with (Postgresql.string_of_error e)
             in
             Lwt.async (fun () -> watch c);
             Lwt.return_unit)
        in
        started := Some ready;
        ready
  in
  { send; listen; on_restart = (fun f -> restarts := f :: !restarts) }
