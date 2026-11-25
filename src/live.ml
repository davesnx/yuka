type use = {
  topic : string;
  mutable key : Json.t option;
  mutable wire_id : int option;
  mutable last_seq : int;
  mutable json : Json.t option;
  mutable at : (string * int) option;
  mutable ended : bool;
  mutable syncs : (int * Json.t option) list;
  on_state : Json.t -> unit;
  on_error : Status.error -> unit;
  on_stale : unit -> unit;
  on_synced : int -> unit;
  on_resumed : unit -> unit;
}

type 's t = {
  state : 's Status.t State.read;
  changes : ('s -> 's) Optimistic.t State.t;
  use : use option;
}

type manager = {
  mutable socket : Host.socket option;
  mutable live : bool;
  mutable node : string;
  mutable uses : use list;
  mutable ids : (int * use) list;
  mutable next_id : int;
  mutable attempt : int;
  mutable wait : unit -> unit;
  mutable waiting : bool;
  mutable closing : unit -> unit;
  mutable ping : unit -> unit;
  mutable pong : unit -> unit;
  mutable token : string option;
  mutable dead : Status.error option;
  mutable renewed : bool;
}

let delays = [| 250; 500; 1000; 2000; 4000; 5000 |]
let manager : manager option ref = ref None

let get () =
  match !manager with
  | Some m -> m
  | None ->
      let m =
        {
          socket = None;
          live = false;
          node = "";
          uses = [];
          ids = [];
          next_id = 0;
          attempt = 0;
          wait = ignore;
          waiting = false;
          closing = ignore;
          ping = ignore;
          pong = ignore;
          token = None;
          dead = None;
          renewed = false;
        }
      in
      manager := Some m;
      Bridge.reset_live := (fun () -> manager := None);
      m

let send m (fields : (string * Json.t) list) =
  match m.socket with
  | Some s when m.live -> Host.socket_send s (Json.to_string (`Assoc fields))
  | _ -> ()

let last_mark : Json.t option ref = ref None

let send_sync m u (r, after) =
  match u.wire_id with
  | Some id ->
      send m
        ([ ("t", `String "sync"); ("id", `Int id); ("ref", `Int r) ]
        @ match after with Some mark -> [ ("after", `List [ mark ]) ] | None -> [])
  | None -> ()

let send_sub m u =
  match u.key with
  | Some key when not u.ended ->
      m.next_id <- m.next_id + 1;
      let id = m.next_id in
      u.wire_id <- Some id;
      u.last_seq <- 0;
      m.ids <- (id, u) :: m.ids;
      send m
        ([ ("t", `String "sub"); ("id", `Int id); ("topic", `String u.topic); ("key", key) ]
        @ match u.at with Some (node, seq) -> [ ("at", `List [ `String node; `Int seq ]) ] | None -> []);
      List.iter (send_sync m u) (List.rev u.syncs)
  | _ -> ()

let unsub m u =
  (match u.wire_id with
  | Some id ->
      send m [ ("t", `String "unsub"); ("id", `Int id) ];
      m.ids <- List.filter (fun (i, _) -> i <> id) m.ids
  | None -> ());
  u.wire_id <- None

let take m u seq state =
  u.last_seq <- seq;
  u.json <- Some state;
  u.at <- (if m.node = "" then None else Some (m.node, seq));
  u.on_state state

let token m =
  match m.token with
  | Some t -> t
  | None -> (
      match Answers.find "l:csrf" with Answers.Found (Ok (`String t)) -> t | _ -> "")

let rec connect m =
  m.wait ();
  m.wait <- ignore;
  m.waiting <- false;
  let refused =
    if Option.is_none m.token && Option.is_none m.socket then
      match Answers.find "l:csrf" with Answers.Found (Error e) -> Some e | _ -> None
    else None
  in
  match refused with
  | Some error ->
      give_up m error;
      List.iter (fun u -> u.ended <- true) m.uses
  | None ->
  if m.uses != [] && Option.is_none m.dead && Option.is_none m.socket then
    match Host.socket_open (Host.live_url () ^ Host.base () ^ "/_yuka/live") (fun () -> opened m) (fun text -> heard m text) (fun code -> closed m code) with
    | s -> m.socket <- Some s
    | exception _ -> retry m

and opened m =
  m.live <- true;
  m.ids <- [];
  send m [ ("t", `String "hello"); ("v", `Int 1); ("csrf", `String (token m)) ];
  List.iter (send_sub m) (List.rev m.uses);
  beat m

and beat m =
  m.ping ();
  m.ping <-
    Host.set_timeout 25_000 (fun () ->
        send m [ ("t", `String "ping") ];
        m.pong <- Host.set_timeout 10_000 (fun () -> hang_up m 4000);
        beat m)

and heard m text =
  m.pong ();
  m.pong <- ignore;
  match Json.of_string text with
  | Ok (`Assoc f) -> (
      let int k = match List.assoc_opt k f with Some (`Int i) -> Some i | _ -> None in
      let str k = match List.assoc_opt k f with Some (`String s) -> Some s | _ -> None in
      let use () = match int "id" with Some id -> List.assoc_opt id m.ids | None -> None in
      match str "t" with
      | Some ("hello" | "pong") as t ->
          if t = Some "hello" then begin
            m.attempt <- 0;
            m.renewed <- false;
            m.node <- Option.value (str "node") ~default:""
          end;
          Option.iter (fun t -> m.token <- Some t) (str "csrf")
      | Some "state" -> (
          match (use (), int "seq", List.assoc_opt "state" f) with
          | Some u, Some seq, Some state when seq > u.last_seq -> take m u seq state
          | _ -> ())
      | Some "patch" -> (
          match (use (), int "seq", int "from", List.assoc_opt "ops" f) with
          | Some u, Some seq, Some from, Some ops when seq > u.last_seq -> (
              let patched =
                match u.json with Some j when from = u.last_seq -> Json_patch.apply j ops | _ -> None
              in
              match patched with
              | Some state -> take m u seq state
              | None ->
                  u.json <- None;
                  u.at <- None;
                  unsub m u;
                  send_sub m u)
          | _ -> ())
      | Some "resumed" -> (
          match (use (), int "seq") with
          | Some u, Some seq when u.last_seq = 0 && (match u.at with Some (_, at) -> at = seq | None -> false) ->
              u.last_seq <- seq;
              u.on_resumed ()
          | _ -> ())
      | Some "error" -> (
          match use () with
          | Some u ->
              let error =
                match str "code" with
                | Some "forbidden" -> Status.Forbidden
                | Some "unknown_topic" -> Status.Not_found
                | Some "rejected" -> Status.Rejected (Option.value (str "message") ~default:"")
                | Some "bad_key" -> Status.Protocol ("bad key: " ^ Option.value (str "message") ~default:"")
                | _ -> Status.Server
              in
              u.ended <- true;
              u.wire_id <- None;
              u.on_error error
          | None -> ())
      | Some "synced" -> (
          match (use (), int "ref") with Some u, Some r -> u.on_synced r | _ -> ())
      | _ -> ())
  | _ -> ()

and closed m code =
  m.socket <- None;
  m.live <- false;
  m.ping ();
  m.pong ();
  m.ping <- ignore;
  m.pong <- ignore;
  m.ids <- [];
  List.iter (fun u -> u.wire_id <- None) m.uses;
  let fatal =
    match code with
    | 4403 -> Some Status.Forbidden
    | 4426 | 4400 | 1009 -> Some (Status.Protocol ("live socket closed with " ^ string_of_int code))
    | _ -> None
  in
  match fatal with
  | Some Status.Forbidden when not m.renewed ->
      m.renewed <- true;
      List.iter (fun u -> if not u.ended then u.on_stale ()) m.uses;
      Host.fetch_text (Host.base () ^ "/_yuka/csrf")
        (fun status body ->
          match (status, Json.of_string body) with
          | 200, Ok (`Assoc [ ("csrf", `String t) ]) ->
              m.token <- Some t;
              connect m
          | _ -> give_up m Status.Forbidden)
        (fun _ -> give_up m Status.Forbidden)
  | Some error -> give_up m error
  | None ->
      List.iter (fun u -> if not u.ended then u.on_stale ()) m.uses;
      retry m

and give_up m error =
  m.dead <- Some error;
  List.iter (fun u -> if not u.ended then u.on_error error) m.uses

and hang_up m code =
  match m.socket with
  | Some s ->
      Host.socket_close s code;
      closed m code
  | None -> ()

and retry m =
  if m.uses != [] && Option.is_none m.dead then begin
    let d = delays.(min m.attempt (Array.length delays - 1)) in
    m.attempt <- m.attempt + 1;
    let delay = int_of_float (float_of_int d *. (0.5 +. (Host.random () /. 2.))) in
    m.wait ();
    m.waiting <- true;
    m.wait <-
      (if Host.online () then Host.set_timeout delay (fun () -> connect m)
       else
         let timer = Host.set_timeout (Array.get delays (Array.length delays - 1)) (fun () -> connect m) in
         let online = Host.on_online (fun () -> connect m) in
         fun () ->
           timer ();
           online ())
  end

let renew m =
  match Answers.find "l:csrf" with
  | Answers.Found (Ok (`String t)) -> m.token <- Some t
  | _ -> ()

let attach m u =
  m.closing ();
  m.closing <- ignore;
  m.uses <- u :: m.uses;
  renew m;
  m.dead <- None;
  if m.live then send_sub m u else if Option.is_none m.socket && not m.waiting then connect m

let detach m u =
  unsub m u;
  m.uses <- List.filter (fun x -> x != u) m.uses;
  if m.uses == [] then begin
    m.closing ();
    m.closing <-
      Host.set_timeout 2000 (fun () ->
          m.closing <- ignore;
          if m.uses == [] then hang_up m 1000)
  end

let key_name (topic : (_, _) Topic.t) key = "l:" ^ Topic.name topic ^ " " ^ Json.to_string key

let decode (topic : (_, 's) Topic.t) last j =
  match Codec.decode (Topic.state topic) j with
  | Ok data -> Status.Ready { data; stale = false }
  | Error m -> Status.Failed { error = Status.Protocol m; last }

let csrf_answer () =
  match !(Types.current_session ()) with
  | Some { csrf = Some token; _ } ->
      Answers.record_value "l:csrf" (fun () ->
          match token () with Some t -> Ok (`String t) | None -> Error Status.Forbidden)
  | _ -> ()

let on_server (topic : (_, _) Topic.t) key base =
  let loaded =
    match !(Types.current_session ()) with
    | Some { context = Some c; _ } -> c.live (Topic.name topic) key
    | _ -> !Bridge.live_state (Topic.name topic) key
  in
  let settle r =
    State.set base (match r with Ok (j, _) -> decode topic None j | Error error -> Status.Failed { error; last = None })
  in
  Async.on_result loaded (function Ok r -> settle r | Error m -> settle (Error (Status.Network m)));
  if !(Base.server_rendering ()) then begin
    csrf_answer ();
    let name = key_name topic key in
    let embed =
      Result.map (fun (j, at) ->
          `List (j :: (match at with Some (node, seq) -> [ `String node; `Int seq ] | None -> [])))
    in
    let embedded = Async.map embed loaded in
    match Async.status embedded with
    | Async.Done r -> Answers.record name (Some r) embedded
    | _ -> Answers.record name None embedded
  end

let make (topic : ('k, 's) Topic.t) (args : unit -> 'k) : 's t =
  let base, changes, state = Optimistic.make () in
  if !(Base.server_rendering ()) || not Host.in_browser then begin
    on_server topic (Codec.encode (Topic.key topic) (args ())) base;
    { state; changes; use = None }
  end
  else begin
    let data () = Status.data (State.peek base) in
    let rec u =
      {
        topic = Topic.name topic;
        key = None;
        wire_id = None;
        last_seq = 0;
        json = None;
        at = None;
        ended = false;
        syncs = [];
        on_state = (fun j -> State.set base (decode topic (data ()) j));
        on_error =
          (fun error ->
            let dropped = List.map fst u.syncs in
            u.syncs <- [];
            Scheduler.batch (fun () ->
                List.iter (fun id -> State.set changes (Optimistic.remove (State.peek changes) id)) dropped;
                State.set base (Status.Failed { error; last = data () })));
        on_stale =
          (fun () ->
            State.set base
              (match data () with Some data -> Status.Ready { data; stale = true } | None -> Status.Loading None));
        on_synced =
          (fun r ->
            let settled, waiting = List.partition (fun (x, _) -> x <= r) u.syncs in
            u.syncs <- waiting;
            Scheduler.batch (fun () ->
                List.iter (fun (id, _) -> State.set changes (Optimistic.remove (State.peek changes) id)) settled));
        on_resumed =
          (fun () ->
            match State.peek base with
            | Status.Ready { data; stale = true } -> State.set base (Status.Ready { data; stale = false })
            | Status.Ready _ -> ()
            | _ -> Option.iter u.on_state u.json);
      }
    in
    Platform.live_mark := (fun fields -> last_mark := List.assoc_opt "live" fields);
    let m = get () in
    let first = ref true in
    Base.run_effect Scheduler.queue (fun () ->
        let key = Codec.encode (Topic.key topic) (args ()) in
        match u.key with
        | Some k when Json.to_string k = Json.to_string key -> ()
        | _ ->
            Scheduler.untrack (fun () ->
                unsub m u;
                u.key <- Some key;
                u.json <- None;
                u.at <- None;
                u.ended <- false;
                (if !first then
                   match Answers.find (key_name topic key) with
                   | Answers.Found (Ok (`List (j :: at))) ->
                       u.json <- Some j;
                       u.at <- (match at with [ `String node; `Int seq ] -> Some (node, seq) | _ -> None);
                       State.set base (decode topic None j)
                   | Answers.Found (Ok _) -> State.set base (Status.Failed { error = Status.Protocol "live answer"; last = None })
                   | Answers.Found (Error error) -> State.set base (Status.Failed { error; last = None })
                   | Answers.Pending | Answers.Absent -> ()
                 else State.set base (Status.Loading (data ())));
                if !first then begin
                  first := false;
                  attach m u
                end
                else if m.live then send_sub m u
                else if Option.is_none m.socket && not m.waiting then connect m));
    Base.own (fun () -> detach m u);
    { state; changes; use = Some u }
  end

let state t = t.state

let optimistic ?commit t ~change run =
  let added, id = Optimistic.add (State.peek t.changes) change in
  State.set t.changes added;
  let drop () = State.set t.changes (Optimistic.remove (State.peek t.changes) id) in
  let result = match run () with a -> a | exception e -> drop (); raise e in
  Async.on_settled result (function
    | Async.Done (Ok v) -> (
        Option.iter (fun f -> State.set t.changes (Optimistic.replace (State.peek t.changes) id (f v))) commit;
        match t.use with
        | Some u when not u.ended ->
            let after = !last_mark in
            last_mark := None;
            u.syncs <- u.syncs @ [ (id, after) ];
            Option.iter (fun m -> if m.live then send_sync m u (id, after)) !manager
        | _ -> drop ())
    | Async.Done (Error _) | Async.Failed _ -> drop ()
    | Async.Pending -> ());
  result
