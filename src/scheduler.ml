(* Adapted from Solid (solid-js/src/reactive/signal.ts, version 1.9).
   Copyright (c) 2016-2023 Ryan Carniato. MIT licence: see LICENSE.solid. *)

type node = {
  mutable first : link option;
  mutable last : link option;
  mutable head : link option;
  mutable tail : link option;
  mutable rest : link option;
  mutable state : int;
  mutable fn : unit -> bool;
  mutable level : int;
  mutable runs : int;
  depth : int;
  id : int;
  eff : bool;
}

and link = {
  src : node;
  dst : node;
  mutable prev : link option;
  mutable next : link option;
  mutable dep : link option;
  mutable at : int;
}

let ids = ref 0
let stack = ref 0
let listener = ref None
let queue = ref []
let depth = ref 0
let never () = false

let make eff fn =
  incr ids;
  {
    first = None;
    last = None;
    head = None;
    tail = None;
    rest = None;
    state = 0;
    fn;
    level = 0;
    runs = 0;
    depth = !stack;
    id = !ids;
    eff;
  }

let unlink l =
  let s = l.src in
  (match l.prev with Some p -> p.next <- l.next | None -> s.first <- l.next);
  match l.next with Some n -> n.prev <- l.prev | None -> s.last <- l.prev

let rec unlink_all = function
  | Some l ->
      let d = l.dep in
      unlink l;
      unlink_all d
  | None -> ()

let dispose n =
  unlink_all n.head;
  unlink_all n.rest;
  n.head <- None;
  n.tail <- None;
  n.rest <- None;
  n.fn <- never;
  n.state <- 3

let append dst l =
  l.at <- dst.runs;
  l.dep <- None;
  (match dst.tail with Some t -> t.dep <- Some l | None -> dst.head <- Some l);
  dst.tail <- Some l

let track src =
  match !listener with
  | Some dst when dst.state <> 3 -> (
      match (dst.rest, src.last) with
      | Some l, _ when l.src == src ->
          dst.rest <- l.dep;
          append dst l
      | _, Some l when l.dst == dst && l.at = dst.runs -> ()
      | _, last ->
          let l = { src; dst; prev = last; next = None; dep = None; at = 0 } in
          (match last with Some p -> p.next <- Some l | None -> src.first <- Some l);
          src.last <- Some l;
          append dst l)
  | _ -> ()

let with_listener n f =
  let prev = !listener in
  listener := n;
  match f () with
  | v ->
      listener := prev;
      v
  | exception e ->
      listener := prev;
      raise e

let untrack f = with_listener None f

let set_level n =
  let rec go m = function
    | Some l -> go (if l.src.level > m then l.src.level else m) l.dep
    | None -> m
  in
  n.level <- 1 + go 0 n.head

let rec mark skip n state =
  let rec go = function
    | Some l ->
        let o = l.dst in
        if o.state < state && o != skip then begin
          let was = o.state in
          o.state <- (if was < 0 then 2 else state);
          if was <= 0 then if o.eff then queue := o :: !queue else mark skip o 1
        end;
        go l.next
    | None -> ()
  in
  go n.first

let run n =
  n.rest <- n.head;
  n.head <- None;
  n.tail <- None;
  n.runs <- n.runs + 1;
  n.state <- 0;
  incr stack;
  let changed =
    match with_listener (Some n) n.fn with
    | c ->
        decr stack;
        unlink_all n.rest;
        n.rest <- None;
        c
    | exception e ->
        decr stack;
        (match n.tail with Some t -> t.dep <- n.rest | None -> n.head <- n.rest);
        n.rest <- None;
        raise e
  in
  if n.level = 0 then set_level n;
  if changed then mark (Option.value !listener ~default:n) n 2

let rec fresh n =
  if n.state <> 0 && n.state <> 3 then
    try
      if n.state = 1 then begin
        let rec check = function
          | Some l when n.state = 1 ->
              fresh l.src;
              check l.dep
          | _ -> ()
        in
        check n.head;
        if n.state = 1 then n.state <- 0
      end;
      if n.state = 2 || n.state < 0 then run n
    with e ->
      n.state <- (if n.eff then 0 else -1);
      raise e

let rec stale n =
  let rec go = function
    | Some l ->
        let s = l.src in
        if s.state > 0 && s.state < 3 then begin
          s.state <- -1;
          stale s
        end;
        go l.dep
    | None -> ()
  in
  go n.head

let before a b =
  a.depth < b.depth
  || a.depth = b.depth
     && (a.level < b.level || (a.level = b.level && a.id > b.id))

let rec merge acc a b =
  match (a, b) with
  | [], l | l, [] -> List.rev_append acc l
  | x :: a', y :: b' ->
      if before y x then merge (y :: acc) a b' else merge (x :: acc) a' b

let rec sorted = function
  | a :: (b :: _ as r) -> before a b && sorted r
  | _ -> true

let rec sort = function
  | ([] | [ _ ]) as l -> l
  | l ->
      let rec split a b = function [] -> (a, b) | x :: r -> split b (x :: a) r in
      let a, b = split [] [] l in
      merge [] (sort a) (sort b)

let flush () =
  match !queue with
  | [] -> ()
  | _ ->
      depth := 1;
      let error = ref None and rounds = ref 0 in
      let fail e = if Option.is_none !error then error := Some e in
      let rec loop () =
        match !queue with
        | [] -> ()
        | q ->
            queue := [];
            if !rounds >= 100 then begin
              List.iter
                (fun n ->
                  if n.state <> 3 then begin
                    n.state <- 0;
                    stale n
                  end)
                q;
              fail
                (Failure
                   "Yuka: an effect or a memo keeps changing a State it reads \
                    (more than 100 update rounds in one flush)")
            end
            else begin
              incr rounds;
              List.iter
                (fun n -> try fresh n with e -> fail e)
                (if sorted q then q else sort q)
            end;
            loop ()
      in
      loop ();
      depth := 0;
      Option.iter raise !error

let changed n =
  mark n n 2;
  if !depth = 0 then flush ()

let finish () =
  decr depth;
  if !depth = 0 then flush ()

let batch f =
  incr depth;
  match f () with
  | v ->
      finish ();
      v
  | exception e ->
      (try finish () with _ -> ());
      raise e

let start n =
  incr depth;
  match run n with
  | () -> finish ()
  | exception e ->
      (try finish () with _ -> ());
      raise e
