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

  let return v = { status = Done v; waiters = [] }
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
      | Done v -> (
          match f v with
          | next ->
              on_settled next (function
                | Pending -> ()
                | Failed e -> fail e
                | Done x -> resolve x)
          | exception e -> fail (Web.exn_to_string e)));
    r

  let map f t = bind t (fun v -> return (f v))

  let watch t =
    let s = State.make t.status in
    on_settled t (fun st -> State.set s st);
    State.read_only s

  let guard f x = match f x with a -> a | exception e -> failed (Web.exn_to_string e)

  let ready_equal equal a b =
    match (a, b) with
    | Status.Ready { data = x; _ }, Status.Ready { data = y; _ } -> equal x y
    | _ -> a == b

  let memo ?equal f =
    let out =
      State.make ?equal:(match equal with Some e -> Some (ready_equal e) | None -> None) (Status.Loading None)
    in
    let source = Source.join () and run = ref 0 and first = ref Web.in_browser and last = ref None in
    let write g st () =
      if g = !run then
        State.set out
          (match st with
          | Done (Ok data) ->
              last := Some data;
              Status.Ready { data; stale = false }
          | Done (Error error) -> Status.Failed { error; last = !last }
          | Failed _ -> Status.Failed { error = Status.Server; last = !last }
          | Pending -> Status.Loading !last)
    in
    let settle g st =
      if g = !run then begin
        (match st with Failed m -> !Source.log m | Done _ | Pending -> ());
        Source.settle source (write g st)
      end
    in
    let start () =
      incr run;
      let g = !run in
      let a =
        if !first then begin
          first := false;
          let reading = !Embedded.reading in
          Embedded.reading := Some Embedded.answer;
          let a = guard f () in
          Embedded.reading := reading;
          a
        end
        else guard f ()
      in
      (match a.status with
      | Pending -> Source.run source (fun () -> State.set out (Status.Loading !last))
      | Done _ | Failed _ -> ());
      on_settled a (settle g)
    in
    if !(Base.server_rendering ()) then start ()
    else begin
      Base.run_effect Scheduler.queue start;
      Base.own (fun () ->
          incr run;
          Source.leave source)
    end;
    State.read_only out

  type waiter = { wait : 'a. 'a t -> ('a -> unit) -> unit }

  let waiter =
    ref
      {
        wait =
          (fun a _ ->
            if Dev.on then
              match a.status with
              | Pending ->
                  Web.console_error
                    "yuka: an Await with no loading has no Pending above it, so it shows nothing until its value is settled"
              | Done _ | Failed _ -> ());
      }
