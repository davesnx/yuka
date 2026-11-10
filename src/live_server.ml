type peer = { session : string; header : string -> string option }

type connection = {
  send : string -> unit Async.t;
  receive : unit -> string option Async.t;
  close : int -> unit Async.t;
}

type check = Accept | Bad_key of string | Forbid

type served = { check : peer -> Json.t -> check; load : Json.t -> Json.t Async.t }

type job = State_of of int | Text of string

type conn = {
  c : connection;
  peer : peer;
  mutable front : job list;
  mutable back : job list;
  waiting : string Web.table;
  mutable busy : bool;
  mutable closed : bool;
  mutable subs : (int * sub) list;
}

and sub = { conn : conn; id : int; entry : entry; mutable has_state : bool; mutable syncs : int list }

and entry = {
  topic : string;
  wire : string;
  mutable state : (Json.t * string) option;
  mutable seq : int;
  mutable members : sub list;
  mutable loading : bool;
}

let max_message = 65_536
let max_subs = 64
let max_out = 1_048_576
let topics : (string * served) list ref = ref []
let table : entry Web.table option ref = ref None
let counter = ref 0

let entries () =
  match !table with
  | Some t -> t
  | None ->
      let t = Web.table () in
      table := Some t;
      t

let entry_key topic wire = topic ^ " " ^ wire

let next_seq () =
  incr counter;
  !counter

let push conn job = conn.back <- job :: conn.back

let take conn =
  (match conn.front with [] -> conn.front <- List.rev conn.back; conn.back <- [] | _ -> ());
  match conn.front with
  | [] -> None
  | job :: rest ->
      conn.front <- rest;
      Some job

let clear conn =
  conn.front <- [];
  conn.back <- []

let rec pump conn =
  if (not conn.busy) && not conn.closed then
    match take conn with
    | None -> ()
    | Some job -> (
        let text =
          match job with
          | Text t -> Some t
          | State_of id ->
              let t = Web.table_get conn.waiting (string_of_int id) in
              Web.table_delete conn.waiting (string_of_int id);
              t
        in
        match text with
        | None -> pump conn
        | Some text ->
            if String.length text > max_out then
              !Types.log_error
                ("warning: live message of " ^ string_of_int (String.length text) ^ " bytes, over 1 MiB");
            conn.busy <- true;
            let sent = match conn.c.send text with a -> a | exception e -> Async.failed (Web.exn_to_string e) in
            Async.on_settled sent (function
              | Async.Pending -> ()
              | Async.Done () ->
                  conn.busy <- false;
                  pump conn
              | Async.Failed _ ->
                  conn.busy <- false;
                  clear conn))

let send_text conn text =
  push conn (Text text);
  pump conn

let message fields = Json.to_string (`Assoc fields)

let synced (sub : sub) r =
  send_text sub.conn (message [ ("t", `String "synced"); ("id", `Int sub.id); ("ref", `Int r) ])

let send_state (sub : sub) seq text =
  let msg =
    "{\"t\":\"state\",\"id\":" ^ string_of_int sub.id ^ ",\"seq\":" ^ string_of_int seq ^ ",\"state\":" ^ text
    ^ "}"
  in
  let slot = string_of_int sub.id in
  if not (Web.table_has sub.conn.waiting slot) then push sub.conn (State_of sub.id);
  Web.table_set sub.conn.waiting slot msg;
  sub.has_state <- true;
  let syncs = List.rev sub.syncs in
  sub.syncs <- [];
  List.iter (synced sub) syncs;
  pump sub.conn

let leave (sub : sub) =
  let e = sub.entry in
  e.members <- List.filter (fun s -> s != sub) e.members;
  Web.table_delete sub.conn.waiting (string_of_int sub.id);
  sub.conn.subs <- List.filter (fun (_, s) -> s != sub) sub.conn.subs;
  if e.members = [] then
    let t = entries () in
    match Web.table_get t (entry_key e.topic e.wire) with
    | Some current when current == e -> Web.table_delete t (entry_key e.topic e.wire)
    | _ -> ()

let error_message id code text =
  message [ ("t", `String "error"); ("id", `Int id); ("code", `String code); ("message", `String text) ]

let fail_sub (sub : sub) code text =
  leave sub;
  send_text sub.conn (error_message sub.id code text)

let failure_code topic m =
  match Types.rejection m with
  | Some shown -> ("rejected", shown)
  | None ->
      !Types.log_error ("live topic " ^ topic ^ " failed: " ^ m);
      ("server", "")

let current e = match Web.table_get (entries ()) (entry_key e.topic e.wire) with Some x -> x == e | None -> false

let store e json =
  let text = Json.to_string json in
  e.state <- Some (json, text);
  e.seq <- next_seq ();
  List.iter (fun s -> send_state s e.seq text) (List.rev e.members)

let start_load e (served : served) key =
  e.loading <- true;
  let loaded = match served.load key with a -> a | exception ex -> Async.failed (Web.exn_to_string ex) in
  Async.on_settled loaded (function
    | Async.Pending -> ()
    | Async.Done json ->
        e.loading <- false;
        if current e && e.state = None then store e json
    | Async.Failed m ->
        e.loading <- false;
        if current e && e.state = None then begin
          let code, text = failure_code e.topic m in
          List.iter (fun s -> fail_sub s code text) (List.rev e.members)
        end)

let subscribe conn id topic key =
  let fail code text = send_text conn (error_message id code text) in
  if List.length conn.subs >= max_subs then fail "limit" "at most 64 subscriptions"
  else
    match List.assoc_opt topic !topics with
    | None -> fail "unknown_topic" topic
    | Some served -> (
        match served.check conn.peer key with
        | exception ex ->
            let code, text = failure_code topic (Web.exn_to_string ex) in
            fail code text
        | Bad_key m -> fail "bad_key" m
        | Forbid -> fail "forbidden" ""
        | Accept ->
            let wire = Json.to_string key in
            let t = entries () in
            let e =
              match Web.table_get t (entry_key topic wire) with
              | Some e -> e
              | None ->
                  let e = { topic; wire; state = None; seq = 0; members = []; loading = false } in
                  Web.table_set t (entry_key topic wire) e;
                  e
            in
            let sub = { conn; id; entry = e; has_state = false; syncs = [] } in
            e.members <- sub :: e.members;
            conn.subs <- (id, sub) :: conn.subs;
            match e.state with
            | Some (_, text) -> send_state sub e.seq text
            | None -> if not e.loading then start_load e served key)

let cleanup conn =
  conn.closed <- true;
  List.iter (fun (_, s) -> leave s) conn.subs;
  conn.subs <- [];
  clear conn;
  Web.table_clear conn.waiting

type incoming =
  | Hello of { v : int; csrf : string }
  | Sub of { id : int; topic : string; key : Json.t }
  | Unsub of int
  | Sync of { id : int; r : int }
  | Ping

let parse text =
  match Json.of_string text with
  | Ok (`Assoc f) -> (
      let int k = match List.assoc_opt k f with Some (`Int i) -> Some i | _ -> None in
      let str k = match List.assoc_opt k f with Some (`String s) -> Some s | _ -> None in
      match (str "t", int "id") with
      | Some "hello", _ -> (
          match (int "v", str "csrf") with Some v, Some csrf -> Some (Hello { v; csrf }) | _ -> None)
      | Some "sub", Some id -> (
          match (str "topic", List.assoc_opt "key" f) with
          | Some topic, Some key -> Some (Sub { id; topic; key })
          | _ -> None)
      | Some "unsub", Some id -> Some (Unsub id)
      | Some "sync", Some id -> Option.map (fun r -> Sync { id; r }) (int "ref")
      | Some "ping", _ -> Some Ping
      | _ -> None)
  | _ -> None

let run ~sleep peer ~verify_csrf ~token (c : connection) =
  let conn =
    { c; peer; front = []; back = []; waiting = Web.table (); busy = false; closed = false; subs = [] }
  in
  let finished, resolve, _ = Async.make () in
  let heard = ref 0 in
  let ready = ref false in
  let stop code =
    if not conn.closed then begin
      cleanup conn;
      let closing = match c.close code with a -> a | exception e -> Async.failed (Web.exn_to_string e) in
      Async.on_settled closing (function Async.Pending -> () | _ -> resolve ())
    end
  in
  let rec next () =
    if not conn.closed then
      let received = match c.receive () with a -> a | exception e -> Async.failed (Web.exn_to_string e) in
      Async.on_settled received (function
        | Async.Pending -> ()
        | Async.Done (Some text) when not conn.closed ->
            incr heard;
            let n = !heard in
            Async.on_settled (sleep 60.) (fun _ -> if !heard = n then stop 4408);
            handle text
        | Async.Done _ | Async.Failed _ ->
            if not conn.closed then begin
              cleanup conn;
              resolve ()
            end)
  and handle text =
    if String.length text > max_message then stop 1009
    else
      match (parse text, !ready) with
      | None, _ -> stop 4400
      | Some (Hello { v; csrf }), false ->
          if v <> 1 then stop 4426
          else
            let verified = match verify_csrf csrf with a -> a | exception e -> Async.failed (Web.exn_to_string e) in
            Async.on_settled verified (function
              | Async.Pending -> ()
              | Async.Done true when not conn.closed ->
                  ready := true;
                  send_text conn (message [ ("t", `String "hello"); ("v", `Int 1); ("csrf", `String (token ())) ]);
                  next ()
              | _ -> stop 4403)
      | Some _, false | Some (Hello _), true -> stop 4400
      | Some (Sub { id; topic; key }), true ->
          if List.mem_assoc id conn.subs then stop 4400
          else begin
            subscribe conn id topic key;
            next ()
          end
      | Some (Unsub id), true ->
          Option.iter leave (List.assoc_opt id conn.subs);
          next ()
      | Some (Sync { id; r }), true ->
          (match List.assoc_opt id conn.subs with
          | Some sub when not sub.has_state -> sub.syncs <- r :: sub.syncs
          | _ -> send_text conn (message [ ("t", `String "synced"); ("id", `Int id); ("ref", `Int r) ]));
          next ()
      | Some Ping, true ->
          send_text conn {|{"t":"pong"}|};
          next ()
  in
  next ();
  finished

let encode_load (topic : (_, _) Topic.t) load j =
  match topic.key.decode j with
  | Error m -> Async.failed m
  | Ok k ->
      let state =
        match load k with
        | a -> a
        | exception Server.Rejected m -> Server.rejected m
        | exception e -> Async.failed (Web.exn_to_string e)
      in
      Async.map topic.state.encode state

let ssr_state name key =
  let failed m =
    match Types.rejection m with
    | Some shown -> Status.Rejected shown
    | None ->
        !Types.log_error ("live topic " ^ name ^ " failed: " ^ m);
        Status.Server
  in
  match Web.table_get (entries ()) (entry_key name (Json.to_string key)) with
  | Some { state = Some (json, _); _ } -> Async.return (Ok json)
  | _ -> (
      match List.assoc_opt name !topics with
      | None -> Async.return (Error Status.Not_found)
      | Some served ->
          let loaded = match served.load key with a -> a | exception e -> Async.failed (Web.exn_to_string e) in
          let result, resolve, _ = Async.make () in
          Async.on_settled loaded (function
            | Async.Pending -> ()
            | Async.Done j -> resolve (Ok j)
            | Async.Failed m -> resolve (Error (failed m)));
          result)

let serve ?(allow = fun _ _ -> true) (topic : ('k, 's) Topic.t) load =
  if List.mem_assoc topic.name !topics then
    invalid_arg ("Yuka.Server.Live.serve: already served: " ^ topic.name);
  let check peer j =
    match topic.key.decode j with Error m -> Bad_key m | Ok k -> if allow peer k then Accept else Forbid
  in
  topics := (topic.name, { check; load = encode_load topic load }) :: !topics;
  Live.server_state := ssr_state

let publish (topic : ('k, 's) Topic.t) key state =
  match Web.table_get (entries ()) (entry_key topic.name (Topic.wire_key topic key)) with
  | None -> ()
  | Some e -> store e (topic.state.encode state)

module type SOCKET = sig
  type request
  type response

  val header : request -> string -> string option
  val session : request -> string
  val csrf_token : request -> string
  val verify_csrf : request -> string -> bool Async.t
  val refuse : status:int -> string -> response Async.t
  val upgrade : request -> (connection -> unit Async.t) -> response Async.t
  val sleep : float -> unit Async.t
end

module Handle (S : SOCKET) = struct
  let live request =
    if not (Server.trusted_origin (S.header request)) then S.refuse ~status:403 "Forbidden"
    else if Option.map String.lowercase_ascii (S.header request "upgrade") <> Some "websocket" then
      S.refuse ~status:426 "Upgrade Required"
    else
      let peer = { session = S.session request; header = S.header request } in
      S.upgrade request
        (run ~sleep:S.sleep peer ~verify_csrf:(S.verify_csrf request) ~token:(fun () ->
             S.csrf_token request))
end
