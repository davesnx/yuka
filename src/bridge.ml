let send : (string -> Json.t -> ((Json.t, Status.error) result -> unit) -> unit -> unit) ref =
  ref (fun _ _ k ->
      k (Error (Status.Network "no action transport"));
      ignore)

let live_state : (string -> Json.t -> (Json.t, Status.error) result Async.t) ref =
  ref (fun name _ -> Async.return (Error (Status.Network ("no live topic " ^ name))))

let reset_live : (unit -> unit) ref = ref ignore
