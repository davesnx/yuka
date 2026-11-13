let navigating : bool Signal.t = Signal.make false
let set value = Scheduler.batch (fun () -> Signal.set navigating value)
