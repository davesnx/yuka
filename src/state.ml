type ('a, 'access) signal = 'a Signal.t
type 'a t = ('a, [ `Write ]) signal
type 'a read = ('a, [ `Read ]) signal

let make = Signal.make
let get = Signal.get
let peek = Signal.peek

let set (s : _ t) value =
  Web.check_state_write s.node;
  Signal.set s value

let update s f = set s (f s.value)
external read_only : 'a t -> 'a read = "%identity"
let untrack = Scheduler.untrack

let memo ?equal f =
  let s = Signal.computed ?equal f in
  Base.own (fun () -> Signal.dispose_computed s);
  s
