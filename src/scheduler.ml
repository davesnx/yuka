type cell = {
  mutable dispose : unit -> unit;
  mutable prev : cell option;
  mutable next : cell option;
  mutable live : bool;
}

type binding = ..
type env = Empty | Bound of binding * env | Island of env | Root of string

type owner = {
  mutable last : cell option;
  mutable gen : int;
  mutable catch : (exn -> unit) option;
  mutable env : env;
  parent : owner option;
}

let catch o e = match o.catch with Some h -> h e | None -> raise e

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
  mutable owner : owner option;
  depth : int;
  id : int;
  eff : node list ref option;
}

and link = {
  src : node;
  dst : node;
  mutable prev : link option;
  mutable next : link option;
  mutable dep : link option;
  mutable at : int;
}

let js = Obj.is_int (Obj.repr 0.5)
let ids = ref 0
let sealed = ref (-1)
let seal () = if (not js) && !sealed < 0 then sealed := !ids
let stack = ref 0
let listener = ref None
let queue = ref []
let late = ref []
let depth = ref 0
let nest = ref 0
let writes = ref 0
let later = ref ignore

type domain = {
  stack : int ref;
  listener : node option ref;
  queue : node list ref;
  late : node list ref;
  depth : int ref;
  nest : int ref;
  writes : int ref;
  later : (unit -> unit) ref;
  owner : owner option ref;
  rendering : bool ref;
}

let key =
  if js then None
  else
    Some
      (Web.local (fun () ->
           {
             stack = ref 0;
             listener = ref None;
             queue = ref [];
             late = ref [];
             depth = ref 0;
             nest = ref 0;
             writes = ref 0;
             later = ref ignore;
             owner = ref None;
             rendering = ref false;
           }))

let here r f = match key with Some k when not js -> f (Web.local_get k) | _ -> r
let stack () = here stack (fun d -> d.stack)
let listener () = here listener (fun d -> d.listener)
let mine q = here q (fun d -> if q == late then d.late else d.queue)
let depth () = here depth (fun d -> d.depth)
let nest () = here nest (fun d -> d.nest)
let writes () = here writes (fun d -> d.writes)
let later () = here later (fun d -> d.later)
let never () = false

let check_write n =
  if (not js) && n.id <= !sealed then
    invalid_arg
      "Yuka.State: a write to a State made at module level, before the first server render or request. The server process has one copy for every request. Create the State inside a component."

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
    owner = None;
    depth = !(stack ());
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
  match !(listener ()) with
  | Some dst when dst.state <> 3 && (js || src.id > !sealed) -> (
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
  let listener = listener () in
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

let mark n state =
  let stack = ref [] and next = ref n.first in
  while !next != None || !stack != [] do
    match !next with
    | Some l ->
        let o = l.dst in
        let state = match !stack with [] -> state | _ :: _ -> 1 in
        next := l.next;
        if o.state < state && o != l.src && (l.at = o.runs || o.state < 0)
        then begin
          let was = o.state in
          o.state <- (if was < 0 then 2 else state);
          if was <= 0 then
            match o.eff with
            | Some q -> q := o :: !q
            | None ->
                stack := !next :: !stack;
                next := o.first
        end
    | None -> (
        match !stack with
        | [] -> ()
        | l :: rest ->
            stack := rest;
            next := l)
  done

let loop =
  Failure
    "Yuka: an effect or a memo keeps changing a State it reads (more than 100 \
     update rounds in one flush)"

let rec restore = function
  | (c, f) :: rest ->
      if c.state <> 3 then begin
        if c.state = -2 then c.state <- -1;
        c.fn <- f
      end;
      restore rest
  | [] -> ()

let rec run n =
  n.rest <- n.head;
  n.head <- None;
  n.tail <- None;
  n.runs <- n.runs + 1;
  n.state <- 0;
  let stack = stack () in
  let outer = !stack in
  stack := n.depth + 1;
  let changed =
    try with_listener (Some n) n.fn
    with e ->
      stack := outer;
      let rec refresh = function
        | Some l ->
            (try settle 100 l.src with _ -> ());
            refresh l.dep
        | None -> ()
      in
      refresh n.rest;
      if n.rest != None then (
        match n.tail with Some t -> t.dep <- n.rest | None -> n.head <- n.rest);
      n.rest <- None;
      raise e
  in
  stack := outer;
  unlink_all n.rest;
  n.rest <- None;
  (match n.head with Some _ when n.level = 0 -> set_level n | _ -> ());
  if changed then mark n 2

and settle left n =
  let writes = writes () and nest = nest () in
  incr nest;
  let deep = !nest > 100 in
  let stack = ref [] and node = ref n and work = ref true and swapped = ref [] in
  let before = ref !writes and next = ref n.head in
  while !work do
    let n = !node in
    if deep && (n.state = 2 || n.state = -1) then n.state <- 4;
    match if n.state = 1 || n.state = 4 then !next else None with
    | Some l when l.src.state = 4 ->
        n.state <- 2;
        next := l.dep
    | Some l ->
        stack := (!before, l) :: !stack;
        node := l.src;
        before := !writes;
        next := l.src.head
    | None -> (
        if n.state = 1 && !writes = !before then n.state <- 0;
        let left = match !stack with [] -> left | _ :: _ -> 100 in
        (match
           if
             n.state = 1
             || n.state <> 0 && n.state <> 3
                && begin
                     run n;
                     n.eff = None && n.state > 0
                   end
           then if left = 0 then raise loop else settle (left - 1) n
         with
        | () -> ()
        | exception e -> (
            n.state <- -1;
            match !stack with
            | [] ->
                decr nest;
                restore !swapped;
                raise e
            | (_, l) :: _ ->
                if deep then begin
                  let f = n.fn and w = !writes in
                  let fake () =
                    n.fn <- f;
                    if !writes <> w then f ()
                    else begin
                      n.head <- n.rest;
                      n.rest <- None;
                      raise e
                    end
                  in
                  n.fn <- fake;
                  n.state <- -2;
                  swapped := (n, f) :: !swapped
                end;
                l.dst.state <- 2));
        match !stack with
        | [] -> work := false
        | (b, l) :: rest ->
            stack := rest;
            node := l.dst;
            before := b;
            next := l.dep)
  done;
  decr nest;
  restore !swapped

let stale n =
  n.state <- -1;
  let stack = ref [] and next = ref n.head in
  while !next != None || !stack != [] do
    match !next with
    | Some l ->
        let s = l.src in
        if s.state > 0 && s.state < 3 && s.head <> None then begin
          s.state <- -1;
          stack := l :: !stack;
          next := s.head
        end
        else begin
          if s.state > 0 && s.state < 3 then run s;
          next := l.dep
        end
    | None -> (
        match !stack with
        | [] -> ()
        | l :: rest ->
            stack := rest;
            next := l.dep)
  done

let before (a : node) (b : node) =
  a.depth < b.depth
  || a.depth = b.depth
     && (a.level < b.level || (a.level = b.level && a.id > b.id))

let rec rev_onto acc l = match acc with [] -> l | x :: r -> rev_onto r (x :: l)

let rec merge acc a b =
  match (a, b) with
  | [], l | l, [] -> rev_onto acc l
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
  depth () := 1;
  let error = ref None and rounds = ref 0 in
  let fail e = match !error with None -> error := Some e | Some _ -> () in
  let rec round () =
    let queue = mine queue and late = mine late in
    (match !queue with
    | [] ->
        queue := !late;
        late := []
    | _ -> ());
    match !queue with
    | [] -> ()
    | q ->
        queue := [];
        if !rounds >= 100 then begin
          let rec drop = function
            | [] -> ()
            | n :: rest ->
                if n.state <> 3 then (try stale n with e -> fail e);
                drop rest
          in
          fail loop;
          drop q
        end
        else begin
          incr rounds;
          let rec run_all = function
            | [] -> ()
            | n :: rest ->
                (try settle 100 n
                 with e -> (
                   match n.owner with
                   | Some o -> ( try catch o e with e -> fail e)
                   | None -> fail e));
                run_all rest
          in
          run_all (if sorted q then q else sort q)
        end;
        round ()
  in
  round ();
  depth () := 0;
  match !error with Some e -> raise e | None -> ()

let after f =
  let depth = depth () and later = later () in
  if !depth = 0 then f ()
  else
    let g = !later in
    later := fun () -> g (); f ()

let flush_all () =
  flush ();
  let later = later () in
  let g = !later in
  later := ignore;
  g ()

let changed n =
  let writes = writes () and depth = depth () in
  incr writes;
  if !depth = 0 then begin
    run n;
    flush_all ()
  end
  else if n.first == None then run n
  else begin
    n.state <- 2;
    mark n 1
  end

let finish () =
  let depth = depth () in
  decr depth;
  if !depth = 0 then flush_all ()

let batch f =
  incr (depth ());
  match f () with
  | v ->
      finish ();
      v
  | exception e ->
      (try finish () with _ -> ());
      raise e

let fresh n =
  if n.state <> 0 && (n.head != None || !(listener ()) != None) then batch (fun () -> settle 100 n)
