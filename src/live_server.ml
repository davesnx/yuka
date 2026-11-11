type peer = { session : string; header : string -> string option }

type connection = {
  send : string -> unit Async.t;
  receive : unit -> string option Async.t;
  close : int -> unit Async.t;
}

type check = Accept of string | Bad_key of string | Forbid

type served = { check : peer -> Json.t -> check; load : Json.t -> Json.t Async.t }

type job = State_of of int | Text of string

type bus = {
  send : string -> unit Async.t;
  listen : (string -> unit) -> unit Async.t;
  on_restart : (unit -> unit) -> unit;
}

type conn = {
  node : instance;
  c : connection;
  peer : peer;
  mutable front : job list;
  mutable back : job list;
  mutable texts : int;
  waiting : string Web.table;
  mutable busy : bool;
  mutable ended : bool;
  mutable stop : int -> unit;
  mutable subs : (int * sub) list;
}

and sub = {
  conn : conn;
  id : int;
  entry : entry;
  mutable has_state : bool;
  mutable sync : int option;
  mutable held : int option;
  mutable after : (string * int) list;
  mutable target : int option;
}

and entry = {
  home : instance;
  topic : string;
  wire : string;
  mutable state : (Json.t * string) option;
  mutable seq : int;
  mutable members : sub list;
  mutable loading : bool;
  mutable again : bool;
  mutable uncovered : int list;
}

and instance = {
  table : entry Web.table;
  mutable conns : conn list;
  mutable counter : int;
  mutable name : string;
  mutable bus : bus option;
  mutable notes : int;
  seen : int Web.table;
  mutable events : int;
  mutable holding : sub list;
  mutable chain : unit Async.t;
}

type limits = { mutable per_session : int; mutable total : int }

let max_message = 65_536
let max_subs = 64
let max_out = 1_048_576
let max_queued = 256
let limits = { per_session = 16; total = 10_000 }
let max_note = 7_900
let topics : (string * served) list ref = ref []

let instance () =
  {
    table = Web.table ();
    conns = [];
    counter = 0;
    name = "";
    bus = None;
    notes = 0;
    seen = Web.table ();
    events = 0;
    holding = [];
    chain = Async.return ();
  }

let default : instance option ref = ref None

let main () =
  match !default with
  | Some i -> i
  | None ->
      let i = instance () in
      default := Some i;
      i

let set_limits ?per_session ?total () =
  Option.iter (fun n -> limits.per_session <- n) per_session;
  Option.iter (fun n -> limits.total <- n) total

let entry_key topic wire = topic ^ " " ^ wire

let next_seq node =
  node.counter <- node.counter + 1;
  node.counter

let failure topic m =
  match Types.rejection m with
  | Some shown -> Status.Rejected shown
  | None ->
      !Types.log_error ("live topic " ^ topic ^ " failed: " ^ m);
      Status.Server

let code_of = function Status.Rejected m -> ("rejected", m) | _ -> ("server", "")

let take conn =
  (match conn.front with
  | [] ->
      conn.front <- List.rev conn.back;
      conn.back <- []
  | _ -> ());
  match conn.front with
  | [] -> None
  | job :: rest ->
      conn.front <- rest;
      Some job

let rec pump conn =
  if (not conn.busy) && not conn.ended then
    match take conn with
    | None -> ()
    | Some job -> (
        let text =
          match job with
          | Text t ->
              conn.texts <- conn.texts - 1;
              Some t
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
            Async.on_settled (Async.guard conn.c.send text) (function
              | Async.Pending -> ()
              | Async.Done () ->
                  conn.busy <- false;
                  pump conn
              | Async.Failed _ -> conn.stop 1011))

let send_text conn text =
  if conn.texts >= max_queued then conn.stop 1008
  else begin
    conn.texts <- conn.texts + 1;
    conn.back <- Text text :: conn.back;
    pump conn
  end

let message fields = Json.to_string (`Assoc fields)
let synced conn id r = send_text conn (message [ ("t", `String "synced"); ("id", `Int id); ("ref", `Int r) ])

let send_state (sub : sub) seq text =
  let slot = string_of_int sub.id in
  if not (Web.table_has sub.conn.waiting slot) then sub.conn.back <- State_of sub.id :: sub.conn.back;
  Web.table_set sub.conn.waiting slot
    ("{\"t\":\"state\",\"id\":" ^ slot ^ ",\"seq\":" ^ string_of_int seq ^ ",\"state\":" ^ text ^ "}");
  sub.has_state <- true;
  match sub.sync with
  | Some r ->
      sub.sync <- None;
      synced sub.conn sub.id r
  | None -> pump sub.conn

let leave (sub : sub) =
  let e = sub.entry in
  e.members <- List.filter (fun s -> s != sub) e.members;
  Web.table_delete sub.conn.waiting (string_of_int sub.id);
  sub.conn.subs <- List.filter (fun (_, s) -> s != sub) sub.conn.subs;
  sub.after <- [];
  sub.target <- None;
  sub.held <- None;
  sub.conn.node.holding <- List.filter (fun s -> s != sub) sub.conn.node.holding;
  if e.members = [] then
    let t = e.home.table in
    match Web.table_get t (entry_key e.topic e.wire) with
    | Some current when current == e -> Web.table_delete t (entry_key e.topic e.wire)
    | _ -> ()

let error_message id code text =
  message [ ("t", `String "error"); ("id", `Int id); ("code", `String code); ("message", `String text) ]

let current e =
  match Web.table_get e.home.table (entry_key e.topic e.wire) with Some x -> x == e | None -> false

let store e json =
  let text = Json.to_string json in
  e.state <- Some (json, text);
  e.seq <- next_seq e.home;
  List.iter (fun s -> send_state s e.seq text) (List.rev e.members)

let seen node name = Option.value (Web.table_get node.seen name) ~default:0

let release (sub : sub) =
  match sub.held with
  | None -> ()
  | Some r ->
      sub.held <- None;
      sub.after <- [];
      sub.target <- None;
      sub.conn.node.holding <- List.filter (fun s -> s != sub) sub.conn.node.holding;
      if sub.has_state then synced sub.conn sub.id r
      else sub.sync <- Some (match sub.sync with Some s -> max s r | None -> r)

let check (sub : sub) =
  let node = sub.conn.node in
  if sub.target = None && List.for_all (fun (n, p) -> n = node.name || seen node n >= p) sub.after then
    sub.target <- Some node.events;
  match sub.target with
  | Some t when not (List.exists (fun ev -> ev <= t) sub.entry.uncovered) -> release sub
  | _ -> ()

let check_all node = List.iter check node.holding

let rec start_load e (served : served) key =
  let node = e.home in
  e.loading <- true;
  e.again <- false;
  let started = node.events and before = e.seq and first = e.state = None in
  Async.on_settled (Async.guard served.load key) (function
    | Async.Pending -> ()
    | Async.Done json ->
        e.loading <- false;
        if current e && e.seq = before then store e json;
        finish_load e served key started
    | Async.Failed m ->
        e.loading <- false;
        if current e && first && e.state = None then begin
          let code, text = code_of (failure e.topic m) in
          List.iter
            (fun (s : sub) ->
              leave s;
              send_text s.conn (error_message s.id code text))
            (List.rev e.members)
        end
        else if not first then ignore (failure e.topic m);
        finish_load e served key started)

and finish_load e served key started =
  e.uncovered <- List.filter (fun ev -> ev > started) e.uncovered;
  if e.again && current e && e.members <> [] then start_load e served key;
  check_all e.home

let reload e =
  if e.loading then e.again <- true
  else
    match (List.assoc_opt e.topic !topics, Json.of_string e.wire) with
    | Some served, Ok key -> start_load e served key
    | _ -> ()

let subscribe conn id topic key =
  let fail code text = send_text conn (error_message id code text) in
  if List.length conn.subs >= max_subs then fail "limit" "at most 64 subscriptions"
  else
    match List.assoc_opt topic !topics with
    | None -> fail "unknown_topic" topic
    | Some served -> (
        match served.check conn.peer key with
        | exception ex ->
            let code, text = code_of (failure topic (Web.exn_to_string ex)) in
            fail code text
        | Bad_key m -> fail "bad_key" m
        | Forbid -> fail "forbidden" ""
        | Accept wire ->
            let t = conn.node.table in
            let e =
              match Web.table_get t (entry_key topic wire) with
              | Some e -> e
              | None ->
                  let e =
                    { home = conn.node; topic; wire; state = None; seq = 0; members = []; loading = false;
                      again = false; uncovered = [] }
                  in
                  Web.table_set t (entry_key topic wire) e;
                  e
            in
            let sub =
              { conn; id; entry = e; has_state = false; sync = None; held = None; after = []; target = None }
            in
            e.members <- sub :: e.members;
            conn.subs <- (id, sub) :: conn.subs;
            match e.state with
            | Some (_, text) -> send_state sub e.seq text
            | None -> if not e.loading then start_load e served key)

type incoming =
  | Hello of { v : int; csrf : string }
  | Sub of { id : int; topic : string; key : Json.t }
  | Unsub of int
  | Sync of { id : int; r : int; after : (string * int) list }
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
      | Some "sync", Some id ->
          let after =
            match List.assoc_opt "after" f with
            | Some (`List marks) ->
                List.filter_map (function `List [ `String n; `Int p ] -> Some (n, p) | _ -> None) marks
            | _ -> []
          in
          Option.map (fun r -> Sync { id; r; after }) (int "ref")
      | Some "ping", _ -> Some Ping
      | _ -> None)
  | _ -> None

let hold ~sleep (sub : sub) r after =
  let node = sub.conn.node in
  sub.held <- Some (match sub.held with Some h -> max h r | None -> r);
  sub.after <-
    List.fold_left
      (fun acc (n, p) ->
        match List.assoc_opt n acc with
        | Some q when q >= p -> acc
        | _ -> (n, p) :: List.remove_assoc n acc)
      sub.after after;
  sub.target <- None;
  if not (List.memq sub node.holding) then node.holding <- sub :: node.holding;
  check sub;
  if sub.held <> None then Async.on_settled (sleep 5.) (fun _ -> release sub)

let run ?instance:node ~sleep peer ~verify_csrf ~token (c : connection) =
  let node = match node with Some n -> n | None -> main () in
  let conn =
    {
      node;
      c;
      peer;
      front = [];
      back = [];
      texts = 0;
      waiting = Web.table ();
      busy = false;
      ended = false;
      stop = ignore;
      subs = [];
    }
  in
  let finished, resolve, _ = Async.make () in
  let heard = ref 0 and ready = ref false in
  let finish ~close code =
    if not conn.ended then begin
      conn.ended <- true;
      node.conns <- List.filter (fun x -> x != conn) node.conns;
      List.iter (fun (_, s) -> leave s) conn.subs;
      conn.subs <- [];
      conn.front <- [];
      conn.back <- [];
      Web.table_clear conn.waiting;
      if close then Async.on_settled (Async.guard c.close code) (function Async.Pending -> () | _ -> resolve ())
      else resolve ()
    end
  in
  conn.stop <- (fun code -> finish ~close:true code);
  let rec watch seconds =
    let mark = !heard in
    Async.on_settled (sleep seconds) (fun _ ->
        if not conn.ended then if !heard = mark then conn.stop 4408 else watch 60.)
  in
  let rec next () =
    if not conn.ended then
      Async.on_settled (Async.guard c.receive ()) (function
        | Async.Pending -> ()
        | Async.Done (Some text) ->
            incr heard;
            handle text
        | Async.Done None -> finish ~close:false 1000
        | Async.Failed _ -> conn.stop 1011)
  and handle text =
    if String.length text > max_message then conn.stop 1009
    else
      match (parse text, !ready) with
      | None, _ -> conn.stop 4400
      | Some (Hello { v; csrf }), false ->
          if v <> 1 then conn.stop 4426
          else
            Async.on_settled (Async.guard verify_csrf csrf) (function
              | Async.Pending -> ()
              | Async.Done true when not conn.ended ->
                  ready := true;
                  send_text conn
                    (message [ ("t", `String "hello"); ("v", `Int 1); ("csrf", `String (token ())) ]);
                  next ()
              | _ -> conn.stop 4403)
      | Some _, false | Some (Hello _), true -> conn.stop 4400
      | Some (Sub { id; topic; key }), true ->
          if List.mem_assoc id conn.subs then conn.stop 4400
          else begin
            subscribe conn id topic key;
            next ()
          end
      | Some (Unsub id), true ->
          Option.iter leave (List.assoc_opt id conn.subs);
          next ()
      | Some (Sync { id; r; after }), true ->
          (match List.assoc_opt id conn.subs with
          | Some sub when after <> [] || sub.held <> None -> hold ~sleep sub r after
          | Some sub when not sub.has_state ->
              sub.sync <- Some (match sub.sync with Some s -> max s r | None -> r)
          | _ -> synced conn id r);
          next ()
      | Some Ping, true ->
          send_text conn (message [ ("t", `String "pong"); ("csrf", `String (token ())) ]);
          next ()
  in
  let same = List.filter (fun x -> x.peer.session = peer.session) node.conns in
  if List.length node.conns >= limits.total || List.length same >= limits.per_session then conn.stop 1013
  else begin
    node.conns <- conn :: node.conns;
    watch 10.;
    next ()
  end;
  finished

let revoke ?instance:node matches =
  let node = match node with Some n -> n | None -> main () in
  List.iter (fun conn -> if matches conn.peer then conn.stop 4401) node.conns

let ssr_state name key =
  match Web.table_get (main ()).table (entry_key name (Json.to_string key)) with
  | Some { state = Some (json, _); _ } -> Async.return (Ok json)
  | _ -> (
      match List.assoc_opt name !topics with
      | None -> Async.return (Error Status.Not_found)
      | Some served ->
          let result, resolve, _ = Async.make () in
          Async.on_settled (Async.guard served.load key) (function
            | Async.Pending -> ()
            | Async.Done j -> resolve (Ok j)
            | Async.Failed m -> resolve (Error (failure name m)));
          result)

let serve ?(allow = fun _ _ -> true) (topic : ('k, 's) Topic.t) load =
  if List.mem_assoc topic.name !topics then
    invalid_arg ("Yuka.Server.Live.serve: already served: " ^ topic.name);
  let check peer j =
    match topic.key.decode j with
    | Error m -> Bad_key m
    | Ok k -> if allow peer k then Accept (Topic.wire_key topic k) else Forbid
  in
  let load j =
    match topic.key.decode j with
    | Error m -> Async.failed m
    | Ok k -> Async.map topic.state.encode (Server.guarded load k)
  in
  topics := (topic.name, { check; load }) :: !topics;
  Live.server_state := ssr_state

let note node topic wire =
  match node.bus with
  | None -> ()
  | Some bus ->
      let text =
        message [ ("n", `String node.name); ("t", `String topic); ("k", `String wire); ("p", `Int (node.notes + 1)) ]
      in
      if String.length text > max_note then
        !Types.log_error
          ("live topic " ^ topic ^ ": the key is too long for the bus (" ^ string_of_int (String.length text)
         ^ " bytes); other nodes do not see this change")
      else begin
        node.notes <- node.notes + 1;
        node.chain <-
          Async.bind node.chain (fun () ->
              let sent, resolve, _ = Async.make () in
              Async.on_settled (Async.guard bus.send text) (function
                | Async.Failed m ->
                    !Types.log_error ("live bus: a note was not sent: " ^ m);
                    resolve ()
                | _ -> resolve ());
              sent)
      end

let publish ?instance:node (topic : ('k, 's) Topic.t) key state =
  let node = match node with Some n -> n | None -> main () in
  let wire = Topic.wire_key topic key in
  (match Web.table_get node.table (entry_key topic.name wire) with
  | None -> ()
  | Some e ->
      if e.loading then e.again <- true;
      store e (topic.state.encode state));
  note node topic.name wire

let changed ?instance:node (topic : ('k, 's) Topic.t) key =
  let node = match node with Some n -> n | None -> main () in
  let wire = Topic.wire_key topic key in
  (match Web.table_get node.table (entry_key topic.name wire) with
  | Some e when e.members <> [] -> reload e
  | _ -> ());
  note node topic.name wire

let heard node text =
  match Json.of_string text with
  | Ok (`Assoc f) -> (
      match (List.assoc_opt "n" f, List.assoc_opt "t" f, List.assoc_opt "k" f, List.assoc_opt "p" f) with
      | Some (`String n), Some (`String topic), Some (`String wire), Some (`Int p) when n <> node.name ->
          node.events <- node.events + 1;
          if p > seen node n then Web.table_set node.seen n p;
          (match Web.table_get node.table (entry_key topic wire) with
          | Some e when e.members <> [] ->
              e.uncovered <- e.uncovered @ [ node.events ];
              reload e
          | _ -> ());
          check_all node
      | _ -> ())
  | _ -> ()

let restarted node =
  node.events <- node.events + 1;
  List.iter
    (fun e ->
      if e.members <> [] then begin
        e.uncovered <- e.uncovered @ [ node.events ];
        reload e
      end)
    (Array.to_list (Web.table_values node.table))

let use_bus ?instance:node ~node:name bus =
  let node = match node with Some n -> n | None -> main () in
  if Option.is_some node.bus then invalid_arg "Yuka.Server.Live.use_bus: this node already has a bus";
  if name = "" then invalid_arg "Yuka.Server.Live.use_bus: the node name is empty";
  node.name <- name;
  node.bus <- Some bus;
  bus.on_restart (fun () -> restarted node);
  if node == main () then
    Server.live_mark := (fun () -> Some (`List [ `String node.name; `Int node.notes ]));
  bus.listen (heard node)

let mark ?instance:node () =
  let node = match node with Some n -> n | None -> main () in
  match node.bus with Some _ -> Some (node.name, node.notes) | None -> None

type memory = { mutable listeners : (string -> unit) list; mutable restarts : (unit -> unit) list; mutable down : bool }

let memory () = { listeners = []; restarts = []; down = false }

let memory_bus m =
  {
    send =
      (fun text ->
        if not m.down then List.iter (fun l -> l text) m.listeners;
        Async.return ());
    listen =
      (fun l ->
        m.listeners <- m.listeners @ [ l ];
        Async.return ());
    on_restart = (fun f -> m.restarts <- m.restarts @ [ f ]);
  }

let memory_down m down =
  let was = m.down in
  m.down <- down;
  if was && not down then List.iter (fun f -> f ()) m.restarts

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
  let live ?instance request =
    if not (Server.trusted_origin (S.header request)) then S.refuse ~status:403 "Forbidden"
    else if Option.map String.lowercase_ascii (S.header request "upgrade") <> Some "websocket" then
      S.refuse ~status:426 "Upgrade Required"
    else
      let peer = { session = S.session request; header = S.header request } in
      S.upgrade request
        (run ?instance ~sleep:S.sleep peer ~verify_csrf:(S.verify_csrf request) ~token:(fun () ->
             S.csrf_token request))
end
