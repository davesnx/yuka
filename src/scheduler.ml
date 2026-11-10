(* The graph follows Solid's signal core (solid-js/src/reactive/signal.ts,
   MIT): a write marks its readers dirty and their readers to check; reads
   and the flush pull a node up to date before it runs. *)

type node = {
  mutable deps : link list;
  mutable old : link list;
  mutable first : link option;
  mutable last : link option;
  mutable state : int;
  mutable fn : unit -> bool;
  mutable level : int;
  id : int;
  eff : bool;
}

and link = {
  src : node;
  dst : node;
  mutable prev : link option;
  mutable next : link option;
}

let ids = ref 0
let listener = ref None
let queue = ref []
let depth = ref 0

let never () = false

let make eff fn =
  incr ids;
  { deps = []; old = []; first = None; last = None; state = 0; fn; level = 0; id = !ids; eff }

let unlink l =
  let s = l.src in
  (match l.prev with Some p -> p.next <- l.next | None -> s.first <- l.next);
  match l.next with Some n -> n.prev <- l.prev | None -> s.last <- l.prev

let dispose n =
  List.iter unlink n.deps;
  List.iter unlink n.old;
  n.deps <- [];
  n.old <- [];
  n.fn <- never

let track src =
  match !listener with
  | Some dst -> (
      match (dst.old, src.last) with
      | l :: old, _ when l.src == src ->
          dst.old <- old;
          dst.deps <- l :: dst.deps
      | _, Some l when l.dst == dst && not (List.memq l dst.old) -> ()
      | _, last ->
          let l = { src; dst; prev = last; next = None } in
          (match last with Some p -> p.next <- Some l | None -> src.first <- Some l);
          src.last <- Some l;
          dst.deps <- l :: dst.deps)
  | None -> ()

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
  n.level <-
    1 + List.fold_left (fun m l -> if l.src.level > m then l.src.level else m) 0 n.deps

let rec mark skip n state =
  let rec go = function
    | Some l ->
        let o = l.dst in
        if o.state < state && o != skip then begin
          let was = o.state in
          o.state <- state;
          if was = 0 then if o.eff then queue := o :: !queue else mark skip o 1
        end;
        go l.next
    | None -> ()
  in
  go n.first

let drop n =
  List.iter unlink n.old;
  n.old <- []

let run n =
  n.old <- List.rev n.deps;
  n.deps <- [];
  n.state <- 0;
  let changed =
    match with_listener (Some n) n.fn with
    | c ->
        drop n;
        c
    | exception e ->
        drop n;
        raise e
  in
  if n.level = 0 then set_level n;
  if changed then mark (Option.value !listener ~default:n) n 2

let rec fresh n =
  if n.state > 0 then
    try
      if n.state = 1 then begin
        List.iter (fun l -> if n.state = 1 then fresh l.src) (List.rev n.deps);
        if n.state = 1 then n.state <- 0
      end;
      if n.state = 2 then run n
    with e ->
      n.state <- (if n.eff then 0 else 2);
      raise e

let before a b = a.level < b.level || (a.level = b.level && a.id > b.id)

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
              List.iter (fun n -> n.state <- 0) q;
              fail
                (Failure
                   "Yuka: an effect or a memo keeps changing a State it reads \
                    (more than 100 update rounds in one flush)")
            end
            else begin
              incr rounds;
              List.iter (fun n -> try fresh n with e -> fail e) (if sorted q then q else sort q)
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
