type t = {
  mutable count : int;
  mutable waiting : (unit -> unit) list;
  mutable live : bool;
  busy : bool State.t;
}

let flush b =
  if b.live && b.count = 0 then begin
    let jobs = List.rev b.waiting in
    b.waiting <- [];
    Scheduler.batch (fun () ->
        List.iter (fun job -> job ()) jobs;
        State.set b.busy false)
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

let make f =
  let b = { count = 0; waiting = []; live = true; busy = State.make false } in
  let o = Base.new_owner () in
  o.env <- Scheduler.Bound (Source.Boundary { join = join b; busy = State.read_only b.busy }, o.env);
  Base.own (fun () ->
      b.live <- false;
      b.waiting <- [];
      Base.dispose_owner o;
      State.set b.busy false);
  (Base.with_owner o f, State.read_only b.busy)
