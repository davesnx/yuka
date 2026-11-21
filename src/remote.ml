type 'o t = {
  state : 'o Status.t State.read;
  base : 'o Status.t State.t;
  changes : ('o -> 'o) Optimistic.t State.t;
  refetch : unit -> unit;
}

type retry = { attempts : int; delay_ms : int -> int }

let retry ~attempts ~delay_ms = { attempts; delay_ms }
let default_retry = { attempts = 2; delay_ms = (fun n -> if n = 1 then 500 else 1500) }
let no_retry = { attempts = 0; delay_ms = (fun _ -> 0) }

let fetch name input k =
  Web.fetch_post
    ("/_yuka/action/" ^ Web.encode_uri name)
    (Json.to_string input)
    (fun status body -> k (Bridge.of_response status (Bridge.fields body)))
    (fun cancelled message -> if not cancelled then k (Error (Status.Network message)))

let send () = if Web.in_browser then fetch else !Bridge.send
let next_use = ref 0

type flight = {
  name : string;
  key : string;
  mutable waiting : (int * ((Json.t, Status.error) result -> unit)) list;
  mutable abort : unit -> unit;
}

let flights_table : flight Web.table option ref = ref None

let flights () =
  match !flights_table with
  | Some t -> t
  | None ->
      let t = Web.table () in
      flights_table := Some t;
      t

let forget t (f : flight) =
  match Web.table_get t f.key with Some g when g == f -> Web.table_delete t f.key | _ -> ()

let join send name input k =
  let t = flights () and key = Answers.key name input in
  incr next_use;
  let id = !next_use in
  let f =
    match Web.table_get t key with
    | Some f ->
        f.waiting <- (id, k) :: f.waiting;
        f
    | None ->
        let f = { name; key; waiting = [ (id, k) ]; abort = ignore } in
        Web.table_set t key f;
        f.abort <-
          send name input (fun r ->
              forget t f;
              let waiting = f.waiting in
              f.waiting <- [];
              List.iter (fun (_, k) -> k r) waiting);
        f
  in
  fun () ->
    f.waiting <- List.filter (fun (i, _) -> i <> id) f.waiting;
    if f.waiting == [] then begin
      forget t f;
      f.abort ()
    end

let forget_name name =
  let t = flights () in
  Array.iter (fun (f : flight) -> if String.equal f.name name then Web.table_delete t f.key) (Web.table_values t)

let table : (int * (unit -> unit)) list Web.table option ref = ref None

let uses () =
  match !table with
  | Some t -> t
  | None ->
      let t = Web.table () in
      table := Some t;
      t

let listed name = Option.value (Web.table_get (uses ()) name) ~default:[]

let decode (q : (_, _, _) Action.t) last = function
  | Ok j -> (
      match Codec.decode (Action.output q) j with
      | Ok data -> Status.Ready { data; stale = false }
      | Error m -> Status.Failed { error = Status.Protocol m; last })
  | Error error -> Status.Failed { error; last }

let on_server ~enabled (q : (_, _, _) Action.t) args base =
  if not (enabled ()) then State.set base Status.Idle
  else
    let input = Codec.encode (Action.input q) (args ()) in
    let settled, resolve, _ = Async.make () in
    let (_abort : unit -> unit) = !Bridge.send (Action.name q) input resolve in
    match Async.status settled with
    | Async.Done r ->
        State.set base (decode q None r);
        Answers.record (Answers.key (Action.name q) input) (Some r) settled
    | _ -> Answers.record (Answers.key (Action.name q) input) None settled

let make ?(retry = default_retry) ?(enabled = fun () -> true) (q : ('i, 'o, [ `Query ]) Action.t)
    (args : unit -> 'i) : 'o t =
  let base, changes, state = Optimistic.make () in
  if !(Base.server_rendering ()) then begin
    on_server ~enabled q args base;
    { state; base; changes; refetch = ignore }
  end
  else begin
    let send = send () in
    let generation = ref 0 and stop = ref ignore and current = ref None and first = ref true in
    let cancel () =
      incr generation;
      !stop ();
      stop := ignore
    in
    let finish g r = if g = !generation then State.set base (decode q (Status.data (State.peek base)) r) in
    let rec attempt g input n = stop := join send (Action.name q) input (answered g input n)
    and answered g input n r =
      if g = !generation then
        match r with
        | Error (Status.Network _ | Status.Server) when n <= retry.attempts ->
            stop := Web.set_timeout (retry.delay_ms n) (fun () -> if g = !generation then attempt g input (n + 1))
        | r -> finish g r
    in
    let embedded g input r =
      finish g r;
      match r with
      | Error (Status.Network _ | Status.Server) when retry.attempts >= 1 ->
          stop :=
            Web.set_timeout (retry.delay_ms 1) (fun () ->
                if g = !generation then begin
                  State.set base (Status.Loading (Status.data (State.peek base)));
                  attempt g input 2
                end)
      | _ -> ()
    in
    let start input ~read =
      cancel ();
      let g = !generation in
      State.set base (Status.Loading (Status.data (State.peek base)));
      if not read then attempt g input 1
      else
        let key = Answers.key (Action.name q) input in
        match Answers.find key with
        | Answers.Found r -> embedded g input r
        | Answers.Absent -> attempt g input 1
        | Answers.Pending ->
            let stop_watch = ref ignore and stop_ready = ref ignore in
            let release () =
              !stop_watch ();
              !stop_ready ()
            in
            stop_watch :=
              Web.watch_added (fun nodes ->
                  match Answers.find_added key nodes with
                  | Some r ->
                      !stop_ready ();
                      embedded g input r;
                      true
                  | None -> false);
            stop_ready :=
              Web.on_dom_ready (fun () ->
                  !stop_watch ();
                  if g = !generation then
                    match Answers.find key with Answers.Found r -> embedded g input r | _ -> attempt g input 1);
            stop := release
    in
    let restart () = match !current with Some (_, input) -> start input ~read:false | None -> () in
    let refetch () =
      match !current with
      | Some (key, input) ->
          Web.table_delete (flights ()) key;
          start input ~read:false
      | None -> ()
    in
    Base.run_effect Scheduler.queue (fun () ->
        if enabled () then begin
          let input = Codec.encode (Action.input q) (args ()) in
          let key = Answers.key (Action.name q) input in
          match !current with
          | Some (k, _) when String.equal k key -> ()
          | _ ->
              current := Some (key, input);
              let read = !first && Web.in_browser in
              first := false;
              start input ~read
        end
        else begin
          current := None;
          first := false;
          cancel ();
          State.set base Status.Idle
        end);
    incr next_use;
    let id = !next_use in
    Web.table_set (uses ()) (Action.name q) ((id, restart) :: listed (Action.name q));
    Base.own (fun () ->
        cancel ();
        Web.table_set (uses ()) (Action.name q) (List.filter (fun (i, _) -> i <> id) (listed (Action.name q))));
    { state; base; changes; refetch }
  end

let state r = r.state

let refetch r = r.refetch ()
let invalidate (q : (_, _, [ `Query ]) Action.t) =
  forget_name (Action.name q);
  List.iter (fun (_, f) -> f ()) (listed (Action.name q))

let optimistic ?commit r ~change run =
  let added, id = Optimistic.add (State.peek r.changes) change in
  State.set r.changes added;
  let drop () = State.set r.changes (Optimistic.remove (State.peek r.changes) id) in
  let result = match run () with a -> a | exception e -> drop (); raise e in
  Async.on_settled result (function
    | Async.Done (Ok v) ->
        Scheduler.batch (fun () ->
            drop ();
            let next data = match commit with Some f -> f v data | None -> change data in
            match State.peek r.base with
            | Status.Ready { data; stale } -> State.set r.base (Status.Ready { data = next data; stale })
            | Status.Loading (Some data) ->
                State.set r.base (Status.Loading (Some (next data)));
                r.refetch ()
            | Status.Failed { error; last = Some data } ->
                State.set r.base (Status.Failed { error; last = Some (next data) })
            | Status.Idle | Status.Loading None | Status.Failed { last = None; _ } -> ())
    | Async.Done (Error _) | Async.Failed _ -> drop ()
    | Async.Pending -> ());
  result
