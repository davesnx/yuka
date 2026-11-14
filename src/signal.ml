type 'a t = {
  mutable value : 'a;
  equal : ('a -> 'a -> bool) option;
  node : Scheduler.node;
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

let make ?equal value = { value; equal; node = Scheduler.make None Scheduler.never }

let peek s =
  Scheduler.fresh s.node;
  s.value

let get s =
  (if s.node.state <> 0 then
     try Scheduler.fresh s.node
     with e ->
       Scheduler.track s.node;
       raise e);
  Scheduler.track s.node;
  s.value

let set s value =
  if differs s.equal s.value value then begin
    s.value <- value;
    Scheduler.changed s.node
  end

let update s f = set s (f s.value)

let computed ?equal compute =
  let node = Scheduler.make None Scheduler.never in
  let value =
    match Scheduler.with_listener (Some node) compute with
    | v -> v
    | exception e ->
        Scheduler.dispose node;
        raise e
  in
  let s = { value; equal; node } in
  Scheduler.set_level node;
  node.fn <-
    (fun () ->
      let next = compute () in
      differs equal s.value next
      && begin
           s.value <- next;
           true
         end);
  s

let dispose_computed s = Scheduler.dispose s.node
