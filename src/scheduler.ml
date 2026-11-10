(* Adapted from reativa (https://github.com/brnrdog/reativa, commit c6d6e5f).
   Copyright (c) 2025-2026 Bernardo Gurgel. MIT licence: see LICENSE.reativa. *)

open Core

let current_target : node option ref = ref None
let current_tracking_version = ref 0
let current_dep_cursor : link option ref = ref None
let pending_effects : node list ref = ref []
let pending_computeds : node list ref = ref []
let flushing = ref false

let add_effect_to_pending node =
  if not (is_pending node) then begin
    set_pending node;
    pending_effects := node :: !pending_effects
  end

let add_computed_to_pending node =
  if not (is_pending node) then begin
    set_pending node;
    pending_computeds := node :: !pending_computeds
  end

let new_link target source version =
  let link = make_link ~source ~target in
  link.last_tracked_version <- version;
  link_to_deps target link;
  link_to_subs source link;
  current_dep_cursor := Some link

let track_dep_into target source =
  let version = !current_tracking_version in
  match target.first_dep with
  | None -> new_link target source version
  | Some _ ->
      let fast =
        match !current_dep_cursor with
        | Some cursor when cursor.source == source ->
            cursor.last_tracked_version <- version;
            true
        | Some cursor -> (
            match cursor.next_dep with
            | Some next when next.source == source ->
                next.last_tracked_version <- version;
                current_dep_cursor := Some next;
                true
            | _ -> false)
        | None -> false
      in
      if not fast then
        let rec scan = function
          | Some l when l.source == source ->
              l.last_tracked_version <- version;
              current_dep_cursor := Some l
          | Some l -> scan l.next_dep
          | None -> new_link target source version
        in
        scan target.first_dep

let track_dep source =
  match !current_target with
  | Some target -> track_dep_into target source
  | None -> ()

let compute_level node =
  let max_level = ref 0 in
  let rec loop = function
    | None -> ()
    | Some l ->
        if is_computed l.source && l.source.level > !max_level then
          max_level := l.source.level;
        loop l.next_dep
  in
  loop node.first_dep;
  !max_level + 1

let prune_stale_deps node =
  let version = !current_tracking_version in
  let rec loop = function
    | None -> ()
    | Some l ->
        let next = l.next_dep in
        if l.last_tracked_version <> version then begin
          unlink_from_subs l;
          unlink_from_deps l
        end;
        loop next
  in
  loop node.first_dep

let with_tracking node body =
  let prev_version = !current_tracking_version in
  let prev_target = !current_target in
  let prev_cursor = !current_dep_cursor in
  incr tracking_version;
  current_tracking_version := !tracking_version;
  current_target := Some node;
  current_dep_cursor := node.first_dep;
  let finish () =
    current_target := prev_target;
    current_dep_cursor := prev_cursor;
    current_tracking_version := prev_version
  in
  match body () with
  | result ->
      prune_stale_deps node;
      finish ();
      result
  | exception e ->
      finish ();
      raise e

let run_body f = match f with Some f -> f () | None -> ()

let run_computed_cycle node ~should_clear_pending =
  let previous_version = node.version in
  if should_clear_pending then clear_pending node;
  with_tracking node (fun () -> run_body node.compute);
  clear_dirty node;
  node.last_global_version <- !global_version;
  if node.version <> previous_version then
    let rec loop = function
      | None -> ()
      | Some (l : link) ->
          let sub = l.target in
          (if is_computed sub then set_dirty sub
           else
             match !current_target with
             | Some cur when cur == sub -> ()
             | _ -> add_effect_to_pending sub);
          loop l.next_sub
    in
    loop node.first_sub

let retrack_computed node =
  let old_level = node.level in
  run_computed_cycle node ~should_clear_pending:true;
  if old_level = 0 then node.level <- compute_level node

let retrack_effect node =
  let old_level = node.level in
  clear_pending node;
  with_tracking node (fun () -> run_body node.run);
  clear_dirty node;
  if old_level = 0 then node.level <- compute_level node

let by_level a b = compare a.level b.level

let run_batch first_error retrack queue =
  let batch = List.sort by_level !queue in
  queue := [];
  List.iter
    (fun node ->
      try retrack node
      with e -> if Option.is_none !first_error then first_error := Some e)
    batch

let max_rounds = 100

let loop_error =
  Failure
    ("Yuka: an effect or a memo keeps changing a State it reads (more than "
    ^ string_of_int max_rounds ^ " update rounds in one flush)")

let drop queue =
  List.iter clear_pending !queue;
  queue := []

let flush () =
  flushing := true;
  let first_error = ref None in
  let rounds = ref 0 in
  while !pending_computeds <> [] || !pending_effects <> [] do
    if !rounds >= max_rounds then begin
      drop pending_computeds;
      drop pending_effects;
      if Option.is_none !first_error then first_error := Some loop_error
    end
    else begin
      incr rounds;
      if !pending_computeds <> [] then
        run_batch first_error retrack_computed pending_computeds;
      if !pending_effects <> [] then
        run_batch first_error retrack_effect pending_effects
    end
  done;
  flushing := false;
  Option.iter raise !first_error

let notify_subs source =
  (match source.first_sub with
  | None -> ()
  | Some _
    when (not (is_computed source)) && source.computed_subscriber_count = 0 ->
      let rec loop = function
        | None -> ()
        | Some (l : link) ->
            add_effect_to_pending l.target;
            loop l.next_sub
      in
      loop source.first_sub
  | Some _ ->
      let queue = Queue.create () in
      Queue.push source queue;
      while not (Queue.is_empty queue) do
        let s = Queue.pop queue in
        let rec loop = function
          | None -> ()
          | Some (l : link) ->
              let target = l.target in
              if is_computed target then begin
                if not (is_dirty target) then begin
                  set_dirty target;
                  Queue.push target queue
                end
              end
              else if is_computed s && s.defer_effects_until_recompute then
                add_computed_to_pending s
              else add_effect_to_pending target;
              loop l.next_sub
        in
        loop s.first_sub
      done);
  if (!pending_effects <> [] || !pending_computeds <> []) && not !flushing then
    flush ()

let ensure_computed_fresh node =
  if is_computed node && is_dirty node then
    if node.last_global_version = !global_version then clear_dirty node
    else
      let old_level = node.level in
      run_computed_cycle node ~should_clear_pending:false;
      if old_level = 0 then node.level <- compute_level node

let untrack fn =
  let prev_target = !current_target in
  let prev_cursor = !current_dep_cursor in
  current_target := None;
  current_dep_cursor := None;
  let restore () =
    current_target := prev_target;
    current_dep_cursor := prev_cursor
  in
  match fn () with
  | result ->
      restore ();
      result
  | exception e ->
      restore ();
      raise e
