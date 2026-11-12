type ('a, 'access) signal = 'a Signal.t
type 'a t = ('a, [ `Write ]) signal
type 'a read = ('a, [ `Read ]) signal

let make = Signal.make
let get = Signal.get
let peek = Signal.peek
let set = Signal.set
let update = Signal.update
external read_only : 'a t -> 'a read = "%identity"
let untrack = Scheduler.untrack

let memo ?equal f =
  let s = Signal.computed ?equal f in
  Base.own (fun () -> Signal.dispose_computed s);
  s
