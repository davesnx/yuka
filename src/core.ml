(* Adapted from reativa (https://github.com/brnrdog/reativa, commit c6d6e5f).
   Copyright (c) 2025-2026 Bernardo Gurgel. MIT licence: see LICENSE.reativa. *)

let flag_dirty = 1
let flag_pending = 2
let tracking_version = ref 0
let global_version = ref 0

type node = {
  mutable first_dep : link option;
  mutable last_dep : link option;
  mutable first_sub : link option;
  mutable last_sub : link option;
  mutable computed_subscriber_count : int;
  mutable version : int;
  mutable flags : int;
  mutable level : int;
  mutable last_global_version : int;
  mutable compute : (unit -> unit) option;
  mutable run : (unit -> unit) option;
  mutable defer_effects_until_recompute : bool;
}

and link = {
  source : node;
  target : node;
  mutable next_dep : link option;
  mutable prev_dep : link option;
  mutable next_sub : link option;
  mutable prev_sub : link option;
  mutable last_tracked_version : int;
}

let make_node ~flags ~compute ~run ~defer_effects_until_recompute =
  {
    first_dep = None;
    last_dep = None;
    first_sub = None;
    last_sub = None;
    computed_subscriber_count = 0;
    version = 0;
    flags;
    level = 0;
    last_global_version = 0;
    compute;
    run;
    defer_effects_until_recompute;
  }

let make_signal_node () =
  make_node ~flags:0 ~compute:None ~run:None
    ~defer_effects_until_recompute:false

let make_computed_node ~defer_effects_until_recompute =
  make_node ~flags:flag_dirty ~compute:None ~run:None
    ~defer_effects_until_recompute

let make_effect_node run =
  make_node ~flags:flag_dirty ~compute:None ~run:(Some run)
    ~defer_effects_until_recompute:false

let is_computed n = Option.is_some n.compute
let is_dirty n = n.flags land flag_dirty <> 0
let set_dirty n = n.flags <- n.flags lor flag_dirty
let clear_dirty n = n.flags <- n.flags land lnot flag_dirty
let is_pending n = n.flags land flag_pending <> 0
let set_pending n = n.flags <- n.flags lor flag_pending
let clear_pending n = n.flags <- n.flags land lnot flag_pending

let make_link ~source ~target =
  {
    source;
    target;
    next_dep = None;
    prev_dep = None;
    next_sub = None;
    prev_sub = None;
    last_tracked_version = 0;
  }

let link_to_subs source link =
  link.prev_sub <- source.last_sub;
  link.next_sub <- None;
  (match source.last_sub with
  | Some last -> last.next_sub <- Some link
  | None -> source.first_sub <- Some link);
  source.last_sub <- Some link;
  if is_computed link.target then
    source.computed_subscriber_count <- source.computed_subscriber_count + 1

let link_to_deps target link =
  link.prev_dep <- target.last_dep;
  link.next_dep <- None;
  (match target.last_dep with
  | Some last -> last.next_dep <- Some link
  | None -> target.first_dep <- Some link);
  target.last_dep <- Some link

let unlink_from_subs link =
  let source = link.source in
  (match link.prev_sub with
  | Some prev -> prev.next_sub <- link.next_sub
  | None -> source.first_sub <- link.next_sub);
  (match link.next_sub with
  | Some next -> next.prev_sub <- link.prev_sub
  | None -> source.last_sub <- link.prev_sub);
  link.prev_sub <- None;
  link.next_sub <- None;
  if is_computed link.target && source.computed_subscriber_count > 0 then
    source.computed_subscriber_count <- source.computed_subscriber_count - 1

let unlink_from_deps link =
  let target = link.target in
  (match link.prev_dep with
  | Some prev -> prev.next_dep <- link.next_dep
  | None -> target.first_dep <- link.next_dep);
  (match link.next_dep with
  | Some next -> next.prev_dep <- link.prev_dep
  | None -> target.last_dep <- link.prev_dep);
  link.prev_dep <- None;
  link.next_dep <- None

let clear_deps node =
  let rec loop = function
    | None -> ()
    | Some l ->
        let next = l.next_dep in
        unlink_from_subs l;
        loop next
  in
  loop node.first_dep;
  node.first_dep <- None;
  node.last_dep <- None
