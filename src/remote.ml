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
  Host.fetch_post
    (Host.base () ^ "/_yuka/action/" ^ Host.encode_uri name)
    (Json.to_string input)
    (fun status body -> k (Bridge.of_response status (Bridge.fields body)))
    (fun cancelled message -> if not cancelled then k (Error (Status.Network message)))

let send () = if Host.in_browser then fetch else !Bridge.send

type answer = (Json.t, Status.error) result

type flight = { mutable writers : (int * (answer -> unit)) list; mutable abort : unit -> unit }

let flights : flight Host.table = Host.table ()

let again retry n = function Error (Status.Network _ | Status.Server) -> n <= retry.attempts | _ -> false

let join send name key input retry n writer =
  match Host.table_get flights key with
  | Some f -> f.writers <- writer :: f.writers
  | None ->
      let f = { writers = [ writer ]; abort = ignore } in
      Host.table_set flights key f;
      let live () = match f.writers with [] -> false | _ -> true in
      let rec attempt n =
        f.abort <-
          send name input (fun r ->
              if live () then
                if again retry n r then
                  f.abort <- Host.set_timeout (retry.delay_ms n) (fun () -> if live () then attempt (n + 1))
                else begin
                  Host.table_delete flights key;
                  let writers = f.writers in
                  f.writers <- [];
                  List.iter (fun (_, write) -> write r) writers
                end)
      in
      attempt n

let leave key id =
  match Host.table_get flights key with
  | Some f -> (
      f.writers <- List.filter (fun (i, _) -> i <> id) f.writers;
      match f.writers with
      | [] ->
          Host.table_delete flights key;
          f.abort ()
      | _ -> ())
  | None -> ()

type use = { adopt : string -> answer -> unit; share : retry option -> (string -> bool) -> (unit -> unit) option }

let table : use list Host.table option ref = ref None
let next_use = ref 0

let adopt t navigated =
  let answers =
    match navigated with
    | Platform.Region region -> Answers.in_region region
    | Platform.Part html -> Answers.in_html html
  in
  List.iter
    (fun (key, r) ->
      match r with Ok _ -> Array.iter (List.iter (fun u -> u.adopt key r)) (Host.table_values t) | Error _ -> ())
    answers

let uses () =
  match !table with
  | Some t -> t
  | None ->
      let t = Host.table () in
      table := Some t;
      Platform.answered := adopt t;
      t

let listed name = Option.value (Host.table_get (uses ()) name) ~default:[]

let refresh ?retry name wanted =
  List.iter
    (fun wait -> wait ())
    (List.fold_left
       (fun waits u -> match u.share retry wanted with Some w -> w :: waits | None -> waits)
       [] (listed name))

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
    let name = Action.name q in
    incr next_use;
    let id = !next_use in
    let island = !Types.hydrating_island in
    let generation = ref 0 and stop = ref ignore and current = ref None and first = ref true in
    let cancel () =
      incr generation;
      !stop ();
      stop := ignore
    in
    let finish g r = if g = !generation then State.set base (decode q (Status.data (State.peek base)) r) in
    let attempt ?(retry = retry) g input n =
      let key = Answers.key name input in
      stop := (fun () -> leave key id);
      join send name key input retry n (id, finish g)
    in
    let embedded g input r =
      finish g r;
      if again retry 1 r then
        stop :=
          Host.set_timeout (retry.delay_ms 1) (fun () ->
              if g = !generation then begin
                State.set base (Status.Loading (Status.data (State.peek base)));
                attempt g input 2
              end)
    in
    let start input ~read =
      cancel ();
      let g = !generation in
      State.set base (Status.Loading (Status.data (State.peek base)));
      if not read then attempt g input 1
      else
        let key = Answers.key (Action.name q) input in
        match Answers.find ?island key with
        | Answers.Found r -> embedded g input r
        | Answers.Absent -> attempt g input 1
        | Answers.Pending ->
            let stop_watch = ref ignore and stop_ready = ref ignore in
            let release () =
              !stop_watch ();
              !stop_ready ()
            in
            stop_watch :=
              Host.watch_added (fun nodes ->
                  match Answers.find_added key nodes with
                  | Some r ->
                      !stop_ready ();
                      embedded g input r;
                      true
                  | None -> false);
            stop_ready :=
              Host.on_dom_ready (fun () ->
                  !stop_watch ();
                  if g = !generation then
                    match Answers.find ?island key with Answers.Found r -> embedded g input r | _ -> attempt g input 1);
            stop := release
    in
    let refetch () = match !current with Some (key, _) -> refresh ~retry name (String.equal key) | None -> () in
    Base.run_effect Scheduler.queue (fun () ->
        if enabled () then begin
          let input = Codec.encode (Action.input q) (args ()) in
          let key = Answers.key (Action.name q) input in
          match !current with
          | Some (k, _) when String.equal k key -> ()
          | _ ->
              current := Some (key, input);
              let read = !first && Host.in_browser in
              first := false;
              start input ~read
        end
        else begin
          current := None;
          first := false;
          cancel ();
          State.set base Status.Idle
        end);
    let adopt key r =
      match !current with
      | Some (k, input) when String.equal k key ->
          cancel ();
          embedded !generation input r
      | _ -> ()
    in
    let share r wanted =
      match !current with
      | Some (key, input) when wanted key ->
          cancel ();
          let g = !generation in
          State.set base (Status.Loading (Status.data (State.peek base)));
          Some (fun () -> attempt ?retry:r g input 1)
      | _ -> None
    in
    let use = { adopt; share } in
    Host.table_set (uses ()) name (use :: listed name);
    Base.own (fun () ->
        cancel ();
        Host.table_set (uses ()) name (List.filter (fun u -> u != use) (listed name)));
    { state; base; changes; refetch }
  end

let state r = r.state

let refetch (r : _ t) = r.refetch ()

let invalidate (q : (_, _, [ `Query ]) Action.t) = refresh (Action.name q) (fun _ -> true)

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
