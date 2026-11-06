open Base

  type 'a status = Pending | Done of 'a | Failed of string

  type 'a t = {
    mutable status : 'a status;
    mutable waiters : ('a status -> unit) list;
  }

  let settle t st =
    match t.status with
    | Pending ->
        t.status <- st;
        let waiters = List.rev t.waiters in
        t.waiters <- [];
        List.iter (fun w -> w st) waiters
    | _ -> ()

  let make () =
    let t = { status = Pending; waiters = [] } in
    (t, (fun v -> settle t (Done v)), fun e -> settle t (Failed e))

  let resolved v = { status = Done v; waiters = [] }
  let failed e = { status = Failed e; waiters = [] }
  let status t = t.status

  let on_settled t f =
    match t.status with
    | Pending -> t.waiters <- f :: t.waiters
    | st -> f st

  let on_result t f =
    on_settled t (function
      | Pending -> ()
      | Done v -> f (Ok v)
      | Failed m -> f (Error m))

  let bind t f =
    let r, resolve, fail = make () in
    on_settled t (function
      | Pending -> ()
      | Failed e -> fail e
      | Done v ->
          on_settled (f v) (function
            | Pending -> ()
            | Failed e -> fail e
            | Done x -> resolve x));
    r

  let map f t = bind t (fun v -> resolved (f v))

  let watch t =
    let s = State.make t.status in
    on_settled t (fun st -> State.set s st);
    s
