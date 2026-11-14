open Yuka

exception Boom of int
exception Abort

type expr =
  | Get of int
  | Peek of int
  | Untrack of expr
  | Sum of expr list
  | Min of expr list
  | Parity of expr
  | If of expr * expr * expr
  | Fail of int * expr

type kind = Before | After

type spec = {
  kind : kind;
  body : expr;
  cleanup : bool;
  kids : spec list;
  writes : int option;
}

type group_spec = { memos : expr list; effects : spec list; mode : int }
type item = W of int * int | R of int | Nest of item list | Nest_raise of item list

type op =
  | Set of int * int
  | Batch of item list * bool
  | Read of int
  | Create of group_spec
  | Dispose of int

type graph = {
  sources : int list;
  sinks : int;
  base_memos : expr list;
  base_effects : spec list;
}

type features = {
  dynamic : bool;
  untracked : bool;
  after : bool;
  nested : bool;
  cleanup : bool;
  groups : bool;
  batches : bool;
  writers : bool;
  raises : bool;
}

let static =
  {
    dynamic = false;
    untracked = false;
    after = false;
    nested = false;
    cleanup = false;
    groups = false;
    batches = false;
    writers = false;
    raises = false;
  }

type rng = { mutable s : int }

let rng seed = { s = ((seed * 7919) + 1) land 0x3FFFFFFF }

let next g =
  g.s <- ((g.s * 1103515245) + 12345) land 0x3FFFFFFF;
  g.s lsr 14

let int g n = next g mod n
let chance g p = int g 100 < p

let list n f =
  let rec go i acc = if i = 0 then List.rev acc else go (i - 1) (f () :: acc) in
  go n []

let rec reads_of = function
  | Get j | Peek j -> [ j ]
  | Untrack e | Parity e | Fail (_, e) -> reads_of e
  | Sum l | Min l -> List.concat_map reads_of l
  | If (a, b, c) -> reads_of a @ reads_of b @ reads_of c

let rec map_expr f = function
  | Get j -> Get (f j)
  | Peek j -> Peek (f j)
  | Untrack e -> Untrack (map_expr f e)
  | Sum l -> Sum (List.map (map_expr f) l)
  | Min l -> Min (List.map (map_expr f) l)
  | Parity e -> Parity (map_expr f e)
  | If (a, b, c) -> If (map_expr f a, map_expr f b, map_expr f c)
  | Fail (k, e) -> Fail (k, map_expr f e)

let rec map_spec f s =
  { s with body = map_expr f s.body; kids = List.map (map_spec f) s.kids }

let gen_expr g f pool =
  let n = Array.length pool in
  let leaf () =
    let j = pool.(int g n) in
    if f.untracked && chance g 15 then Peek j else Get j
  in
  let rec go d =
    if d = 0 then leaf ()
    else
      match int g 12 with
      | 0 | 1 | 2 -> leaf ()
      | 3 | 4 ->
          let k = 1 + int g 3 in
          Sum (list k (fun () -> go (d - 1)))
      | 5 ->
          let k = 1 + int g 3 in
          Min (list k (fun () -> go (d - 1)))
      | 6 -> Parity (go (d - 1))
      | 7 ->
          let j = pool.(int g n) in
          Sum [ Get j; Get j ]
      | 8 when f.dynamic ->
          let c = go (d - 1) in
          let a = go (d - 1) in
          let b = go (d - 1) in
          If (c, a, b)
      | 9 when f.untracked -> Untrack (go (d - 1))
      | 10 when f.raises ->
          let k = int g 6 in
          Fail (k, go (d - 1))
      | _ ->
          let a = go (d - 1) in
          let b = leaf () in
          Sum [ a; b ]
  in
  go 2

let rec gen_spec g f pool ~depth ~writes =
  let kind = if f.after && chance g 40 then After else Before in
  let body = gen_expr g f pool in
  let cleanup = f.cleanup && chance g 60 in
  let kids =
    if f.nested && writes = None && depth < 2 && chance g 50 then
      let k = 1 + int g 2 in
      list k (fun () -> gen_spec g f pool ~depth:(depth + 1) ~writes:None)
    else []
  in
  { kind; body; cleanup; kids; writes }

let range a b = Array.init (b - a) (fun i -> a + i)

let gen_graph g f =
  let nsrc = 2 + int g 3 in
  let sources = list nsrc (fun () -> int g 4) in
  let sinks = if f.writers then 1 + int g 2 else 0 in
  let first = nsrc + sinks in
  let nmemo = 3 + int g 6 in
  let taint = Array.make (first + nmemo) 0 in
  for k = 0 to sinks - 1 do
    taint.(nsrc + k) <- 1 lsl k
  done;
  let id = ref first in
  let base_memos =
    list nmemo (fun () ->
        let e = gen_expr g f (range 0 !id) in
        taint.(!id) <- List.fold_left (fun m j -> m lor taint.(j)) 0 (reads_of e);
        incr id;
        e)
  in
  let all = range 0 !id in
  let effects =
    let k = 2 + int g 3 in
    list k (fun () -> gen_spec g f all ~depth:0 ~writes:None)
  in
  let sink = ref 0 in
  let writers =
    list sinks (fun () ->
        let k = !sink in
        incr sink;
        let pool =
          Array.of_list
            (List.filter
               (fun j -> taint.(j) land lnot ((1 lsl k) - 1) = 0)
               (Array.to_list all))
        in
        gen_spec g f pool ~depth:0 ~writes:(Some (nsrc + k)))
  in
  { sources; sinks; base_memos; base_effects = effects @ writers }

let gen_ops g f graph =
  let nsrc = List.length graph.sources in
  let nbase = nsrc + graph.sinks + List.length graph.base_memos in
  let gen_group () =
    let nm = int g 3 in
    let id = ref nbase in
    let memos =
      list nm (fun () ->
          let e = gen_expr g f (range 0 !id) in
          incr id;
          e)
    in
    let pool = range 0 (nbase + nm) in
    let ne = 1 + int g 2 in
    let effects = list ne (fun () -> gen_spec g f pool ~depth:0 ~writes:None) in
    let mode = int g 3 in
    { memos; effects; mode }
  in
  let batch_items () =
    let order = Array.init nsrc (fun i -> i) in
    for i = nsrc - 1 downto 1 do
      let j = int g (i + 1) in
      let x = order.(i) in
      order.(i) <- order.(j);
      order.(j) <- x
    done;
    let free = ref (Array.to_list order) in
    let rec items depth =
      let k = 1 + int g 3 in
      list k (fun () ->
          match int g 10 with
          | (0 | 1) when depth < 2 -> Nest (items (depth + 1))
          | 2 when depth < 2 -> Nest_raise (items (depth + 1))
          | 3 -> R (int g 1000)
          | _ -> (
              match !free with
              | s :: rest ->
                  free := rest;
                  W (s, int g 4)
              | [] -> R (int g 1000)))
    in
    items 0
  in
  let n = 15 + int g 20 in
  list n (fun () ->
      let x = int g 100 in
      if x < 35 then
        let s = int g nsrc in
        Set (s, int g 4)
      else if x < 52 && f.batches then
        let items = batch_items () in
        Batch (items, chance g 15)
      else if x < 62 then Read (int g 1000)
      else if x < 74 && f.groups then Create (gen_group ())
      else if x < 82 && f.groups then Dispose (int g 1000)
      else
        let s = int g nsrc in
        Set (s, int g 4))

type ex = Val of int | Err of int | Unknown | Stale

type node = {
  id : int;
  expr : expr option;
  loose : bool;
  mutable alive : bool;
  mutable handle : int State.read option;
  mutable writer : int State.t option;
  mutable value : int;
  mutable ver : int;
  mutable ver0 : int;
  mutable computes : int;
  mutable computes_op : int;
  mutable m_reads : (int * int * int) list;
  mutable m_links : int list;
  mutable m_links0 : int list;
  mutable m_failed : bool;
}

type inst = {
  iid : int;
  spec : spec;
  created : int;
  mutable i_alive : bool;
  mutable i_alive0 : bool;
  mutable attempts : int;
  mutable oks : int;
  mutable ok_reads : (int * int) list;
  mutable ok_vers : (int * int) list;
  mutable seen : (int * ex) list;
  mutable seen0 : int list;
  mutable i_failed : bool;
  mutable pending : int option;
  mutable children : inst list;
  mutable ran_op : int;
}

type grp = {
  mutable g_memos : int list;
  mutable g_insts : inst list;
  mutable g_dispose : unit -> unit;
  mutable g_alive : bool;
}

type t = {
  seed : int;
  nbase : int;
  nsrc : int;
  nodes : node array;
  mutable count : int;
  mutable insts : inst list;
  mutable roots : inst list;
  mutable groups : grp list;
  mutable step : int;
  mutable exact : bool;
  mutable depth : int;
  mutable top : bool;
  mutable in_batch : int;
  mutable pulled : bool;
  mutable after_ran : bool;
  mutable escapes : int list;
  mutable failure : string option;
  mutable serial : int;
  mutable iids : int;
  read_op : bool array;
  mutable cver : int;
  cache : ex array;
  cache_at : int array;
  checks : rng;
}

type reader = { read : bool -> bool -> int -> int; untrack : (unit -> int) -> int }

let show = function
  | Val v -> string_of_int v
  | Err k -> "Boom " ^ string_of_int k
  | Unknown -> "unknown"
  | Stale -> "a recompute"

let show_exn = function
  | None -> "no exception"
  | Some (Boom k) -> "Boom " ^ string_of_int k
  | Some Abort -> "Abort"
  | Some e -> Printexc.to_string e

let fail t inv what expected observed =
  let m =
    Printf.sprintf "seed %d step %d invariant %s: %s: expected %s, observed %s" t.seed t.step inv
      what expected observed
  in
  (match t.failure with None -> t.failure <- Some m | Some _ -> ());
  raise (Cases.Failed m)

let who i =
  Printf.sprintf "effect e%d (%s)" i.iid (match i.spec.kind with Before -> "before" | After -> "after")

let pairs l = String.concat " " (List.map (fun (j, x) -> Printf.sprintf "n%d=%s" j (show x)) l)

let rec eval rd ~tracked id = function
  | Get j -> rd.read tracked false j
  | Peek j -> rd.read false true j
  | Untrack e -> rd.untrack (fun () -> eval rd ~tracked:false id e)
  | Sum l ->
      List.fold_left
        (fun acc e ->
          let v = eval rd ~tracked id e in
          (acc + v) mod 10)
        0 l
  | Min [] -> 0
  | Min (e :: l) ->
      let first = eval rd ~tracked id e in
      List.fold_left
        (fun acc e ->
          let v = eval rd ~tracked id e in
          min acc v)
        first l
  | Parity e -> eval rd ~tracked id e mod 2
  | If (c, a, b) ->
      if eval rd ~tracked id c mod 2 = 0 then eval rd ~tracked id a else eval rd ~tracked id b
  | Fail (k, e) ->
      let v = eval rd ~tracked id e in
      if v = k then raise (Boom id) else v

let rec expect t j =
  if t.cache_at.(j) = t.cver then t.cache.(j)
  else
    let n = t.nodes.(j) in
    let v =
      match n.expr with
      | None -> Val n.value
      | Some e when not n.loose -> (
          match eval (model t) ~tracked:false j e with v -> Val v | exception Boom k -> Err k)
      | Some _ ->
          if n.m_failed || n.computes = 0 then Unknown
          else
            let now = List.map (fun (k, v, _) -> (expect t k, v)) n.m_reads in
            if List.exists (fun (x, _) -> x = Unknown) now then Unknown
            else if List.for_all (fun (x, v) -> x = Val v) now then Val n.value
            else Stale
    in
    t.cache.(j) <- v;
    t.cache_at.(j) <- t.cver;
    v

and model t =
  {
    read =
      (fun _ _ j ->
        match expect t j with
        | Val v -> v
        | Err k -> raise (Boom k)
        | Unknown | Stale -> failwith "the model reads a loose node");
    untrack = (fun f -> f ());
  }

let enter t = t.depth <- t.depth + 1

let leave t e =
  t.depth <- t.depth - 1;
  match e with
  | Some (Boom k) when t.depth = 0 && not t.top -> t.escapes <- k :: t.escapes
  | _ -> ()

let spread_failure t =
  let changed = ref true in
  while !changed do
    changed := false;
    for j = 0 to t.count - 1 do
      let n = t.nodes.(j) in
      if
        n.expr <> None && (not n.m_failed)
        && List.exists (fun k -> t.nodes.(k).m_failed) n.m_links
      then begin
        n.m_failed <- true;
        changed := true
      end
    done
  done;
  t.cver <- t.cver + 1

let handle t j = match t.nodes.(j).handle with Some h -> h | None -> failwith "no handle"

let actual t who obs =
  {
    read =
      (fun tracked peek j ->
        let h = handle t j in
        let got =
          match if peek then State.peek h else State.get h with
          | v -> Val v
          | exception Boom k -> Err k
        in
        t.read_op.(j) <- true;
        if t.in_batch > 0 then t.pulled <- true;
        let want = expect t j in
        if want <> Unknown && want <> got then
          fail t "3 no glitch" (Printf.sprintf "%s reads n%d" who j) (show want) (show got);
        if tracked then obs := (j, got) :: !obs;
        match got with Val v -> v | Err k -> raise (Boom k) | Unknown | Stale -> assert false);
    untrack = State.untrack;
  }

let set_src t j v =
  let n = t.nodes.(j) in
  if v <> n.value then begin
    n.value <- v;
    n.ver <- n.ver + 1;
    t.cver <- t.cver + 1;
    if t.depth > 0 then t.exact <- false;
    if t.in_batch > 0 && t.pulled then t.exact <- false
  end;
  match n.writer with Some w -> State.set w v | None -> ()

let vals obs = List.filter_map (fun (j, x) -> match x with Val v -> Some (j, v) | _ -> None) obs

let compute t n e () =
  let who = Printf.sprintf "memo n%d" n.id in
  if not n.alive then fail t "6 disposal" who "no compute after its owner is disposed" "a compute";
  if
    t.exact && n.computes > 0 && (not n.m_failed)
    && List.for_all (fun (j, _, c) -> t.nodes.(j).ver = c) n.m_reads
  then
    fail t "4 no needless run" who "no compute (no input changed)"
      (Printf.sprintf "a compute with %s"
         (pairs (List.map (fun (j, v, _) -> (j, Val v)) n.m_reads)));
  if n.computes > 0 then n.computes_op <- n.computes_op + 1;
  n.computes <- n.computes + 1;
  enter t;
  let obs = ref [] in
  match eval (actual t who obs) ~tracked:true n.id e with
  | v ->
      leave t None;
      if n.computes > 1 && v <> n.value then n.ver <- n.ver + 1;
      n.value <- v;
      n.m_reads <- List.rev_map (fun (j, v) -> (j, v, t.nodes.(j).ver)) (vals !obs);
      n.m_links <- List.map fst !obs;
      n.m_failed <- false;
      t.cver <- t.cver + 1;
      v
  | exception ex ->
      leave t (if n.computes = 1 then Some ex else None);
      n.m_failed <- true;
      n.m_links <- List.map fst !obs @ n.m_links;
      spread_failure t;
      raise ex

let new_node t ~expr ~loose =
  let n =
    {
      id = t.count;
      expr;
      loose;
      alive = true;
      handle = None;
      writer = None;
      value = 0;
      ver = 0;
      ver0 = 0;
      computes = 0;
      computes_op = 0;
      m_reads = [];
      m_links = [];
      m_links0 = [];
      m_failed = false;
    }
  in
  t.nodes.(t.count) <- n;
  t.count <- t.count + 1;
  n

let rec loose_expr t = function
  | Get j -> t.nodes.(j).loose
  | Peek _ | Untrack _ -> true
  | Sum l | Min l -> List.exists (loose_expr t) l
  | Parity e | Fail (_, e) -> loose_expr t e
  | If (a, b, c) -> loose_expr t a || loose_expr t b || loose_expr t c

let new_memo t e =
  let n = new_node t ~expr:(Some e) ~loose:(loose_expr t e) in
  match State.memo (compute t n e) with
  | s ->
      n.handle <- Some s;
      n.id
  | exception ex ->
      n.alive <- false;
      raise ex

let rec kill t i =
  i.i_alive <- false;
  List.iter (kill t) i.children;
  if i.pending <> None then
    fail t "6 disposal" (who i) "its cleanup ran on dispose" "no cleanup"

let unchanged t reads = List.for_all (fun (j, v) -> expect t j = Val v) reads

let rec start t home spec =
  t.iids <- t.iids + 1;
  let i =
    {
      iid = t.iids;
      spec;
      created = t.step;
      i_alive = true;
      i_alive0 = false;
      attempts = 0;
      oks = 0;
      ok_reads = [];
      ok_vers = [];
      seen = [];
      seen0 = [];
      i_failed = false;
      pending = None;
      children = [];
      ran_op = -1;
    }
  in
  t.insts <- i :: t.insts;
  home i;
  let deferred = spec.kind = After && (t.depth > 0 || t.in_batch > 0) in
  let body = run t i in
  let cleanup r = on_cleanup t i r in
  match
    match (spec.kind, spec.cleanup) with
    | Before, true -> Effect.before ~cleanup body
    | Before, false -> Effect.before body
    | After, true -> Effect.after ~cleanup body
    | After, false -> Effect.after body
  with
  | () ->
      if deferred && i.attempts > 0 then
        fail t "5 order" (who i) "first run after the batch ends" "a first run inside it";
      if (not deferred) && i.attempts = 0 then
        fail t "5 order" (who i) "first run at once" "no run"
  | exception e ->
      if (not deferred) && i.i_failed then kill t i;
      raise e

and run t i () =
  let w = who i in
  if not i.i_alive then fail t "6 disposal" w "no run after its owner is disposed" "a run";
  if i.pending <> None then
    fail t "7 cleanup pairing" w "the cleanup of the previous run before this run" "no cleanup";
  let old = i.children in
  i.children <- [];
  List.iter
    (fun c ->
      if t.exact && c.ran_op = t.step && c.created < t.step && c.spec.kind = i.spec.kind then
        fail t "5 order" w
          (Printf.sprintf "parent runs before its child %s" (who c))
          "the child ran first in the same flush";
      kill t c)
    old;
  if
    i.attempts > 0 && t.exact && (not i.i_failed)
    && unchanged t i.ok_reads
    && (i.ran_op = t.step || List.for_all (fun (j, c) -> t.nodes.(j).ver0 = c) i.ok_vers)
  then
    fail t "4 no needless run" w "no run (no value it read changed)"
      (Printf.sprintf "a run with %s" (pairs (List.map (fun (j, v) -> (j, Val v)) i.ok_reads)));
  if i.attempts > 0 && t.exact && (not i.i_failed) && i.spec.kind = Before && t.after_ran then
    fail t "5 order" w "before runs ahead of the after runs of the same change"
      "a before run after an after run";
  if i.spec.kind = After then t.after_ran <- true;
  i.attempts <- i.attempts + 1;
  i.ran_op <- t.step;
  enter t;
  let obs = ref [] in
  match
    let v = eval (actual t w obs) ~tracked:true (1000 + i.iid) i.spec.body in
    List.iter (fun k -> start t (fun c -> i.children <- c :: i.children) k) i.spec.kids;
    (match i.spec.writes with Some s -> set_src t s (v mod 4) | None -> ());
    v
  with
  | _ ->
      leave t None;
      i.ok_reads <- List.rev (vals !obs);
      i.ok_vers <- List.map (fun (j, _) -> (j, t.nodes.(j).ver)) i.ok_reads;
      i.seen <- List.rev !obs;
      i.i_failed <- false;
      i.oks <- i.oks + 1;
      t.serial <- t.serial + 1;
      if i.spec.cleanup then i.pending <- Some t.serial;
      t.serial
  | exception e ->
      leave t (Some e);
      let fresh = List.rev !obs in
      i.seen <-
        fresh
        @ List.filter_map
            (fun (j, _) -> if List.mem_assoc j fresh then None else Some (j, expect t j))
            i.seen;
      i.i_failed <- true;
      raise e

and on_cleanup t i r =
  match i.pending with
  | Some p when p = r -> i.pending <- None
  | Some p ->
      fail t "7 cleanup pairing" (who i ^ " cleanup argument") (string_of_int p) (string_of_int r)
  | None ->
      fail t "7 cleanup pairing" (who i) "no cleanup without a pending run"
        (Printf.sprintf "cleanup %d" r)

let rec tight_spec t s =
  (not (loose_expr t s.body))
  && List.for_all (fun k -> k.kind = After || tight_spec t k) s.kids

let rec model_spec t s =
  ignore (eval (model t) ~tracked:false 0 s.body);
  List.iter (fun k -> if k.kind = Before then model_spec t k) s.kids

let would_succeed t s =
  tight_spec t s && match model_spec t s with () -> true | exception Boom _ -> false

let check_effect t i =
  let w = who i in
  if i.attempts = 0 then fail t "2 no missed run" w "a first run" "no run"
  else
    let now l = List.map (fun (j, _) -> (j, expect t j)) l in
    let ok_now = now i.ok_reads and seen_now = now i.seen in
    let known l = List.for_all (fun (_, x) -> x <> Unknown) l in
    let raising l = List.exists (fun (_, x) -> match x with Err _ -> true | _ -> false) l in
    if known ok_now && known seen_now then
      if i.oks > 0 && unchanged t i.ok_reads then ()
      else if not i.i_failed then begin
        if not (raising ok_now) then
          fail t "2 no missed run" w (pairs ok_now)
            ("its last run read " ^ pairs (List.map (fun (j, v) -> (j, Val v)) i.ok_reads))
      end
      else if
        List.exists2 (fun (_, x) (_, y) -> x <> y) i.seen seen_now
        && (not (raising seen_now))
        && would_succeed t i.spec
      then
        fail t "8 recovery" w
          (Printf.sprintf "a new run, now that %s" (pairs seen_now))
          (Printf.sprintf "no run since its failed run read %s" (pairs i.seen))

let top_read t j =
  let n = t.nodes.(j) in
  let h = handle t j in
  let wanted () = if n.alive then expect t j else Val n.value in
  let read () =
    t.top <- true;
    match State.peek h with
    | v ->
        t.top <- false;
        Val v
    | exception Boom k ->
        t.top <- false;
        Err k
    | exception e ->
        t.top <- false;
        raise e
  in
  let first = read () in
  let got = match (first, wanted ()) with Err _, Val _ -> read () | _ -> first in
  t.read_op.(j) <- true;
  if t.in_batch > 0 then t.pulled <- true;
  let want = wanted () in
  if want <> Unknown && want <> got then
    fail t "1 no stale value" (Printf.sprintf "peek n%d" j) (show want) (show got)

let live_memos t =
  let rec go j acc =
    if j < t.nsrc then acc
    else
      let n = t.nodes.(j) in
      go (j - 1) (if n.alive && n.expr <> None then j :: acc else acc)
  in
  go (t.count - 1) []

let read_pick t k =
  match live_memos t with [] -> () | l -> top_read t (List.nth l (k mod List.length l))

let kill_group t gr =
  gr.g_alive <- false;
  List.iter (fun j -> t.nodes.(j).alive <- false) gr.g_memos;
  List.iter (kill t) gr.g_insts

let create t gs =
  let local = Array.make (List.length gs.memos) (-1) in
  let res j = if j < t.nbase then j else local.(j - t.nbase) in
  let gr = { g_memos = []; g_insts = []; g_dispose = ignore; g_alive = true } in
  let build () =
    List.iteri
      (fun k e ->
        let id = t.count in
        gr.g_memos <- id :: gr.g_memos;
        local.(k) <- new_memo t (map_expr res e))
      gs.memos;
    List.iter (fun s -> start t (fun i -> gr.g_insts <- i :: gr.g_insts) (map_spec res s)) gs.effects
  in
  match owner build with
  | (), d ->
      gr.g_dispose <- d;
      gr
  | exception e ->
      kill_group t gr;
      raise e

let check_failure t = match t.failure with Some m -> raise (Cases.Failed m) | None -> ()

let check_exn t body got =
  check_failure t;
  let want =
    match body with
    | Some e -> Some e
    | None -> ( match List.rev t.escapes with k :: _ -> Some (Boom k) | [] -> None)
  in
  if show_exn want <> show_exn got then
    fail t "8 exceptions" "the exception of the operation" (show_exn want) (show_exn got)

let attempt f = match f () with () -> None | exception ((Boom _ | Abort) as e) -> Some e

let in_batch t body =
  let body_exn = ref None in
  let got =
    attempt (fun () ->
        batch (fun () ->
            t.in_batch <- t.in_batch + 1;
            match body () with
            | () -> t.in_batch <- t.in_batch - 1
            | exception e ->
                t.in_batch <- t.in_batch - 1;
                body_exn := Some e;
                raise e))
  in
  check_exn t !body_exn got

let rec items_run t =
  List.iter (function
    | W (s, v) -> set_src t s v
    | R k -> read_pick t k
    | Nest l -> batch (fun () -> items_run t l)
    | Nest_raise l -> (
        try
          batch (fun () ->
              items_run t l;
              raise Abort)
        with Abort -> ()))

let add_group t gr = if gr.g_alive then t.groups <- gr :: t.groups

let exec t = function
  | Set (s, v) -> check_exn t None (attempt (fun () -> set_src t s v))
  | Batch (items, abort) ->
      in_batch t (fun () ->
          items_run t items;
          if abort then raise Abort)
  | Read k -> read_pick t k
  | Create gs -> (
      match gs.mode with
      | 0 -> check_exn t None (attempt (fun () -> add_group t (create t gs)))
      | 1 -> in_batch t (fun () -> add_group t (create t gs))
      | _ ->
          in_batch t (fun () ->
              let gr = create t gs in
              gr.g_dispose ();
              kill_group t gr))
  | Dispose k -> (
      match List.filter (fun gr -> gr.g_alive) t.groups with
      | [] -> ()
      | l ->
          let gr = List.nth l (k mod List.length l) in
          check_exn t None (attempt (fun () -> gr.g_dispose ()));
          kill_group t gr)

let begin_op t =
  t.step <- t.step + 1;
  t.exact <- true;
  t.after_ran <- false;
  t.pulled <- false;
  t.escapes <- [];
  Array.fill t.read_op 0 (Array.length t.read_op) false;
  for j = 0 to t.count - 1 do
    let n = t.nodes.(j) in
    n.computes_op <- 0;
    n.ver0 <- n.ver;
    n.m_links0 <- n.m_links
  done;
  List.iter
    (fun i ->
      i.i_alive0 <- i.i_alive;
      i.seen0 <- List.map fst i.seen)
    t.insts

let laziness t =
  let pulled = Array.make t.count false in
  let rec mark j =
    if not pulled.(j) then begin
      pulled.(j) <- true;
      let n = t.nodes.(j) in
      List.iter mark n.m_links0;
      List.iter mark n.m_links
    end
  in
  for j = 0 to t.count - 1 do
    if t.read_op.(j) then mark j
  done;
  List.iter
    (fun i ->
      if i.i_alive0 || i.i_alive then begin
        List.iter mark i.seen0;
        List.iter (fun (j, _) -> mark j) i.seen
      end)
    t.insts;
  for j = 0 to t.count - 1 do
    if t.nodes.(j).computes_op > 0 && not pulled.(j) then
      fail t "4 no needless run" (Printf.sprintf "memo n%d" j) "no compute without a reader"
        "a compute"
  done

let finish_op t =
  check_failure t;
  List.iter (fun i -> if i.i_alive then check_effect t i) t.insts;
  laziness t;
  for j = t.nsrc to t.count - 1 do
    let n = t.nodes.(j) in
    if n.expr <> None && n.handle <> None && chance t.checks (if n.alive then 30 else 10) then
      top_read t j
  done;
  check_failure t

let dummy =
  {
    id = -1;
    expr = None;
    loose = false;
    alive = false;
    handle = None;
    writer = None;
    value = 0;
    ver = 0;
    ver0 = 0;
    computes = 0;
    computes_op = 0;
    m_reads = [];
    m_links = [];
    m_links0 = [];
    m_failed = false;
  }

let make_t seed graph =
  let nsrc = List.length graph.sources + graph.sinks in
  let size = 512 in
  {
    seed;
    nbase = nsrc + List.length graph.base_memos;
    nsrc;
    nodes = Array.make size dummy;
    count = 0;
    insts = [];
    roots = [];
    groups = [];
    step = 0;
    exact = true;
    depth = 0;
    top = false;
    in_batch = 0;
    pulled = false;
    after_ran = false;
    escapes = [];
    failure = None;
    serial = 0;
    iids = 0;
    read_op = Array.make size false;
    cver = 0;
    cache = Array.make size Unknown;
    cache_at = Array.make size (-1);
    checks = rng (seed + 1);
  }

let ops_run = ref 0
let seeds_run = ref 0

let execute seed graph ops =
  incr seeds_run;
  let t = make_t seed graph in
  List.iter
    (fun v ->
      let n = new_node t ~expr:None ~loose:false in
      n.value <- v;
      n.writer <- Some (State.make v);
      n.handle <- Option.map State.read_only n.writer)
    (graph.sources @ List.init graph.sinks (fun _ -> 0));
  begin_op t;
  let root = ref ignore in
  let started =
    attempt (fun () ->
        let (), d =
          owner (fun () ->
              List.iter (fun e -> ignore (new_memo t e)) graph.base_memos;
              List.iter (fun s -> start t (fun i -> t.roots <- i :: t.roots) s) graph.base_effects)
        in
        root := d)
  in
  check_exn t None started;
  match started with
  | Some _ ->
      List.iter (kill t) t.roots;
      check_failure t
  | None ->
      finish_op t;
      List.iter
        (fun op ->
          incr ops_run;
          begin_op t;
          exec t op;
          finish_op t)
        ops;
      begin_op t;
      List.iter
        (fun gr ->
          if gr.g_alive then begin
            gr.g_dispose ();
            kill_group t gr
          end)
        t.groups;
      !root ();
      List.iter (kill t) t.roots;
      for j = t.nsrc to t.count - 1 do
        t.nodes.(j).alive <- false
      done;
      for s = 0 to t.nsrc - 1 do
        ignore (attempt (fun () -> set_src t s ((t.nodes.(s).value + 1) mod 4)))
      done;
      check_failure t

let generate f seed =
  let g = rng seed in
  let graph = gen_graph g f in
  let ops = gen_ops g f graph in
  (graph, ops)

let run_seed f seed =
  let graph, ops = generate f seed in
  execute seed graph ops

let dynamic = { static with dynamic = true }
let untracked = { static with untracked = true }
let after = { static with after = true }
let nested = { after with nested = true }
let cleanup = { nested with cleanup = true }
let groups = { cleanup with groups = true }
let batches = { after with batches = true }
let writers = { batches with writers = true }
let raises = { cleanup with raises = true; batches = true }

let every =
  {
    dynamic = true;
    untracked = true;
    after = true;
    nested = true;
    cleanup = true;
    groups = true;
    batches = true;
    writers = true;
    raises = true;
  }

let seeds f ~upto () =
  for seed = 1 to upto do
    run_seed f seed
  done

let only f l () = List.iter (run_seed f) l

let prng () =
  let g = rng 1 in
  let got = list 5 (fun () -> string_of_int (next g)) in
  Cases.check "the sequence of seed 1" "40041 27028 25609 64896 27989" (String.concat " " got)

let joined l = String.concat " " (List.rev l)

let needless_rerun () =
  let a = State.make 0 in
  let b = State.memo (fun () -> State.get a) in
  let c =
    State.memo (fun () ->
        let x = State.get a in
        x + State.get b)
  in
  let runs = ref 0 in
  Effect.before (fun () ->
      incr runs;
      let x = State.get a in
      let y = State.get c in
      ignore (x + y + State.get b));
  State.set a 1;
  Cases.check "one run for one write" "2" (string_of_int !runs)

let missed_run () =
  let a = State.make 0 in
  let j = State.memo (fun () -> State.get a) in
  let y =
    State.memo (fun () ->
        let x = State.get a in
        x + State.get j)
  in
  let x =
    State.memo (fun () ->
        let s = State.get a in
        let s = s + State.get y in
        let s = s + State.get j in
        if s = 4 then 0 else s)
  in
  let seen = ref [] in
  Effect.before (fun () -> seen := string_of_int (State.get x) :: !seen);
  State.set a 1;
  State.set a 2;
  Cases.check "the effect sees x = 8" "0 8" (joined !seen)

let child_before_parent () =
  let a = State.make 0 in
  let log = ref [] in
  Effect.before (fun () ->
      Effect.before (fun () ->
          log := ("P" ^ string_of_int (State.get a)) :: !log;
          Effect.before (fun () -> log := ("C" ^ string_of_int (State.get a)) :: !log)));
  State.set a 1;
  State.set a 2;
  Cases.check "parent effects first" "P0 C0 P1 C1 P2 C2" (joined !log)

let no_rerun_after_recovery () =
  let a = State.make 0 and b = State.make 0 in
  let m = State.memo (fun () -> if State.get a = 1 then raise (Boom 1) else 0) in
  let seen = ref [] in
  Effect.before (fun () ->
      let x = State.get b in
      let y = State.get m in
      seen := Printf.sprintf "%d/%d" x y :: !seen);
  (try State.set a 1 with Boom _ -> ());
  (try State.set b 5 with Boom _ -> ());
  State.set a 0;
  Cases.check "the effect sees b = 5 once m recovers" "0/0 5/0" (joined !seen)

let raising_read_untracked () =
  let a = State.make 0 in
  let m = State.memo (fun () -> let v = State.get a in if v = 1 then raise (Boom 1) else v) in
  State.set a 1;
  let seen = ref [] in
  (try batch (fun () -> Effect.after (fun () -> seen := string_of_int (State.get m) :: !seen))
   with Boom _ -> ());
  State.set a 2;
  Cases.check "the effect runs once m recovers" "2" (joined !seen)

let before_after_after () =
  let a = State.make 0 and b = State.make 0 in
  let r = State.memo (fun () -> if State.get a = 1 then raise (Boom 1) else 0) in
  let c = State.memo (fun () -> State.get b) in
  let log = ref [] in
  Effect.after (fun () -> log := ("after" ^ string_of_int (State.get c)) :: !log);
  Effect.before (fun () ->
      log := "before" :: !log;
      let x = State.get r in
      ignore (x + State.get c));
  (try State.set a 1 with Boom _ -> ());
  log := [];
  (try State.set b 1 with Boom _ -> ());
  Cases.check "no before run after the after run of the same change" "true"
    (string_of_bool (match !log with "before" :: _ :: _ -> false | _ -> true))

let pending_after_peek () =
  let a = State.make 0 and t = State.make 0 in
  let m =
    State.memo (fun () ->
        let x = State.get t in
        if State.peek a = 1 then raise (Boom 1) else x)
  in
  let seen = ref [] in
  Effect.before (fun () -> seen := string_of_int (State.get m) :: !seen);
  State.set a 1;
  (try State.set t 1 with Boom _ -> ());
  State.set a 0;
  ignore (State.peek m);
  Cases.check "the effect sees m = 1" "0 1" (joined !seen)

let all =
  [
    ("fuzz: prng", prng);
    ("fuzz: static", seeds static ~upto:200);
    ("fuzz: dynamic", seeds dynamic ~upto:200);
    ("fuzz: untracked", seeds untracked ~upto:200);
    ("fuzz: after", seeds after ~upto:200);
    ("fuzz: nested", seeds nested ~upto:60);
    ("fuzz: cleanup", seeds cleanup ~upto:60);
    ("fuzz: groups", seeds groups ~upto:60);
    ("fuzz: batches", seeds batches ~upto:150);
    ("fuzz: writers", seeds writers ~upto:150);
    ("fuzz: raises", seeds raises ~upto:60);
    ("fuzz: every feature", seeds every ~upto:100);
    ("fuzz: needless re-run in one flush", needless_rerun);
    ("fuzz: missed run behind a dirty memo", missed_run);
    ("fuzz: child before parent", child_before_parent);
    ("fuzz: no re-run after recovery", no_rerun_after_recovery);
    ("fuzz: raising read is not tracked", raising_read_untracked);
    ("fuzz: before run after an after run", before_after_after);
    ("fuzz: pending effect after a top-level read", pending_after_peek);
    ("fuzz: seeds with a needless re-run", only static [ 3; 21; 89 ]);
    ("fuzz: seeds with a child before its parent", only nested [ 9; 16; 19 ]);
    ("fuzz: seeds with no re-run after recovery", only raises [ 99; 108; 202 ]);
    ("fuzz: seed with a pending effect after a read", only every [ 744 ]);
  ]
