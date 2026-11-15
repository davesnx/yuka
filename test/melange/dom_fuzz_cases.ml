open Yuka

exception Boom of int
exception Replay

type node = Dom_cases.node

external is_connected : node -> bool = "isConnected" [@@mel.get]
external remove_node : node -> unit = "remove" [@@mel.send]
external get_tag : node -> string -> int Js.undefined = "" [@@mel.get_index]
external set_tag : node -> string -> int -> unit = "" [@@mel.set_index]

let html = Dom_cases.html
let query_all = Dom_cases.query_all
let attr_of n a = Option.value (Dom_cases.get_attribute n a) ~default:""

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

type expr = St of int | Memo of int
type kind = Before | After

type eff = { kind : kind; reads : expr list; cleanup : bool; snap : bool; raise_on : int option }

type tree =
  | El of string * attr list * tree list
  | Txt of string
  | Show of int * expr
  | Switch of int * int * tree list * tree list
  | Comp of int * eff list * int option * tree list
  | Each of int * int * int * tree list
  | Guard of int * tree list
  | Bomb of int * int
  | Button of int * int
  | Key
  | Val
  | Provide of int * int * tree list
  | Ctx of int

and attr = Fixed of string * string | Dyn of string * expr

type features = {
  switch : bool;
  lists : bool;
  nested : bool;
  memos : bool;
  effects : bool;
  catch : bool;
  events : bool;
  batches : bool;
  stop : bool;
  hydrate : bool;
  row_raise : bool;
  context : bool;
}

let base =
  {
    switch = false;
    lists = false;
    nested = false;
    memos = false;
    effects = false;
    catch = false;
    events = false;
    batches = false;
    stop = false;
    hydrate = false;
    row_raise = false;
    context = false;
  }

type spec = {
  n_ints : int;
  n_lists : int;
  memos : (int * int) array;
  tree : tree list;
  ctx : (int, int list * bool) Hashtbl.t;
  sources : (int, int) Hashtbl.t;
  buttons : (int, int) Hashtbl.t;
}

let show_expr = function St i -> Printf.sprintf "s%d" i | Memo i -> Printf.sprintf "m%d" i

let rec show_tree = function
  | El (tag, attrs, kids) ->
      Printf.sprintf "%s[%s](%s)" tag
        (String.concat ","
           (List.map
              (function
                | Fixed (n, v) -> n ^ "=" ^ v | Dyn (n, e) -> n ^ "~" ^ show_expr e)
              attrs))
        (show_trees kids)
  | Txt s -> Printf.sprintf "%S" s
  | Show (k, e) -> Printf.sprintf "show%d(%s)" k (show_expr e)
  | Switch (id, s, a, b) -> Printf.sprintf "switch%d(s%d|%s|%s)" id s (show_trees a) (show_trees b)
  | Comp (id, effs, raises, kids) ->
      Printf.sprintf "comp%d{%s}%s(%s)" id
        (String.concat ","
           (List.map
              (fun e ->
                Printf.sprintf "%s %s%s%s%s"
                  (match e.kind with Before -> "before" | After -> "after")
                  (String.concat "+" (List.map show_expr e.reads))
                  (if e.cleanup then " cleanup" else "")
                  (if e.snap then " snap" else "")
                  (match e.raise_on with Some k -> Printf.sprintf " raise%d" k | None -> ""))
              effs))
        (match raises with
        | Some -1 -> " raises"
        | Some k -> Printf.sprintf " raises when val=%d" k
        | None -> "")
        (show_trees kids)
  | Each (id, src, shape, kids) ->
      Printf.sprintf "each%d(l%d %s|%s)" id src [| "element"; "element+text"; "bare" |].(shape) (show_trees kids)
  | Guard (id, kids) -> Printf.sprintf "catch%d(%s)" id (show_trees kids)
  | Bomb (s, k) -> Printf.sprintf "bomb(s%d=%d)" s k
  | Button (id, s) -> Printf.sprintf "button%d(s%d)" id s
  | Key -> "key"
  | Val -> "val"
  | Provide (c, v, kids) -> Printf.sprintf "provide c%d=%d(%s)" c v (show_trees kids)
  | Ctx s -> Printf.sprintf "ctx(s%d)" s

and show_trees l = String.concat " " (List.map show_tree l)

let tags = [| "div"; "span"; "em"; "ul"; "b" |]
let words = [| "a"; "bc"; ""; "d e" |]

let gen_spec g f =
  let n_ints = 2 + int g 3 in
  let n_lists = if f.lists then 1 + int g 2 else 0 in
  let memos =
    if f.memos then Array.init (1 + int g 2) (fun _ -> (int g n_ints, int g n_ints)) else [||]
  in
  let ctx = Hashtbl.create 8 and sources = Hashtbl.create 8 and buttons = Hashtbl.create 8 in
  let ids = ref 0 in
  let fresh () =
    incr ids;
    !ids
  in
  let button () =
    let id = fresh () and s = int g n_ints in
    Hashtbl.replace buttons id s;
    Button (id, s)
  in
  let expr () =
    if Array.length memos > 0 && chance g 35 then Memo (int g (Array.length memos))
    else St (int g n_ints)
  in
  let budget = ref (12 + int g 24) in
  let rec node ~depth ~holes ~guarded ~safe ~in_row ~lists =
    decr budget;
    let leaf () =
      if f.context && chance g 35 then Ctx (int g n_ints)
      else
        match int g 6 with
        | 0 -> Txt words.(int g (Array.length words))
        | 1 when in_row -> if chance g 50 then Key else Val
        | 2 when guarded && f.catch -> Bomb (int g n_ints, int g 4)
        | 3 when f.events -> button ()
        | _ -> Show (int g 4, expr ())
    in
    let kids ?(holes = holes) ?(guarded = guarded) ?(safe = safe) ?(in_row = in_row) ?(lists = lists) () =
      list (int g 4) (fun () -> node ~depth:(depth + 1) ~holes ~guarded ~safe ~in_row ~lists)
    in
    if depth > 4 || !budget <= 0 then leaf ()
    else if f.context && chance g 25 then
      let c = int g 2 in
      let v = int g 6 in
      Provide (c, v, kids ())
    else
      match int g 12 with
      | 0 | 1 | 2 ->
          let attrs =
            list (int g 3) (fun () ->
                let name = [| "class"; "title"; "data-x" |].(int g 3) in
                if chance g 50 then Fixed (name, words.(int g 4)) else Dyn (name, expr ()))
          in
          let rec dedup seen = function
            | [] -> []
            | a :: rest ->
                let n = match a with Fixed (n, _) | Dyn (n, _) -> n in
                if List.mem n seen then dedup seen rest else a :: dedup (n :: seen) rest
          in
          El (tags.(int g (Array.length tags)), dedup [] attrs, kids ())
      | 3 when f.switch ->
          let s = int g n_ints in
          let id = fresh () in
          Switch (id, s, kids ~holes:(s :: holes) (), kids ~holes:(s :: holes) ())
      | 4 | 5 when f.lists && lists < if f.nested then 2 else 1 ->
          let id = fresh () and src = int g n_lists in
          Hashtbl.replace ctx id (holes, guarded);
          Hashtbl.replace sources id src;
          Each (id, src, (if chance g 60 then 0 else 1 + int g 2), kids ~in_row:true ~safe:false ~lists:(lists + 1) ())
      | 6 | 7 when f.effects ->
          let effs =
            list (1 + int g 2) (fun () ->
                {
                  kind = (if chance g 50 then Before else After);
                  reads = list (1 + int g 2) expr;
                  cleanup = chance g 50;
                  snap = chance g 50;
                  raise_on = (if f.catch && guarded && chance g 25 then Some (int g 4) else None);
                })
          in
          let raises =
            if f.catch && guarded && chance g 30 then
              if in_row && (safe || f.row_raise) then Some (int g 3) else if chance g 30 then Some (-1) else None
            else None
          in
          Comp (fresh (), effs, raises, kids ())
      | 8 when f.catch -> Guard (fresh (), kids ~guarded:true ~safe:true ())
      | 9 when f.events -> button ()
      | _ -> leaf ()
  in
  let tree =
    list (1 + int g 3) (fun () -> node ~depth:0 ~holes:[] ~guarded:false ~safe:false ~in_row:false ~lists:0)
  in
  { n_ints; n_lists; memos; tree; ctx; sources; buttons }

type inst = {
  ipath : string;
  effs : eff array;
  runs : int array;
  ok_runs : int array;
  last_ok : bool array;
  cleanups : int array;
  seen : int list array;
  mutable stopped : bool;
  mutable frozen : int array option;
}

type mode = Live | Shadow | Server

type world = {
  seed : int;
  feats : features;
  spec : spec;
  ints : int State.t array;
  lists : (int * int) array State.t array;
  touched : bool array;
  latest : (string, inst) Hashtbl.t;
  mutable insts : inst list;
  mutable shadow_insts : inst list;
  caught : (string, string) Hashtbl.t;
  mutable guard_events : int;
  mutable client_catches : int;
  mutable after_snaps : (node * string) list;
  mutable violations : string list;
  mutable ctx_fails : (string * string * string) list;
  mutable step : int;
  mutable ops : string list;
  live : node;
  mutable dispose : unit -> unit;
  mutable next_tag : int;
}

type env = {
  w : world;
  mode : mode;
  root : node;
  memos : int State.read array;
  path : string;
  row : (int * int) option;
  given : int option array;
}

type stats = {
  mutable kept : int;
  mutable removed : int;
  mutable alive : int;
  mutable dead : int;
  mutable after_seen : int;
  mutable catches : int;
  mutable resets : int;
  mutable clicks : int;
  mutable stops : int;
}

let stats = { kept = 0; removed = 0; alive = 0; dead = 0; after_seen = 0; catches = 0; resets = 0; clicks = 0; stops = 0 }

let fail w check what expected observed =
  raise
    (Cases.Failed
       (Printf.sprintf "seed %d step %d check %s: %s: expected %s, observed %s\ntree: %s\nops: %s"
          w.seed w.step check what expected observed (show_trees w.spec.tree)
          (String.concat "; " (List.rev w.ops))))

let contexts : int Context.t array = [| Context.make ~name:"c0" (); Context.make ~name:"c1" () |]
let ctx_now () = Array.map Context.get contexts

let show_ctx a =
  String.concat "," (Array.to_list (Array.map (function None -> "-" | Some v -> string_of_int v) a))

let read_ctx env place =
  let seen = ctx_now () in
  if seen <> env.given then
    env.w.ctx_fails <-
      ( Printf.sprintf "%s at %s (%s)" place (if env.path = "" then "/" else env.path)
          (match env.mode with Live -> "live" | Shadow -> "fresh render" | Server -> "server"),
        show_ctx env.given,
        show_ctx seen )
      :: env.w.ctx_fails;
  seen

let memo_fn a b = (a * 3) + b
let eval env = function St i -> State.get env.w.ints.(i) | Memo i -> State.get env.memos.(i)

let model w = function
  | St i -> State.peek w.ints.(i)
  | Memo i ->
      let a, b = w.spec.memos.(i) in
      memo_fn (State.peek w.ints.(a)) (State.peek w.ints.(b))

let touched w = function
  | St i -> w.touched.(i)
  | Memo i ->
      let a, b = w.spec.memos.(i) in
      w.touched.(a) || w.touched.(b)

let write_int w i v =
  if v <> State.peek w.ints.(i) then w.touched.(i) <- true;
  State.set w.ints.(i) v

let show_text k v =
  let s = string_of_int v in
  match k with
  | 0 -> text s
  | 1 -> if v mod 2 = 0 then text "" else text s
  | 2 -> if v mod 2 = 1 then fragment [ text s; text "." ] else text s
  | _ -> if v mod 2 = 0 then element "span" [] [ text s ] else text s

let new_inst env path effs =
  let effs = Array.of_list effs in
  let n = Array.length effs in
  let i =
    {
      ipath = path;
      effs;
      runs = Array.make n 0;
      ok_runs = Array.make n 0;
      last_ok = Array.make n false;
      cleanups = Array.make n 0;
      seen = Array.make n [];
      stopped = false;
      frozen = None;
    }
  in
  (match env.mode with
  | Live ->
      env.w.insts <- i :: env.w.insts;
      Hashtbl.replace env.w.latest path i
  | Shadow -> env.w.shadow_insts <- i :: env.w.shadow_insts
  | Server -> ());
  i

let start_effect env inst k e =
  let w = env.w in
  let body () =
    ignore (read_ctx env (Printf.sprintf "effect %d of %s" k inst.ipath));
    let vals = List.map (eval env) e.reads in
    inst.runs.(k) <- inst.runs.(k) + 1;
    inst.last_ok.(k) <- false;
    inst.seen.(k) <- vals;
    if e.snap && e.kind = After then w.after_snaps <- (env.root, html env.root) :: w.after_snaps;
    (match e.raise_on with
    | Some r when List.hd vals mod 4 = r -> raise (Boom r)
    | _ -> ());
    inst.ok_runs.(k) <- inst.ok_runs.(k) + 1;
    inst.last_ok.(k) <- true;
    inst.ok_runs.(k)
  in
  let cleanup r =
    inst.cleanups.(k) <- inst.cleanups.(k) + 1;
    if r <> inst.cleanups.(k) then
      w.violations <-
        Printf.sprintf "cleanup %d of effect %d of %s got the result %d" inst.cleanups.(k) k
          inst.ipath r
        :: w.violations
  in
  match (e.kind, e.cleanup) with
  | Before, true -> Effect.before ~cleanup body
  | Before, false -> Effect.before (fun () -> ignore (body ()))
  | After, true -> Effect.after ~cleanup body
  | After, false -> Effect.after (fun () -> ignore (body ()))

let rec build env t : client element =
  let w = env.w in
  match t with
  | El (tag, attrs, kids) ->
      element tag
        (List.map
           (function
             | Fixed (n, v) -> attr n v
             | Dyn (n, e) ->
                 hole_attr n (fun () ->
                     let v = eval env e in
                     if v mod 3 = 0 then None else Some (string_of_int v)))
           attrs)
        (List.map (build env) kids)
  | Txt s -> text s
  | Show (k, e) -> hole (fun () -> show_text k (eval env e))
  | Switch (id, s, a, b) ->
      hole (fun () ->
          let v = State.get w.ints.(s) in
          let side = if v mod 2 = 0 then "a" else "b" in
          let env = { env with path = Printf.sprintf "%s/s%d%s" env.path id side } in
          ignore (read_ctx env "switch side");
          fragment (List.map (build env) (if v mod 2 = 0 then a else b)))
  | Comp (id, effs, raises, kids) ->
      let path = Printf.sprintf "%s/c%d" env.path id in
      let inst = new_inst env path effs in
      List.iteri (start_effect env inst) effs;
      (match (raises, env.row) with
      | Some -1, _ -> raise (Boom (-1))
      | Some k, Some (_, v) when v = k -> raise (Boom k)
      | _ -> ());
      element "section" [ attr "data-c" path ] (List.map (build { env with path }) kids)
  | Each (id, src, shape, kids) ->
      each ~equal:( = )
        ~key:(fun (k, _) -> string_of_int k)
        (fun () -> State.get w.lists.(src))
        (fun (k, v) ->
          let path = Printf.sprintf "%s/l%d:%d" env.path id k in
          let env = { env with path; row = Some (k, v) } in
          ignore (read_ctx env "row");
          let li () = element "article" [ attr "data-row" path ] (List.map (build env) kids) in
          match shape with
          | 0 -> li ()
          | 1 -> fragment [ li (); text "~" ]
          | _ -> fragment (List.map (build env) kids))
  | Guard (id, kids) ->
      let path = Printf.sprintf "%s/g%d" env.path id in
      let replay = env.mode = Shadow && Hashtbl.mem w.caught path in
      Catch.make
        ~fallback:(fun ~error ~reset ->
          let error = if replay then Hashtbl.find w.caught path else error in
          ignore (read_ctx { env with path } "catch fallback");
          if env.mode = Live then begin
            Hashtbl.replace w.caught path error;
            w.guard_events <- w.guard_events + 1;
            stats.catches <- stats.catches + 1;
            if error <> "server error" then w.client_catches <- w.client_catches + 1
          end;
          element "p" [ attr "data-fallback" path; on "click" (fun _ -> reset ()) ] [ text ("caught " ^ error) ])
        ~children:(fun () ->
          if replay then raise Replay;
          ignore (read_ctx { env with path } "catch children");
          if env.mode = Live then begin
            Hashtbl.remove w.caught path;
            w.guard_events <- w.guard_events + 1
          end;
          fragment (List.map (build { env with path }) kids))
        ()
  | Bomb (s, k) ->
      hole (fun () ->
          let v = State.get w.ints.(s) in
          if v mod 4 = k then raise (Boom k) else text ("b" ^ string_of_int v))
  | Button (id, s) ->
      element "button"
        [ attr "data-b" (Printf.sprintf "%s/b%d" env.path id);
          on "click" (fun _ ->
              ignore (read_ctx env (Printf.sprintf "click handler of b%d" id));
              write_int w s (State.peek w.ints.(s) + 1)) ]
        [ text "+" ]
  | Key -> text (match env.row with Some (k, _) -> "k" ^ string_of_int k | None -> "?")
  | Val -> text (match env.row with Some (_, v) -> "v" ^ string_of_int v | None -> "?")
  | Provide (c, v, kids) ->
      let given = Array.copy env.given in
      given.(c) <- Some v;
      let env = { env with given } in
      Context.provide contexts.(c) v (fun () -> fragment (List.map (build env) kids))
  | Ctx s ->
      let seen = read_ctx env "component function" in
      hole (fun () ->
          let v = State.get w.ints.(s) in
          let now = read_ctx env "hole" in
          text (Printf.sprintf "r%s/%s:%d" (show_ctx seen) (show_ctx now) v))

let root env =
  let w = env.w in
  let memos =
    Array.map
      (fun (a, b) -> State.memo (fun () -> memo_fn (State.get w.ints.(a)) (State.get w.ints.(b))))
      w.spec.memos
  in
  element "main" [] (List.map (build { env with memos }) w.spec.tree)

let env w mode root = { w; mode; root; memos = [||]; path = ""; row = None; given = [| None; None |] }

let canonical : node -> string =
  [%mel.raw
    {|function (root) {
  function esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }
  function go(n) {
    if (n.nodeType === 3) return esc(n.data);
    if (n.nodeType === 8) return "<!--" + (n.data === "[!" ? "[" : n.data) + "-->";
    var attrs = Array.from(n.attributes).map(function (a) { return " " + a.name + "=\"" + esc(a.value).replace(/"/g, "&quot;") + "\""; }).sort().join("");
    return "<" + n.localName + attrs + ">" + Array.from(n.childNodes).map(go).join("") + "</" + n.localName + ">";
  }
  return Array.from(root.childNodes).map(go).join("");
}|}]

let restore_log () =
  Server.Testing.set_log (fun level message ->
      let name = match level with `Error -> "error" | `Warn -> "warn" | `Info -> "info" | `Debug -> "debug" in
      if level <> `Debug then prerr_endline ("yuka: " ^ name ^ " " ^ message))

let check_context w =
  (match List.rev w.ctx_fails with (place, want, seen) :: _ -> fail w "7 context" place want seen | [] -> ());
  let outside = ctx_now () in
  if outside <> [| None; None |] then fail w "7 context" "Context.get outside a render" "-,-" (show_ctx outside)

let mount w g =
  w.after_snaps <- [];
  if w.feats.hydrate then begin
    Server.Testing.set_log (fun _ _ -> ());
    let server =
      Fun.protect ~finally:restore_log (fun () ->
          Private.render_html (fun () -> Private.node (root (env w Server w.live))))
    in
    check_context w;
    Dom_cases.set_html w.live server;
    let catches = w.client_catches in
    Dom_cases.capture_warnings ();
    let d =
      match Private.hydrate (Dom_cases.as_element w.live) (fun () -> root (env w Live w.live)) with
      | d -> d
      | exception e ->
          ignore (Dom_cases.warnings ());
          raise e
    in
    w.dispose <- d;
    let warnings = Dom_cases.warnings () in
    if warnings <> "" then fail w "5 hydration" "mismatch log" "nothing" warnings;
    if w.client_catches = catches && html w.live <> server then
      fail w "5 hydration" "the DOM after hydration" server (html w.live)
  end
  else if chance g 30 then begin
    Yuka.render ~root:(Dom_cases.as_element w.live, fun () -> root (env w Live w.live)) ();
    w.dispose <- Yuka.stop
  end
  else w.dispose <- Private.render (Dom_cases.as_element w.live) (fun () -> root (env w Live w.live))

type pre = {
  rows : (string * node * int) list;
  values : (int * int) array array;
  before_runs : (inst * int array) list;
  events : int;
}

let tag_key = "__fuzz_tag"

let capture w =
  let rows =
    Array.to_list
      (Array.map
         (fun n ->
           let t =
             match Js.Undefined.toOption (get_tag n tag_key) with
             | Some t -> t
             | None ->
                 w.next_tag <- w.next_tag + 1;
                 set_tag n tag_key w.next_tag;
                 w.next_tag
           in
           (attr_of n "data-row", n, t))
         (query_all w.live "[data-row]"))
  in
  {
    rows;
    values = Array.map State.peek w.lists;
    before_runs = List.map (fun i -> (i, Array.copy i.runs)) w.insts;
    events = w.guard_events;
  }

let segments path =
  List.filter_map
    (fun seg ->
      if String.length seg > 1 && seg.[0] = 'l' then
        match String.split_on_char ':' (String.sub seg 1 (String.length seg - 1)) with
        | [ id; k ] -> Some (int_of_string id, int_of_string k)
        | _ -> None
      else None)
    (String.split_on_char '/' path)

let value_of arr k = Array.fold_left (fun acc (k', v) -> if k' = k then Some v else acc) None arr

let expected_kept w pre path =
  List.for_all
    (fun (id, k) ->
      let holes, guarded = Hashtbl.find w.spec.ctx id in
      let src = Hashtbl.find w.spec.sources id in
      let before = value_of pre.values.(src) k and after = value_of (State.peek w.lists.(src)) k in
      before <> None && before = after
      && List.for_all (fun s -> not w.touched.(s)) holes
      && ((not guarded) || w.guard_events = pre.events))
    (segments path)

let ints_show l = String.concat "," (List.map string_of_int l)

let check_instances w pre ~stopped =
  let present = Hashtbl.create 16 in
  Array.iter (fun n -> Hashtbl.replace present (attr_of n "data-c") ()) (query_all w.live "[data-c]");
  List.iter
    (fun i ->
      let alive =
        (not i.stopped) && Hashtbl.find_opt w.latest i.ipath == Some i && Hashtbl.mem present i.ipath
      in
      let who k =
        Printf.sprintf "%s effect %d (%s)" i.ipath k
          (match i.effs.(k).kind with Before -> "before" | After -> "after")
      in
      Array.iteri
        (fun k e ->
          if e.cleanup then begin
            let want = i.ok_runs.(k) - if alive && i.last_ok.(k) then 1 else 0 in
            if i.cleanups.(k) <> want then
              fail w "3 cleanups" (who k ^ (if alive then " alive" else " disposed") ^ ": cleanups")
                (string_of_int want) (string_of_int i.cleanups.(k))
          end;
          if alive then begin
            if i.runs.(k) < 1 then fail w "4 effects" (who k ^ ": runs") "at least 1" "0";
            let want = List.map (model w) e.reads in
            if i.seen.(k) <> want then
              fail w "4 effects" (who k ^ ": values of the last run") (ints_show want) (ints_show i.seen.(k));
            match List.assq_opt i pre.before_runs with
            | Some runs when not stopped ->
                let delta = i.runs.(k) - runs.(k) in
                if delta > 1 then fail w "4 effects" (who k ^ ": runs in one change") "at most 1" (string_of_int delta);
                if delta > 0 && not (List.exists (touched w) e.reads) then
                  fail w "4 effects" (who k ^ ": runs with no read changed") "0" (string_of_int delta)
            | _ -> ()
          end)
        i.effs;
      if alive then stats.alive <- stats.alive + 1 else stats.dead <- stats.dead + 1;
      if not alive then
        match i.frozen with
        | None -> i.frozen <- Some (Array.copy i.runs)
        | Some runs ->
            if runs <> i.runs then
              fail w "3 no run after dispose" (i.ipath ^ ": runs")
                (ints_show (Array.to_list runs)) (ints_show (Array.to_list i.runs)))
    w.insts

let check_rows w pre ~stopped =
  let now = Hashtbl.create 16 in
  Array.iter (fun n -> Hashtbl.replace now (attr_of n "data-row") n) (query_all w.live "[data-row]");
  List.iter
    (fun (path, n, t) ->
      match Hashtbl.find_opt now path with
      | Some m ->
          if (not stopped) && expected_kept w pre path then begin
            stats.kept <- stats.kept + 1;
            if m != n then fail w "2 rows keep nodes" (path ^ ": node") "the same node" "a new node";
            if get_tag m tag_key <> Js.Undefined.return t then fail w "2 rows keep nodes" (path ^ ": tag") (string_of_int t) "another tag"
          end
      | None ->
          stats.removed <- stats.removed + 1;
          if is_connected n then fail w "2 rows keep nodes" (path ^ ": removed row") "not in the document" "in the document")
    pre.rows

let check_shadow w =
  let c = Dom_cases.container "" in
  w.shadow_insts <- [];
  w.after_snaps <- [];
  let d = Private.render (Dom_cases.as_element c) (fun () -> root (env w Shadow c)) in
  let fresh = html c in
  let a = canonical w.live and b = canonical c in
  List.iter
    (fun (r, h) -> if r == c && h <> fresh then fail w "4 after sees the DOM" "fresh render: container in an after effect" fresh h)
    w.after_snaps;
  d ();
  remove_node c;
  if a <> b then fail w "1 fresh render" "the live DOM" b a;
  List.iter
    (fun i ->
      Array.iteri
        (fun k e ->
          if e.cleanup && i.cleanups.(k) <> i.ok_runs.(k) then
            fail w "3 cleanups" (Printf.sprintf "fresh render %s effect %d after dispose: cleanups" i.ipath k)
              (string_of_int i.ok_runs.(k)) (string_of_int i.cleanups.(k)))
        i.effs)
    w.shadow_insts

let check_step w pre ~stopped =
  (match w.violations with v :: _ -> fail w "3 cleanups" "cleanup argument" "the result of the previous run" v | [] -> ());
  check_context w;
  let live = html w.live in
  if w.guard_events = pre.events then
    List.iter
      (fun (r, h) ->
        stats.after_seen <- stats.after_seen + 1;
        if r == w.live && h <> live then fail w "4 after sees the DOM" "container in an after effect" live h)
      w.after_snaps;
  check_rows w pre ~stopped;
  check_instances w pre ~stopped;
  check_shadow w;
  check_context w

type op =
  | Set of int * int
  | Set_list of int * (int * int) array
  | Batch of op list
  | Click of int
  | Reset of int
  | Stop of op list

let show_pairs a = String.concat " " (Array.to_list (Array.map (fun (k, v) -> Printf.sprintf "%d:%d" k v) a))

let rec show_op = function
  | Set (i, v) -> Printf.sprintf "set s%d %d" i v
  | Set_list (j, a) -> Printf.sprintf "set l%d [%s]" j (show_pairs a)
  | Batch ops -> "batch(" ^ String.concat ", " (List.map show_op ops) ^ ")"
  | Click k -> Printf.sprintf "click button %d" k
  | Reset k -> Printf.sprintf "click fallback %d" k
  | Stop ops -> "stop, " ^ String.concat ", " (List.map show_op ops) ^ ", render"

let shuffle g a =
  let a = Array.copy a in
  for i = Array.length a - 1 downto 1 do
    let j = int g (i + 1) in
    let x = a.(i) in
    a.(i) <- a.(j);
    a.(j) <- x
  done;
  a

let fresh_keys g n =
  let pool = shuffle g (Array.init 10 (fun k -> k)) in
  Array.init n (fun i -> (pool.(i), int g 3))

let gen_list g cur =
  let n = Array.length cur in
  let l = Array.to_list cur in
  match int g 10 with
  | 0 ->
      let free = List.filter (fun k -> not (List.mem_assoc k l)) (List.init 12 (fun k -> k)) in
      let k = List.nth free (int g (List.length free)) in
      let at = int g (n + 1) in
      Array.concat [ Array.sub cur 0 at; [| (k, int g 3) |]; Array.sub cur at (n - at) ]
  | 1 when n > 0 ->
      let at = int g n in
      Array.append (Array.sub cur 0 at) (Array.sub cur (at + 1) (n - at - 1))
  | 2 when n > 1 ->
      let i = int g n and j = int g (n - 1) in
      let x = cur.(i) in
      let rest = Array.append (Array.sub cur 0 i) (Array.sub cur (i + 1) (n - i - 1)) in
      Array.concat [ Array.sub rest 0 j; [| x |]; Array.sub rest j (n - 1 - j) ]
  | 3 -> Array.of_list (List.rev l)
  | 4 when n > 1 ->
      let a = Array.copy cur in
      let i = int g n and j = int g n in
      let x = a.(i) in
      a.(i) <- a.(j);
      a.(j) <- x;
      a
  | 5 -> [||]
  | 6 -> fresh_keys g (int g 6)
  | 7 -> shuffle g cur
  | 8 when n > 0 ->
      let a = Array.copy cur in
      let i = int g n in
      let k, v = a.(i) in
      a.(i) <- (k, (v + 1) mod 3);
      a
  | _ -> Array.copy cur

let gen_write g w =
  if w.spec.n_lists > 0 && chance g 50 then
    let j = int g w.spec.n_lists in
    Set_list (j, gen_list g (State.peek w.lists.(j)))
  else Set (int g w.spec.n_ints, int g 5)

let gen_int_write g w = Set (int g w.spec.n_ints, int g 5)

let gen_op g w =
  let f = w.feats in
  let roll = int g 100 in
  let fallbacks = Array.length (query_all w.live "[data-fallback]") in
  let buttons = Array.length (query_all w.live "button[data-b]") in
  if f.stop && roll < 6 then Stop (list (1 + int g 2) (fun () -> gen_int_write g w))
  else if f.catch && fallbacks > 0 && roll < 20 then Reset (int g fallbacks)
  else if f.events && buttons > 0 && roll < 35 then Click (int g buttons)
  else if f.batches && roll < 55 then Batch (list (2 + int g 3) (fun () -> gen_write g w))
  else gen_write g w

let rec apply w = function
  | Set (i, v) -> write_int w i v
  | Set_list (j, a) -> State.set w.lists.(j) a
  | Batch ops -> batch (fun () -> List.iter (apply w) ops)
  | Click k ->
      stats.clicks <- stats.clicks + 1;
      let b = (query_all w.live "button[data-b]").(k) in
      let path = attr_of b "data-b" in
      let id = String.sub path (String.rindex path 'b' + 1) (String.length path - String.rindex path 'b' - 1) in
      let s = Hashtbl.find w.spec.buttons (int_of_string id) in
      let before = State.peek w.ints.(s) in
      Dom_cases.click b;
      if State.peek w.ints.(s) <> before + 1 then
        fail w "6 events" (path ^ ": the State after a click") (string_of_int (before + 1))
          (string_of_int (State.peek w.ints.(s)))
  | Reset k ->
      stats.resets <- stats.resets + 1;
      let events = w.guard_events in
      Dom_cases.click (query_all w.live "[data-fallback]").(k);
      if w.guard_events = events then fail w "6 catch" "a click on reset" "the children render again" "nothing"
  | Stop _ -> ()

let stop_and_render w g ops =
  stats.stops <- stats.stops + 1;
  w.dispose ();
  w.dispose <- ignore;
  List.iter (fun i -> i.stopped <- true) w.insts;
  Array.iteri
    (fun i s -> if Private.has_readers s then fail w "3 no readers after stop" (Printf.sprintf "s%d" i) "no reader" "a reader")
    w.ints;
  Array.iteri
    (fun i s -> if Private.has_readers s then fail w "3 no readers after stop" (Printf.sprintf "l%d" i) "no reader" "a reader")
    w.lists;
  let dom = html w.live in
  let runs = List.map (fun i -> (i, Array.copy i.runs)) w.insts in
  List.iter (apply w) ops;
  List.iter
    (fun (i, r) ->
      if r <> i.runs then fail w "3 no run after stop" (i.ipath ^ ": runs") (ints_show (Array.to_list r)) (ints_show (Array.to_list i.runs)))
    runs;
  if html w.live <> dom then fail w "3 no update after stop" "the DOM" dom (html w.live);
  mount w g

let execute f seed ~steps =
  let g = rng seed in
  let spec = gen_spec g f in
  let live = Dom_cases.container "" in
  let w =
    {
      seed;
      feats = f;
      spec;
      ints = Array.init spec.n_ints (fun _ -> State.make (int g 4));
      lists = Array.init spec.n_lists (fun _ -> State.make (fresh_keys g (int g 5)));
      touched = Array.make spec.n_ints false;
      latest = Hashtbl.create 16;
      insts = [];
      shadow_insts = [];
      caught = Hashtbl.create 4;
      guard_events = 0;
      client_catches = 0;
      after_snaps = [];
      violations = [];
      ctx_fails = [];
      step = 0;
      ops = [];
      live;
      dispose = ignore;
      next_tag = 0;
    }
  in
  let finish () =
    (try w.dispose () with _ -> ());
    remove_node live
  in
  match
    let pre = capture w in
    mount w g;
    check_step w pre ~stopped:true;
    for step = 1 to steps do
      w.step <- step;
      let op = gen_op g w in
      w.ops <- show_op op :: w.ops;
      let pre = capture w in
      Array.fill w.touched 0 (Array.length w.touched) false;
      w.after_snaps <- [];
      match op with
      | Stop ops ->
          stop_and_render w g ops;
          check_step w pre ~stopped:true
      | op ->
          (match apply w op with
          | () -> ()
          | exception (Cases.Failed _ as e) -> raise e
          | exception e -> fail w "0 no exception" "the operation" "no exception" (Printexc.to_string e));
          check_step w pre ~stopped:false
    done
  with
  | () -> finish ()
  | exception e ->
      finish ();
      raise e

let seeds_run = ref 0
let steps_run = ref 0

let run_seed ?(steps = 25) f seed =
  incr seeds_run;
  steps_run := !steps_run + steps;
  execute f seed ~steps

let seeds ?steps f ~from ~upto () =
  for seed = from to upto do
    run_seed ?steps f seed
  done

let switch = { base with switch = true }
let lists = { base with lists = true }
let nested = { base with lists = true; nested = true }
let memos = { base with memos = true }
let effects = { base with effects = true }
let catch = { base with catch = true }
let events = { base with events = true }
let batches = { base with batches = true; lists = true }
let stop = { base with stop = true; effects = true }
let hydrate = { base with hydrate = true }
let effects_lists = { base with effects = true; lists = true; nested = true }
let effects_switch = { base with effects = true; switch = true }
let catch_effects = { base with effects = true; catch = true; lists = true; nested = true }
let hydrate_events = { base with hydrate = true; events = true }
let row_raise = { catch_effects with row_raise = true }
let context = { base with context = true }
let context_lists = { base with context = true; lists = true; nested = true; effects = true; batches = true }
let context_switch = { base with context = true; switch = true; effects = true; events = true }
let context_catch = { base with context = true; catch = true; effects = true; lists = true; nested = true; events = true }
let context_hydrate = { base with context = true; hydrate = true; switch = true; lists = true; events = true }

let every =
  {
    switch = true;
    lists = true;
    nested = true;
    memos = true;
    effects = true;
    catch = true;
    events = true;
    batches = true;
    stop = true;
    hydrate = false;
    row_raise = false;
    context = true;
  }

let every_hydrate = { every with hydrate = true }

let only f l () = List.iter (run_seed f) l

let row_raise_leak ~update () =
  let s = State.make 0 and items = State.make (if update then [||] else [| 1; 2 |]) in
  let runs = ref 0 and cleanups = ref 0 in
  let c = Dom_cases.container "" in
  let dispose =
    Private.render (Dom_cases.as_element c) (fun () ->
        Catch.make
          ~fallback:(fun ~error ~reset:_ -> text ("caught " ^ error))
          ~children:(fun () ->
            element "ul" []
              [ each ~key:string_of_int
                  (fun () -> State.get items)
                  (fun k ->
                    if k = 2 then failwith "row 2";
                    Effect.before ~cleanup:(fun () -> incr cleanups) (fun () ->
                        ignore (State.get s);
                        incr runs);
                    element "li" [] [ text (string_of_int k) ]) ])
          ())
  in
  if update then State.set items [| 2; 1 |];
  let shown = html c in
  State.set s 1;
  let readers = Private.has_readers s in
  dispose ();
  remove_node c;
  Cases.check "fallback" "<!--[-->caught Failure(row 2)<!--]-->" shown;
  Cases.check "runs, cleanups and readers of row 1 after the boundary caught row 2" "1 1 false"
    (Printf.sprintf "%d %d %b" !runs !cleanups readers)

let all =
  [
    ("dom fuzz: base", seeds base ~from:1 ~upto:30);
    ("dom fuzz: switch", seeds switch ~from:1 ~upto:30);
    ("dom fuzz: lists", seeds lists ~from:1 ~upto:20);
    ("dom fuzz: nested lists", seeds nested ~from:1 ~upto:12);
    ("dom fuzz: memos", seeds memos ~from:1 ~upto:30);
    ("dom fuzz: effects", seeds effects ~from:1 ~upto:30);
    ("dom fuzz: effects in lists", seeds effects_lists ~from:1 ~upto:10);
    ("dom fuzz: effects in switches", seeds effects_switch ~from:1 ~upto:20);
    ("dom fuzz: catch", seeds catch ~from:1 ~upto:30);
    ("dom fuzz: catch with effects and lists", seeds catch_effects ~from:1 ~upto:12);
    ("dom fuzz: events", seeds events ~from:1 ~upto:30);
    ("dom fuzz: batches", seeds batches ~from:1 ~upto:15);
    ("dom fuzz: stop", seeds stop ~from:1 ~upto:20);
    ("dom fuzz: hydrate", seeds hydrate ~from:1 ~upto:30);
    ("dom fuzz: hydrate with events", seeds hydrate_events ~from:1 ~upto:20);
    ("dom fuzz: context", seeds context ~from:1 ~upto:20);
    ("dom fuzz: context in lists", seeds context_lists ~from:1 ~upto:10);
    ("dom fuzz: context in switches", seeds context_switch ~from:1 ~upto:10);
    ("dom fuzz: context in catch", seeds context_catch ~from:1 ~upto:10);
    ("dom fuzz: context with hydration", seeds context_hydrate ~from:1 ~upto:10);
    ("dom fuzz: every feature", seeds every ~from:1 ~upto:12);
    ("dom fuzz: every feature with hydration", seeds every_hydrate ~from:1 ~upto:12);
    ("dom fuzz: a row that raises on first mount stops the rows before it", row_raise_leak ~update:false);
    ("dom fuzz: a row that raises in an update stops the rows created before it", row_raise_leak ~update:true);
    ("dom fuzz: rows that raise", only row_raise [ 500; 555; 876; 897 ]);
  ]
