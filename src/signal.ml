(* Adapted from reativa (https://github.com/brnrdog/reativa, commit c6d6e5f).
   Copyright (c) 2025-2026 Bernardo Gurgel. MIT licence: see LICENSE.reativa. *)

type 'a t = {
  mutable value : 'a;
  equal : ('a -> 'a -> bool) option;
  node : Core.node;
}

(* Melange floats are JS numbers, so [js] is true only there. On native,
   tags 252 and 253 are [Obj.string_tag] and [Obj.double_tag]; the casts
   follow those tags. *)
let js = Obj.is_int (Obj.repr 0.5)

let native_same a b =
  let a = Obj.repr a and b = Obj.repr b in
  if Obj.is_int a || Obj.is_int b then a == b
  else
    let tag = Obj.tag a in
    if tag = 253 then Obj.tag b = 253 && (Obj.obj a : float) = Obj.obj b
    else
      a == b
      || (tag = 252 && Obj.tag b = 252 && String.equal (Obj.obj a) (Obj.obj b))

let same a b = if js then a == b else native_same a b

let differs equal a b =
  match equal with
  | None -> not (same a b)
  | Some equal -> ( try not (equal a b) with _ -> true)

let make ?equal value = { value; equal; node = Core.make_signal_node () }

let get s =
  Scheduler.ensure_computed_fresh s.node;
  Scheduler.track_dep s.node;
  s.value

let peek s =
  Scheduler.ensure_computed_fresh s.node;
  s.value

let set s value =
  if differs s.equal s.value value then begin
    s.value <- value;
    s.node.version <- s.node.version + 1;
    incr Core.global_version;
    Scheduler.notify_subs s.node
  end

let update s f = set s (f s.value)

let computed ?equal compute =
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
