type cell = Scheduler.cell = {
  mutable dispose : unit -> unit;
  mutable prev : cell option;
  mutable next : cell option;
  mutable live : bool;
}

type owner = Scheduler.owner = {
  mutable last : cell option;
  mutable gen : int;
  mutable catch : (exn -> unit) option;
  parent : owner option;
}

let current_owner : owner option ref = ref None

let new_owner () =
  { last = None; gen = 0;
    catch = (match !current_owner with Some o -> o.catch | None -> None);
    parent = !current_owner }

let fail = Scheduler.catch

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

let run_effect queue ?cleanup body =
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
    Scheduler.make (Some queue) (fun () ->
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
  node.owner <- Some child;
  if queue == Scheduler.late && !Scheduler.depth > 0 then begin
    node.state <- 2;
    Scheduler.late := node :: !Scheduler.late;
    own stop
  end
  else
  let first = ref None in
  let later =
    match Scheduler.batch (fun () -> try Scheduler.run node with e -> first := Some e) with
    | () -> None
    | exception e -> Some e
  in
  match !first with
  | Some e -> (
      match child.catch with
      | Some _ ->
          fail child e;
          own stop
      | None ->
          stop ();
          raise e)
  | None -> (
      own stop;
      match later with Some e -> raise e | None -> ())

module Effect = struct
  let before ?cleanup body = run_effect Scheduler.queue ?cleanup body
  let after ?cleanup body = run_effect Scheduler.late ?cleanup body

  let on_change ?equal state f =
    let prev = ref (Signal.peek state) in
    after (fun () ->
        let next = Signal.get state in
        if Signal.differs equal !prev next then begin
          let p = !prev in
          prev := next;
          Scheduler.untrack (fun () -> f ~prev:p ~next)
        end)
end
