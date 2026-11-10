type 'a t = 'a Signal.t

let make = Signal.make
let get = Signal.get
let peek = Signal.peek
let set = Signal.set
let update = Signal.update

let memo ?equal f =
  let s = Signal.computed ?equal f in
  Base.own (fun () -> Signal.dispose_computed s);
  s
