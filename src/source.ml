type t = { run : (unit -> unit) -> unit; settle : (unit -> unit) -> unit; leave : unit -> unit }
type boundary = { join : unit -> t; busy : bool State.read }
type Scheduler.binding += Boundary of boundary

let rec find = function
  | Scheduler.Bound (Boundary b, _) -> Some b
  | Scheduler.Bound (_, e) | Scheduler.Island e -> find e
  | Scheduler.Empty | Scheduler.Root _ -> None

let join () =
  match !(Base.current_owner ()) with
  | Some o -> ( match find o.env with Some b -> Some (b.join ()) | None -> None)
  | None -> None

let run s loading = match s with Some s -> s.run loading | None -> loading ()
let settle s write = match s with Some s -> s.settle write | None -> write ()
let leave s = match s with Some s -> s.leave () | None -> ()

let log : (string -> unit) ref = ref (fun m -> prerr_endline ("yuka: Async.memo failed: " ^ m))
