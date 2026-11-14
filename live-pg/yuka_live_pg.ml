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

let bus ?(retry = 1.) ~conninfo ~channel () =
  let listeners = ref [] and restarts = ref [] and started = ref None in
  let sender = ref None and sending = Lwt_mutex.create () in
  let closed = ref false and stopped, stop = Lwt.wait () in
  let send note =
    to_async
      (Lwt_mutex.with_lock sending (fun () ->
           if !closed then Lwt.fail_with "the bus is closed"
           else
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
    if !closed then Lwt.return_none
    else
    match connect conninfo with
    | c -> (
        let* r = Lwt.catch (fun () -> Lwt.map Result.ok (query c ("LISTEN " ^ quote_ident channel))) (fun e -> Lwt.return (Error e)) in
        match r with
        | Ok () -> Lwt.return_some c
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
          let* woke =
            Lwt.pick
              [ Lwt.map (fun () -> `Read) (Lwt_unix.wait_read (descr c)); Lwt.map (fun () -> `Stop) stopped ]
          in
          match woke with
          | `Stop -> Lwt.return false
          | `Read ->
              c#consume_input;
              deliver c;
              Lwt.return (c#status <> Postgresql.Bad))
        (fun _ -> Lwt.return false)
    in
    if !closed then begin
      close c;
      Lwt.return_unit
    end
    else if alive then watch c
    else begin
      close c;
      let* () = Lwt_unix.sleep retry in
      let* c = open_listener () in
      match c with
      | None -> Lwt.return_unit
      | Some c ->
          List.iter (fun f -> try f () with _ -> ()) (List.rev !restarts);
          watch c
    end
  in
  let listen l =
    listeners := l :: !listeners;
    match !started with
    | Some ready -> ready
    | None ->
        let ready, ok, fail = Async.make () in
        started := Some ready;
        let first () =
          let c = connect conninfo in
          let* () = Lwt.catch (fun () -> query c ("LISTEN " ^ quote_ident channel)) (fun e -> close c; Lwt.fail e) in
          Lwt.async (fun () -> watch c);
          Lwt.return_unit
        in
        Lwt.on_any
          (Lwt.catch first (function
            | Postgresql.Error e -> Lwt.fail_with (Postgresql.string_of_error e)
            | e -> Lwt.fail e))
          ok
          (fun e ->
            started := None;
            listeners := [];
            fail (Printexc.to_string e));
        ready
  in
  let close_bus () =
    to_async
      (if !closed then Lwt.return_unit
       else begin
         closed := true;
         Lwt.wakeup_later stop ();
         Lwt_mutex.with_lock sending (fun () ->
             Option.iter close !sender;
             sender := None;
             Lwt.return_unit)
       end)
  in
  Yuka.Server.Live.bus ~send ~listen ~on_restart:(fun f -> restarts := f :: !restarts) ~close:close_bus
