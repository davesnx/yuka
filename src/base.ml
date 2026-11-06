type owner = { mutable next : int; disposers : (int, unit -> unit) Hashtbl.t }

let current_owner : owner option ref = ref None
let new_owner () = { next = 0; disposers = Hashtbl.create 8 }

let add_disposer o dispose =
  o.next <- o.next + 1;
  Hashtbl.replace o.disposers o.next dispose;
  o.next

let own dispose =
  match !current_owner with
  | Some o -> ignore (add_disposer o dispose)
  | None -> ()

let with_owner o f =
  let prev = !current_owner in
  current_owner := Some o;
  match f () with
  | result ->
      current_owner := prev;
      result
  | exception e ->
      current_owner := prev;
      raise e

let dispose_owner o =
  let all = Hashtbl.fold (fun id dispose acc -> (id, dispose) :: acc) o.disposers [] in
  Hashtbl.reset o.disposers;
  List.iter
    (fun (_, dispose) -> dispose ())
    (List.sort (fun (a, _) (b, _) -> compare b a) all)

let mount f =
  let o = new_owner () in
  match with_owner o f with
  | result -> (result, fun () -> dispose_owner o)
  | exception e ->
      dispose_owner o;
      raise e

module State = struct
  type 'a t = 'a Signal.t

  let make = Signal.make
  let get = Signal.get
  let peek = Signal.peek
  let set = Signal.set
  let update = Signal.update

  let memo ?equal f =
    let s = Signal.computed ?equal f in
    own (fun () -> Signal.dispose_computed s);
    s
end

let server_rendering = ref false

module Effect = struct
  let run ?cleanup body =
    if !server_rendering then () else
    let child = new_owner () in
    let last = ref None in
    let teardown () =
      dispose_owner child;
      match !last with
      | None -> ()
      | Some result ->
          last := None;
          Option.iter (fun cleanup -> cleanup result) cleanup
    in
    let node =
      Core.make_effect_node (fun () ->
          teardown ();
          last := Some (with_owner child body))
    in
    let stop () =
      node.run <- None;
      teardown ();
      Core.clear_deps node
    in
    (match Scheduler.with_tracking node (fun () -> Scheduler.run_body node.run) with
    | () -> ()
    | exception e ->
        stop ();
        raise e);
    Core.clear_dirty node;
    node.level <- Scheduler.compute_level node;
    own stop

  let on_change ?(equal = Signal.default_equal) state f =
    let prev = ref (Signal.peek state) in
    run (fun () ->
        let next = Signal.get state in
        if Signal.differs equal !prev next then begin
          let p = !prev in
          prev := next;
          Scheduler.untrack (fun () -> f ~prev:p ~next)
        end)
end
