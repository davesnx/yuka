type ('a, 'access) signal = 'a Signal.t
type 'a t = ('a, [ `Write ]) signal
type 'a read = ('a, [ `Read ]) signal

let make = Signal.make
let get = Signal.get
let peek = Signal.peek

let set (s : _ t) value =
  Scheduler.check_write s.node;
  Signal.set s value

let update s f = set s (f s.value)
external read_only : 'a t -> 'a read = "%identity"

let reducer ?equal reduce initial =
  let s = make ?equal initial in
  (read_only s, fun action -> update s (fun value -> reduce value action))

let untrack = Scheduler.untrack

let memo ?equal f =
  let s = Signal.computed ?equal f in
  Base.own (fun () -> Signal.dispose_computed s);
  s

let waiting = ref []
let frame = ref false

let run_waiting () =
  frame := false;
  let jobs = List.rev !waiting in
  waiting := [];
  Scheduler.batch (fun () -> List.iter (fun job -> job ()) jobs)

let after_paint job =
  if not !frame then begin
    let task () =
      let (_ : unit -> unit) = Web.set_timeout 0 run_waiting in
      ()
    in
    if !Base.in_frame then task ()
    else begin
      let stop = ref ignore in
      stop :=
        Web.on_frame (fun _ ->
            !stop ();
            task ())
    end;
    frame := true
  end;
  waiting := job :: !waiting

let deferred ?equal (source : (_, _) signal) =
  if not Web.in_browser then memo ?equal (fun () -> get source)
  else begin
    let watch = Scheduler.make (Some Scheduler.queue) Scheduler.never in
    let first =
      match Scheduler.with_listener (Some watch) (fun () -> get source) with
      | v -> v
      | exception e ->
          Scheduler.dispose watch;
          raise e
    in
    let s = Signal.make ?equal first in
    let queued = ref false and live = ref true in
    let job () =
      queued := false;
      if !live then
        match Signal.peek source with
        | value -> Signal.set s value
        | exception _ ->
            (* [watch] reads the same stale source in this batch and raises the
               same exception to its owner. *)
            ()
    in
    Scheduler.set_level watch;
    watch.fn <-
      (fun () ->
        let value = get source in
        if (not !queued) && Signal.differs s.equal s.value value then begin
          after_paint job;
          queued := true
        end;
        false);
    watch.owner <- !(Base.current_owner ());
    Base.own (fun () ->
        live := false;
        Scheduler.dispose watch);
    s
  end

let on_change ?equal (state : (_, _) signal) f =
  let prev = ref (Signal.peek state) and first = ref true in
  Base.Effect.after (fun () ->
      let next = Signal.get state in
      let created = !first && not (Signal.differs None !prev next) in
      first := false;
      if (not created) && Signal.differs equal !prev next then begin
        let p = !prev in
        prev := next;
        Scheduler.untrack (fun () -> f ~prev:p ~next)
      end)

external signal : ('a, _) signal -> 'a Signal.t = "%identity"
external of_signal : 'a Signal.t -> ('a, _) signal = "%identity"
