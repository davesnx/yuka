let current_key = Navigation_stub.current_key
let loaded = Navigation_stub.loaded
let started = ref false
let pending : Navigation_web.controller option ref = ref None

let table r =
  match !r with
  | Some t -> t
  | None ->
      let t = Web.table () in
      r := Some t;
      t

let scroll_table : float Web.table option ref = ref None
let scrolls () = table scroll_table

let start_islands : (unit -> unit) ref = ref (fun () -> ())

let cancel_pending () =
  match !pending with
  | Some c ->
      pending := None;
      Navigation_web.abort c
  | None -> ()

let assign url =
  Navigation_state.set false;
  Web.location_assign url

let save_scroll () = Web.table_set (scrolls ()) !current_key (Navigation_web.scroll_y ())

let hash_of = Navigation_web.hash_of
let outlets () = Web.query_all (Web.document ()) "yuka-outlet"
let is value = function Some v -> String.equal v value | None -> false
let keys = Navigation_web.keys

let build () =
  match Web.query_all (Web.document ()) "meta[name=yuka-build]" with
  | [| meta |] -> Web.get_attribute meta "content"
  | _ -> None

let mark_links outlet path =
  let doc = Web.document () in
  let islands = Web.query_all doc "yuka-island" in
  Array.iter
    (fun a ->
      if not (Web.contains outlet a || Array.exists (fun i -> Web.contains i a) islands) then
        match (is path (Web.get_attribute a "href"), Web.get_attribute a "aria-current") with
        | true, None -> Web.set_attribute a "aria-current" "page"
        | false, Some "page" -> Web.remove_attribute a "aria-current"
        | _ -> ())
    (Web.query_all doc "a")

let outlet header =
  Option.map
    (fun key -> Array.find_opt (fun o -> is key (Web.get_attribute o "data-k")) (outlets ()))
    (header "yuka-outlet")

let swap target final header text =
  match target with
  | Some el ->
      let title =
        Option.map (fun t -> match Web.decode_uri t with Some d -> d | None -> t) (header "yuka-title")
      in
      Client.stop_within el;
      Navigation_web.adopt_stylesheets ();
      Web.set_inner_html el text;
      Navigation_web.adopt_stylesheets ();
      Option.iter Navigation_web.set_title title;
      mark_links el (Navigation_web.path_of final)
  | None ->
      Client.stop ();
      Navigation_web.swap_page text;
      Navigation_web.adopt_stylesheets ()

let html header =
  match header "content-type" with
  | Some t -> Navigation_web.is_html t
  | None -> false

type answer = { final : string; status : int; header : string -> string option; text : string }

let swappable a =
  let stale = match a.header "yuka-build" with Some b -> not (is b (build ())) | None -> false in
  let shown = (a.status >= 200 && a.status < 300) || a.status >= 400 in
  match outlet a.header with
  | Some None -> None
  | _ when stale || (not shown) || not (html a.header) -> None
  | target -> Some (Option.join target)

let warm a = if Option.is_some (swappable a) then Navigation_web.warm a.final a.text

type entry = {
  key : string;
  mutable answer : answer option;
  mutable waiters : (answer option -> unit) list;
  controller : Navigation_web.controller;
  mutable at : float;
  prefetched : bool;
  mutable warm : bool;
}

let cache_table : entry Web.table option ref = ref None
let cache () = table cache_table

let limit_table : Prefetch.level Web.table option ref = ref None
let limits () = table limit_table

let max_age header = Navigation_web.max_age (Option.value (header "cache-control") ~default:"")

let drop e =
  match Web.table_get (cache ()) e.key with
  | Some x when x == e -> Web.table_delete (cache ()) e.key
  | _ -> ()

let discard e =
  drop e;
  match (e.answer, e.waiters) with None, [] -> Navigation_web.abort e.controller | _ -> ()

let era = ref 0

let lookup key =
  match Web.table_get (cache ()) key with
  | Some e -> (
      match e.answer with
      | None -> Some e
      | Some a ->
          let age = Navigation_web.now () -. e.at and n = max_age a.header in
          if (n > 0 && age < float_of_int n *. 1000.) || (n = 0 && e.prefetched && age < 10000.)
          then Some e
          else begin
            drop e;
            None
          end)
  | None -> None

let add e =
  let t = cache () in
  if Web.table_size t >= 30 && not (Web.table_has t e.key) then discard (Web.table_values t).(0);
  Web.table_set t e.key e

let page_key url = Navigation_web.absolute url ^ " " ^ keys ()

let prefetching = ref Prefetch.default
let transitions_on = ref false
let nav = ref 0
let hover = ref ignore

let queued : (Web.node * string * string * (unit -> unit)) list ref = ref []

let rec without f = function [] -> [] | x :: rest -> if f x then without f rest else x :: without f rest

let take key =
  List.iter (fun (_, k, _, unobserve) -> if String.equal k key then unobserve ()) !queued;
  queued := without (fun (_, k, _, _) -> String.equal k key) !queued

let opened () =
  let n = ref 0 in
  Array.iter (fun e -> if Option.is_none e.answer then incr n) (Web.table_values (cache ()));
  !n

let allowed () =
  !started && (match !prefetching with `Off -> false | _ -> true) && not (Navigation_web.save_data ())

let rec start (trigger : Prefetch.level) key url =
  let low = match trigger with `Visible -> true | _ -> false in
  let page = Navigation_web.absolute url in
  let under = match Web.table_get (limits ()) page with Some l -> Prefetch.rank trigger <= Prefetch.rank l | None -> true in
  if under && Option.is_none (lookup key) then begin
    let e =
      { key; answer = None; waiters = []; controller = Navigation_web.new_controller (); at = 0.;
        prefetched = true; warm = (match trigger with `Hover -> true | _ -> false) }
    in
    add e;
    let settle a =
      let w = e.waiters in
      e.waiters <- [];
      List.iter (fun f -> f a) (List.rev w);
      pump ()
    in
    Navigation_web.fetch_page (url, keys (), Prefetch.name trigger, low, e.controller)
      (fun final status header text ->
        let a = { final; status; header; text } and waited = match e.waiters with [] -> false | _ -> true in
        if status = 204 then begin
          drop e;
          Option.iter
            (fun l ->
              let t = limits () in
              if Web.table_size t >= 200 then Web.table_clear t;
              Web.table_set t page l)
            (Option.bind (header "yuka-prefetch") Prefetch.of_name);
          settle (Some a);
          match trigger with
          | (`Trajectory | `Visible) when e.warm && (not waited) && allowed () -> start `Hover key url
          | _ -> ()
        end
        else begin
          e.at <- Navigation_web.now ();
          e.answer <- Some a;
          settle e.answer;
          if e.warm && not waited then warm a
        end)
      (fun () ->
        drop e;
        settle None)
  end

and pump () =
  match !queued with
  | (_, key, url, unobserve) :: rest when opened () < 4 && allowed () ->
      queued := rest;
      unobserve ();
      start `Visible key url;
      pump ()
  | _ -> ()

let prefetch url =
  if allowed () then begin
    let key = page_key url in
    take key;
    match lookup key with
    | Some e ->
        e.warm <- true;
        Option.iter warm e.answer
    | None -> start `Hover key url
  end

let predict url =
  if allowed () then begin
    let key = page_key url in
    take key;
    start `Trajectory key url
  end

let seen a inside unobserve =
  queued := without (fun (l, _, _, _) -> l == a) !queued;
  match Web.link_href true a with
  | href when inside && href <> "" && allowed () ->
      let key = page_key href in
      if opened () < 4 || Option.is_some (lookup key) then begin
        unobserve ();
        start `Visible key href
      end
      else queued := (a, key, href, unobserve) :: !queued
  | _ -> if inside then unobserve ()

let show ~dir ~push ~restore url a =
  let final =
    match hash_of url with
    | "" -> a.final
    | h -> Navigation_web.no_hash a.final ^ h
  in
  match swappable a with
  | None -> assign final
  | Some target ->
      if push then begin
        let key = Web.fresh_key () in
        Navigation_web.history_push_key key final;
        current_key := key
      end;
      loaded := Web.current_url ();
      let apply () =
        Navigation_state.set false;
        swap target final a.header a.text;
        (match restore with
        | Some y -> Navigation_web.scroll_to y
        | None -> Navigation_web.scroll_to_hash (hash_of final));
        !start_islands ()
      in
      if !transitions_on then Navigation_web.transition dir apply else apply ()

let load ~dir ~push ~restore url =
  if not !started then assign url
  else begin
    cancel_pending ();
    !hover ();
    hover := ignore;
    incr nav;
    let gen = !nav in
    let apply = function
      | _ when !nav <> gen -> ()
      | Some a -> show ~dir ~push ~restore url a
      | None -> assign url
    in
    let key = page_key url in
    take key;
    let fetch () =
      let controller = Navigation_web.new_controller () in
      let asked = !era in
      pending := Some controller;
      Navigation_web.fetch_page (url, keys (), "", false, controller)
        (fun final status header text ->
          pending := None;
          let a = { final; status; header; text } in
          if max_age header > 0 && asked = !era then begin
            add { key; answer = Some a; waiters = []; controller; at = Navigation_web.now (); prefetched = false; warm = false };
            pump ()
          end;
          apply (Some a))
        (fun () ->
          pending := None;
          assign url)
    in
    match lookup key with
    | Some e -> (
        let use = function
          | Some a when e.prefetched && a.status = 204 -> if !nav = gen then fetch ()
          | a ->
              (match a with Some a when max_age a.header = 0 -> drop e | _ -> ());
              apply a
        in
        match e.answer with
        | Some _ -> use e.answer
        | None -> e.waiters <- use :: e.waiters)
    | None -> fetch ()
  end

let navigate url =
  save_scroll ();
  load ~dir:"push" ~push:true ~restore:None url

let on_over e =
  match Web.link_href true (Web.target e) with
  | "" -> ()
  | href ->
      !hover ();
      hover := Navigation_web.after 50 (fun () -> prefetch href)

let on_out _ =
  !hover ();
  hover := ignore

let on_touch e =
  match Web.link_href true (Web.target e) with "" -> () | href -> prefetch href

let on_down e = if Web.plain_click e then on_touch e

let unwatch = ref ignore
let untrack = ref ignore

let watch () =
  !unwatch ();
  unwatch := ignore;
  queued := [];
  match !prefetching with
  | `Visible -> unwatch := Navigation_web.observe (Web.query_all (Web.document ()) "a[href]") seen
  | `Off | `Hover | `Trajectory -> ()

let clear () =
  incr era;
  queued := [];
  Array.iter discard (Web.table_values (cache ()));
  Web.table_clear (cache ())

let on_popstate _ =
  save_scroll ();
  let next = Web.history_key () in
  let dir = if Navigation_web.key_before next !current_key then "back" else "forward" in
  current_key := next;
  let y = Option.value (Web.table_get (scrolls ()) !current_key) ~default:0. in
  if Web.current_url () = !loaded then begin
    cancel_pending ();
    incr nav;
    Navigation_state.set false;
    Navigation_web.scroll_to y
  end
  else load ~dir ~push:false ~restore:(Some y) (Web.current_url ())

let handle e =
  match Navigation_web.event_type e with
  | "popstate" -> on_popstate e
  | "pointerover" | "focusin" -> on_over e
  | "pointerdown" -> on_down e
  | "touchstart" -> on_touch e
  | _ -> on_out e

let boot (transitions, islands) =
  cancel_pending ();
  started := true;
  Web.table_clear (limits ());
  (prefetching :=
     match Web.query_all (Web.document ()) "meta[name=yuka-prefetch]" with
     | [| m |] -> Option.value (Option.bind (Web.get_attribute m "content") Prefetch.of_name) ~default:Prefetch.default
     | _ -> Prefetch.default);
  transitions_on := transitions;
  !untrack ();
  (untrack :=
     match !prefetching with
     | `Trajectory | `Visible -> Navigation_web.trajectory (Web.link_href true) predict
     | `Off | `Hover -> ignore);
  (Platform.acted :=
     fun () ->
       clear ();
       watch ());
  clear ();
  Navigation_web.adopt_stylesheets ();
  (start_islands :=
     fun () ->
       islands ();
       watch ());
  watch ()

let stop () =
  cancel_pending ();
  started := false;
  Navigation_state.set false;
  start_islands := (fun () -> ());
  on_out ();
  !unwatch ();
  unwatch := ignore;
  !untrack ();
  untrack := ignore;
  incr nav;
  Array.iter (fun e -> if Option.is_none e.answer then Navigation_web.abort e.controller) (Web.table_values (cache ()));
  clear ();
  Platform.acted := ignore

let router : Types.router = { boot; navigate; handle; stop }
