type 'o t = {
  base : 'o Status.t State.t;
  changes : ('o -> 'o) Optimistic.t State.t;
  refetch : unit -> unit;
}

type retry = { attempts : int; delay_ms : int -> int }

let default_retry = { attempts = 2; delay_ms = (fun n -> if n = 1 then 500 else 1500) }
let no_retry = { attempts = 0; delay_ms = (fun _ -> 0) }

let server_send :
    (string -> Json.t -> ((Json.t, Status.error) result -> unit) -> unit -> unit) ref =
  ref (fun _ _ k ->
      k (Error (Status.Network "no action transport"));
      ignore)

let of_response status body : (Json.t, Status.error) result =
  let fields = match Json.of_string body with Ok (`Assoc f) -> Some f | _ -> None in
  let message () =
    match Option.bind fields (List.assoc_opt "error") with Some (`String m) -> m | _ -> "HTTP " ^ string_of_int status
  in
  match (status, Option.bind fields (List.assoc_opt "ok")) with
  | 200, Some v -> Ok v
  | 400, _ -> Error (Status.Rejected (message ()))
  | 403, _ -> Error Status.Forbidden
  | 404, _ -> Error Status.Not_found
  | (413 | 415), _ -> Error (Status.Protocol (message ()))
  | s, _ when s >= 500 -> Error Status.Server
  | _ -> Error (Status.Protocol ("unexpected response (HTTP " ^ string_of_int status ^ ")"))

let fetch name input k =
  Web.fetch_post
    ("/_yuka/action/" ^ Web.encode_uri name)
    (Json.to_string input)
    (fun status body -> k (of_response status body))
    (fun cancelled message -> if not cancelled then k (Error (Status.Network message)))

let send () = if Web.in_browser then fetch else !server_send

let table : (int * (unit -> unit)) list Web.table option ref = ref None
let next_use = ref 0

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
      match q.output.decode j with
      | Ok data -> Status.Ready { data; stale = false }
      | Error m -> Status.Failed { error = Status.Protocol m; last })
  | Error error -> Status.Failed { error; last }

let on_server ~enabled (q : (_, _, _) Action.t) args base =
  if not (enabled ()) then State.set base Status.Idle
  else
    let input = q.input.encode (args ()) in
    let settled, resolve, _ = Async.make () in
    let (_abort : unit -> unit) = !server_send q.name input resolve in
    match Async.status settled with
    | Async.Done r ->
        State.set base (decode q None r);
        Answers.record (Answers.key q.name input) (Some r) settled
    | _ -> Answers.record (Answers.key q.name input) None settled

let use ?(retry = default_retry) ?(enabled = fun () -> true) (q : ('i, 'o, [ `Query ]) Action.t)
    (args : unit -> 'i) : 'o t =
  let base = State.make (Status.Loading None) in
  let changes = State.make Optimistic.empty in
  if !Base.server_rendering then begin
    on_server ~enabled q args base;
    { base; changes; refetch = ignore }
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
    let rec attempt g input n = stop := send q.name input (answered g input n)
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
        let key = Answers.key q.name input in
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
    let refetch () = match !current with Some (_, input) -> start input ~read:false | None -> () in
    Base.Effect.run (fun () ->
        if enabled () then begin
          let input = q.input.encode (args ()) in
          let key = Answers.key q.name input in
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
    Web.table_set (uses ()) q.name ((id, refetch) :: listed q.name);
    Base.own (fun () ->
        cancel ();
        Web.table_set (uses ()) q.name (List.filter (fun (i, _) -> i <> id) (listed q.name)));
    { base; changes; refetch }
  end

let status r =
  let changes = State.get r.changes in
  let base = State.get r.base in
  if Optimistic.is_empty changes then base
  else Status.map (Optimistic.apply (fun d f -> f d) changes) base

let refetch r = r.refetch ()
let invalidate (q : (_, _, [ `Query ]) Action.t) = List.iter (fun (_, f) -> f ()) (listed q.name)

let mutate r change ?commit run =
  let added, id = Optimistic.add (State.peek r.changes) change in
  State.set r.changes added;
  let drop () = State.set r.changes (Optimistic.remove (State.peek r.changes) id) in
  let result = match run () with a -> a | exception e -> drop (); raise e in
  Async.on_settled result (function
    | Async.Done v ->
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
    | Async.Failed _ -> drop ()
    | Async.Pending -> ());
  result
