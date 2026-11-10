type use = {
  topic : string;
  mutable key : Json.t option;
  mutable wire_id : int option;
  mutable last_seq : int;
  mutable ended : bool;
  mutable syncs : int list;
  on_state : Json.t -> unit;
  on_error : Status.error -> unit;
  on_stale : unit -> unit;
  on_synced : int -> unit;
}

type 's t = {
  base : 's Status.t State.t;
  changes : ('s -> 's) Optimistic.t State.t;
  use : use option;
}

type manager = {
  mutable socket : Web.socket option;
  mutable live : bool;
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
}

let server_state : (string -> Json.t -> (Json.t, Status.error) result Async.t) ref =
  ref (fun name _ -> Async.return (Error (Status.Network ("no live topic " ^ name))))

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
        }
      in
      manager := Some m;
      m

let send m (fields : (string * Json.t) list) =
  match m.socket with
  | Some s when m.live -> Web.socket_send s (Json.to_string (`Assoc fields))
  | _ -> ()

let send_sync m u r =
  match u.wire_id with
  | Some id -> send m [ ("t", `String "sync"); ("id", `Int id); ("ref", `Int r) ]
  | None -> ()

let send_sub m u =
  match u.key with
  | Some key when not u.ended ->
      m.next_id <- m.next_id + 1;
      let id = m.next_id in
      u.wire_id <- Some id;
      u.last_seq <- 0;
      m.ids <- (id, u) :: m.ids;
      send m [ ("t", `String "sub"); ("id", `Int id); ("topic", `String u.topic); ("key", key) ];
      List.iter (send_sync m u) (List.rev u.syncs)
  | _ -> ()

let token m =
  match m.token with
  | Some t -> t
  | None -> (
      match Answers.find "l:csrf" with Answers.Found (Ok (`String t)) -> t | _ -> "")

let rec connect m =
  m.wait ();
  m.wait <- ignore;
  m.waiting <- false;
  if m.uses != [] && Option.is_none m.dead && Option.is_none m.socket then
    match Web.socket_open (Web.live_url ()) (fun () -> opened m) (fun text -> heard m text) (fun code -> closed m code) with
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
    Web.set_timeout 25_000 (fun () ->
        send m [ ("t", `String "ping") ];
        m.pong <- Web.set_timeout 10_000 (fun () -> hang_up m 4000);
        beat m)

and heard m text =
  m.pong ();
  m.pong <- ignore;
  match Json.of_string text with
  | Ok (`Assoc f) -> (
      let int k = match List.assoc_opt k f with Some (`Int i) -> Some i | _ -> None in
      let str k = match List.assoc_opt k f with Some (`String s) -> Some s | _ -> None in
      let use () = Option.bind (int "id") (fun id -> List.assoc_opt id m.ids) in
      match str "t" with
      | Some "hello" ->
          m.attempt <- 0;
          Option.iter (fun t -> m.token <- Some t) (str "csrf")
      | Some "state" -> (
          match (use (), int "seq", List.assoc_opt "state" f) with
          | Some u, Some seq, Some state when seq > u.last_seq ->
              u.last_seq <- seq;
              u.on_state state
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
  | Some error ->
      m.dead <- Some error;
      List.iter (fun u -> if not u.ended then u.on_error error) m.uses
  | None ->
      List.iter (fun u -> if not u.ended then u.on_stale ()) m.uses;
      retry m

and hang_up m code =
  match m.socket with
  | Some s ->
      Web.socket_close s code;
      closed m code
  | None -> ()

and retry m =
  if m.uses != [] && Option.is_none m.dead then begin
    let d = delays.(min m.attempt (Array.length delays - 1)) in
    m.attempt <- m.attempt + 1;
    let delay = int_of_float (float_of_int d *. (0.5 +. (Web.random () /. 2.))) in
    m.wait ();
    m.waiting <- true;
    m.wait <-
      (if Web.online () then Web.set_timeout delay (fun () -> connect m)
       else
         let timer = Web.set_timeout (Array.get delays (Array.length delays - 1)) (fun () -> connect m) in
         let online = Web.on_online (fun () -> connect m) in
         fun () ->
           timer ();
           online ())
  end

let attach m u =
  m.closing ();
  m.closing <- ignore;
  m.uses <- u :: m.uses;
  match m.dead with
  | Some error -> u.on_error error
  | None -> if m.live then send_sub m u else if Option.is_none m.socket && not m.waiting then connect m

let unsub m u =
  (match u.wire_id with
  | Some id ->
      send m [ ("t", `String "unsub"); ("id", `Int id) ];
      m.ids <- List.filter (fun (i, _) -> i <> id) m.ids
  | None -> ());
  u.wire_id <- None

let detach m u =
  unsub m u;
  m.uses <- List.filter (fun x -> x != u) m.uses;
  if m.uses == [] then begin
    m.closing ();
    m.closing <-
      Web.set_timeout 2000 (fun () ->
          m.closing <- ignore;
          if m.uses == [] then hang_up m 1000)
  end

let key_name (topic : (_, _) Topic.t) key = "l:" ^ topic.name ^ " " ^ Json.to_string key

let decode (topic : (_, 's) Topic.t) last j =
  match topic.state.decode j with
  | Ok data -> Status.Ready { data; stale = false }
  | Error m -> Status.Failed { error = Status.Protocol m; last }

let csrf_answer () =
  match !Types.current_session with
  | Some ({ csrf = Some token; _ } as s) when s.depth > 0 && not (List.mem "l:csrf" s.answered) ->
      let r = Ok (`String (token ())) in
      Answers.record "l:csrf" (Some r) (Async.return r)
  | _ -> ()

let on_server (topic : (_, _) Topic.t) key base =
  let loaded = !server_state topic.name key in
  let settle r = State.set base (match r with Ok j -> decode topic None j | Error error -> Status.Failed { error; last = None }) in
  Async.on_result loaded (function Ok r -> settle r | Error m -> settle (Error (Status.Network m)));
  if !Base.server_rendering then begin
    csrf_answer ();
    let name = key_name topic key in
    match Async.status loaded with
    | Async.Done r -> Answers.record name (Some r) loaded
    | _ -> Answers.record name None loaded
  end

let use (topic : ('k, 's) Topic.t) (args : unit -> 'k) : 's t =
  let base = State.make (Status.Loading None) in
  let changes = State.make Optimistic.empty in
  if !Base.server_rendering || not Web.in_browser then begin
    on_server topic (topic.key.encode (args ())) base;
    { base; changes; use = None }
  end
  else begin
    let data () = Status.data (State.peek base) in
    let rec u =
      {
        topic = topic.name;
        key = None;
        wire_id = None;
        last_seq = 0;
        ended = false;
        syncs = [];
        on_state = (fun j -> State.set base (decode topic (data ()) j));
        on_error =
          (fun error ->
            let dropped = u.syncs in
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
            if List.mem r u.syncs then begin
              u.syncs <- List.filter (fun x -> x <> r) u.syncs;
              State.set changes (Optimistic.remove (State.peek changes) r)
            end);
      }
    in
    let m = get () in
    let first = ref true in
    Base.Effect.run (fun () ->
        let key = topic.key.encode (args ()) in
        match u.key with
        | Some k when Json.to_string k = Json.to_string key -> ()
        | _ ->
            Scheduler.untrack (fun () ->
                unsub m u;
                u.key <- Some key;
                u.ended <- false;
                (if !first then
                   match Answers.find (key_name topic key) with
                   | Answers.Found (Ok j) -> State.set base (decode topic None j)
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
    { base; changes; use = Some u }
  end

let status t =
  let changes = State.get t.changes in
  let base = State.get t.base in
  if Optimistic.is_empty changes then base else Status.map (Optimistic.apply (fun d f -> f d) changes) base

let mutate t change run =
  let added, id = Optimistic.add (State.peek t.changes) change in
  State.set t.changes added;
  let drop () = State.set t.changes (Optimistic.remove (State.peek t.changes) id) in
  let result = match run () with a -> a | exception e -> drop (); raise e in
  Async.on_settled result (function
    | Async.Done _ -> (
        match t.use with
        | Some u when not u.ended ->
            u.syncs <- u.syncs @ [ id ];
            Option.iter (fun m -> if m.live then send_sync m u id) !manager
        | _ -> drop ())
    | Async.Failed _ -> drop ()
    | Async.Pending -> ());
  result
