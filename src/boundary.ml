type t = {
  mutable count : int;
  mutable waiting : (unit -> unit) list;
  mutable idle : (unit -> unit) list;
  mutable live : bool;
  mutable building : bool;
  mutable revealed : bool;
  mutable runs : int;
  busy : bool State.t;
}

let flush b =
  if b.live && b.count = 0 && not b.building then begin
    let jobs = List.rev b.waiting and idle = List.rev b.idle in
    b.waiting <- [];
    b.idle <- [];
    Scheduler.batch (fun () ->
        List.iter (fun job -> job ()) jobs;
        State.set b.busy false);
    List.iter (fun k -> k ()) idle
  end

let join b () =
  let running = ref false in
  let stop () =
    if !running then begin
      running := false;
      b.count <- b.count - 1
    end
  in
  {
    Source.run =
      (fun _ ->
        if not !running then begin
          running := true;
          b.runs <- b.runs + 1;
          b.count <- b.count + 1;
          State.set b.busy true
        end);
    settle =
      (fun write ->
        stop ();
        b.waiting <- write :: b.waiting;
        flush b);
    leave =
      (fun () ->
        stop ();
        flush b);
  }

let create building =
  { count = 0; waiting = []; idle = []; live = true; building; revealed = false; runs = 0; busy = State.make false }

let bind b env = Scheduler.Bound (Source.Boundary { join = join b; busy = State.read_only b.busy }, env)

let make f =
  let b = create false in
  let o = Base.new_owner () in
  o.env <- bind b o.env;
  Base.own (fun () ->
      b.live <- false;
      b.waiting <- [];
      Base.dispose_owner o;
      State.set b.busy false);
  (Base.with_owner o f, State.read_only b.busy)

let start () =
  let b = create true in
  if not !(Base.server_rendering ()) then
    Base.own (fun () ->
        b.live <- false;
        b.waiting <- [];
        b.idle <- [];
        State.set b.busy false);
  {
    Types.bind = bind b;
    built =
      (fun () ->
        b.building <- false;
        flush b);
    idle = (fun () -> b.count = 0);
    on_idle =
      (fun k ->
        b.idle <- k :: b.idle;
        flush b);
    on_switch =
      (fun job ->
        b.waiting <- job :: b.waiting;
        flush b);
    reveal = (fun () -> b.revealed <- true);
    mark =
      (fun () ->
        let runs = b.runs in
        fun () -> b.revealed && b.count > 0 && b.runs <> runs);
  }

let unbound = !Async.waiter

let wait a write =
  match (Async.status a, Source.join ()) with
  | Async.Pending, (Some _ as s) ->
      Source.run s ignore;
      Async.on_settled a (fun st ->
          Source.settle s (fun () -> match st with Async.Done v -> write v | Async.Pending | Async.Failed _ -> ()));
      if not !(Base.server_rendering ()) then Base.own (fun () -> Source.leave s)
  | _, None -> unbound.wait a write
  | (Async.Done _ | Async.Failed _), Some _ -> ()

let build children env =
  let p = start () in
  let env = p.bind env in
  let o = Base.new_owner () in
  o.env <- env;
  let tree = Base.with_owner o children in
  p.built ();
  (p, env, tree)

let pending ~fallback ~children () =
  Client.use_catch ();
  Async.waiter := { wait };
  let fallback = Kind.to_node fallback and children = Kind.fn children in
  let build =
    if !(Base.server_rendering ()) then begin
      let r = build children (match !(Base.current_owner ()) with Some o -> o.env | None -> Scheduler.Empty) in
      fun _ -> r
    end
    else build children
  in
  let client pos =
    Pending_dom.mount pos fallback children start;
    Types.Fragment []
  in
  Kind.of_node (Types.Provide { add = (fun e -> e); children; client; pending = Some { fallback; build } })

let busy () =
  match Option.bind !(Base.current_owner ()) (fun (o : Base.owner) -> Source.find o.env) with
  | Some b -> b.busy
  | None ->
      if Dev.on then Web.console_error "yuka: Pending.busy () found no Pending above it, so it stays false";
      State.read_only (State.make false)
