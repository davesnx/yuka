type navigation = { url : string; from : string; kind : [ `Push | `Replace | `Traverse | `Reload ] }

let navigating : bool Signal.t = Signal.make false
let navigation : navigation option Signal.t = Signal.make None

let link : Host.node option ref = ref None

let set ?link:a value =
  (match !link with Some l -> Host.remove_attribute l "data-yuka-pending" | None -> ());
  link := a;
  (match a with Some l -> Host.set_attribute l "data-yuka-pending" "" | None -> ());
  Scheduler.batch (fun () ->
      Signal.set navigating (Option.is_some value);
      Signal.set navigation value)

let stream : [ `Filling | `Done | `Broken ] Signal.t = Signal.make `Done
