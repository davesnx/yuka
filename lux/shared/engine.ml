type t = unit

let start ~canvas_id:_ = Error "lux: WebGL runs in the browser only"
let frame () _ = ()
let follow () = ()
let restart () = ()
let following () = true
let readout () = ""
let stop () = ()
