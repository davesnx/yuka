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

let debug_name name (s : (_, _) signal) =
  if Dev.on then Dev.name s.node ("State `" ^ name ^ "`");
  s

external read_only : 'a t -> 'a read = "%identity"

let reducer ?equal reduce initial =
  let s = make ?equal initial in
  (read_only s, fun action -> update s (fun value -> reduce value action))

let runtime_untrack = Scheduler.untrack
let untrack f = if Dev.on then Scheduler.quiet f else Scheduler.untrack f

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
        | exception _ -> ()
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

let select_with_size (source : (_, _) signal) =
  let watch =
    Scheduler.make (Some (Scheduler.mine Scheduler.selects)) Scheduler.never
  in
  let current =
    match Scheduler.with_listener (Some watch) (fun () -> get source) with
    | value -> ref value
    | exception e ->
        Scheduler.dispose watch;
        raise e
  in
  let keys = Web.keyed Signal.same and limit = ref 16 and live = ref true in
  let write key answer =
    match Web.keyed_get keys key with Some s -> Signal.set s answer | None -> ()
  in
  watch.level <- -1;
  watch.fn <-
    (fun () ->
      let value = get source and prev = !current in
      if not (Signal.same prev value) then begin
        current := value;
        write prev false;
        write value true
      end;
      false);
  watch.owner <- !(Base.current_owner ());
  Base.own (fun () ->
      live := false;
      Scheduler.dispose watch;
      Web.keyed_clear keys);
  let entry key =
    match Web.keyed_get keys key with
    | Some s -> s
    | None ->
        if Web.keyed_size keys >= !limit then begin
          Web.keyed_keep keys (fun (s : bool Signal.t) -> s.node.first != None);
          let size = Web.keyed_size keys in
          limit := if size > 8 then 2 * size else 16
        end;
        let s = Signal.make (Signal.same !current key) in
        Web.keyed_set keys key s;
        s
  in
  let read key =
    if
      !live
      && !(Scheduler.listener ()) != None
      && Signal.same key key
      && (Scheduler.js || (watch.id > !Scheduler.sealed && not !(Base.server_rendering ())))
    then begin
      (try Scheduler.fresh watch with _ -> ());
      Signal.get (entry key)
    end
    else Signal.same (if !live then get source else !current) key
  in
  (read, fun () -> Web.keyed_size keys)

let select source = fst (select_with_size source)

let on_change ?equal (state : (_, _) signal) f =
  let prev = ref (Signal.peek state) and first = ref true in
  Base.Effect.after (fun () ->
      let next = Signal.get state in
      let created = !first && not (Signal.differs None !prev next) in
      first := false;
      if (not created) && Signal.differs equal !prev next then begin
        let p = !prev in
        prev := next;
        Scheduler.untrack (fun () ->
            if Dev.on then Scheduler.body := false;
            f ~prev:p ~next)
      end)

external signal : ('a, _) signal -> 'a Signal.t = "%identity"
external of_signal : 'a Signal.t -> ('a, _) signal = "%identity"
