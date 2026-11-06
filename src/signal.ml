(* Adapted from reativa (https://github.com/brnrdog/reativa, commit c6d6e5f).
   Copyright (c) 2025-2026 Bernardo Gurgel. MIT licence: see LICENSE.reativa. *)

type 'a t = { mutable value : 'a; equal : 'a -> 'a -> bool; node : Core.node }

let default_equal a b = a == b || try a = b with Invalid_argument _ -> false
let differs equal a b = try not (equal a b) with _ -> true

let make ?(equal = default_equal) value =
  { value; equal; node = Core.make_signal_node () }

let get s =
  Scheduler.ensure_computed_fresh s.node;
  Scheduler.track_dep s.node;
  s.value

let peek s =
  Scheduler.ensure_computed_fresh s.node;
  s.value

let set s value =
  if Core.is_computed s.node then invalid_arg "Yuka: State.set on a memo";
  if differs s.equal s.value value then begin
    s.value <- value;
    s.node.version <- s.node.version + 1;
    incr Core.global_version;
    Scheduler.notify_subs s.node
  end

let update s f =
  if Core.is_computed s.node then invalid_arg "Yuka: State.set on a memo";
  set s (f s.value)

let computed ?(equal = default_equal) compute =
  let node = Core.make_computed_node ~defer_effects_until_recompute:true in
  let cell = ref None in
  node.compute <-
    Some
      (fun () ->
        match !cell with
        | None -> ()
        | Some s ->
            let next = compute () in
            if differs s.equal s.value next then begin
              s.value <- next;
              node.version <- node.version + 1
            end);
  let s = { value = Scheduler.with_tracking node compute; equal; node } in
  cell := Some s;
  node.last_global_version <- !Core.global_version;
  Core.clear_dirty node;
  node.level <- Scheduler.compute_level node;
  s

let dispose_computed s =
  s.node.compute <- Some ignore;
  Core.clear_deps s.node
