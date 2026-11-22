type navigation = { url : string; from : string; kind : [ `Push | `Replace | `Traverse | `Reload ] }

let navigating : bool Signal.t = Signal.make false
let navigation : navigation option Signal.t = Signal.make None

let set value =
  Scheduler.batch (fun () ->
      Signal.set navigating (Option.is_some value);
      Signal.set navigation value)
