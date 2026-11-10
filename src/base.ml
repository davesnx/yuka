type cell = {
  mutable dispose : unit -> unit;
  mutable prev : cell option;
  mutable next : cell option;
  mutable live : bool;
}

type owner = { mutable last : cell option; mutable gen : int }

let current_owner : owner option ref = ref None
let new_owner () = { last = None; gen = 0 }

let add_disposer o dispose =
  let c = { dispose; prev = o.last; next = None; live = true } in
  (match o.last with Some l -> l.next <- Some c | None -> ());
  o.last <- Some c;
  c

let remove_disposer o c =
  if c.live then begin
    c.live <- false;
    c.dispose <- ignore;
    (match c.prev with Some p -> p.next <- c.next | None -> ());
    match c.next with Some n -> n.prev <- c.prev | None -> o.last <- c.prev
  end

let own dispose =
  match !current_owner with
  | Some o -> ignore (add_disposer o dispose)
  | None -> ()

let with_owner o f =
  let prev = !current_owner in
  current_owner := Some o;
  match f () with
  | result ->
      current_owner := prev;
      result
  | exception e ->
      current_owner := prev;
      raise e

let dispose_owner o =
  o.gen <- o.gen + 1;
  let rec go = function
    | None -> ()
    | Some c ->
        let prev = c.prev in
        if c.live then begin
          let dispose = c.dispose in
          remove_disposer o c;
          dispose ()
        end;
        go prev
  in
  go o.last

let owner_size o =
  let rec count n = function None -> n | Some c -> count (n + 1) c.prev in
  count 0 o.last

let mount f =
  let o = new_owner () in
  match with_owner o f with
  | result -> (result, fun () -> dispose_owner o)
  | exception e ->
      dispose_owner o;
      raise e

let server_rendering = ref false

module Effect = struct
  let run ?cleanup body =
    if !server_rendering then () else
    let child = new_owner () in
    let last = ref None in
    let teardown () =
      dispose_owner child;
      match !last with
      | None -> ()
      | Some finish ->
          last := None;
          finish ()
    in
    let node =
      Scheduler.make true (fun () ->
          teardown ();
          let result = with_owner child body in
          (match cleanup with
          | Some cleanup -> last := Some (fun () -> cleanup result)
          | None -> ());
          false)
    in
    let stop () =
      Scheduler.dispose node;
      teardown ()
    in
    (match Scheduler.start node with
    | () -> ()
    | exception e ->
        stop ();
        raise e);
    own stop

  let on_change ?equal state f =
    let prev = ref (Signal.peek state) in
    run (fun () ->
        let next = Signal.get state in
        if Signal.differs equal !prev next then begin
          let p = !prev in
          prev := next;
          Scheduler.untrack (fun () -> f ~prev:p ~next)
        end)
end
