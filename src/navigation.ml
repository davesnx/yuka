let current_key = Navigation_stub.current_key
let loaded = Navigation_stub.loaded
let shown_key = Navigation_stub.shown_key
let started = ref false
let pending : Navigation_web.controller option ref = ref None

let table = Navigation_stub.table
let scrolls () = table Navigation_stub.scroll_table

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

let save_scroll = Navigation_stub.save_scroll

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

let fill el header text =
  let title =
    Option.map (fun t -> match Web.decode_uri t with Some d -> d | None -> t) (header "yuka-title")
  in
  Client.stop_within el;
  Navigation_web.adopt_stylesheets ();
  Web.set_inner_html el text;
  Navigation_web.adopt_stylesheets ();
  Option.iter Navigation_web.set_title title;
  Option.iter Navigation_web.set_html (header "yuka-html")

let swap target final header text =
  match target with
  | Some el ->
      fill el header text;
      Navigation_web.set_head el;
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
  overlay : bool;
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

let lookup overlay key =
  match Web.table_get (cache ()) key with
  | Some e -> (
      match e.answer with
      | None -> if e.overlay = overlay then Some e else None
      | Some a when e.overlay <> overlay && (overlay || is "overlay" (a.header "yuka-layer")) -> None
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

type overlay = {
  key : string;
  under : string;
  url : string;
  title : string;
  focus : Web.node;
  route : (Web.node * Web.node) option;
  direct : bool;
}

let overlays : overlay list ref = ref []
let showing () = List.find_opt (fun o -> String.equal o.key !shown_key) !overlays
let beneath () = match showing () with Some o -> o.under | None -> !shown_key

let hide () =
  Array.iter
    (fun el ->
      Client.stop_within el;
      Web.remove el)
    (Web.query_all (Web.document ()) "yuka-overlay")

let prefetching = ref Prefetch.default
let transitions_on = ref false
let nav = ref 0
let hover = ref ignore

type waiting = { link : Web.node; key : string; url : string; trigger : Prefetch.level; unobserve : unit -> unit }

let queued : waiting list ref = ref []

let rec without f = function [] -> [] | x :: rest -> if f x then without f rest else x :: without f rest

let take key =
  List.iter (fun w -> if String.equal w.key key then w.unobserve ()) !queued;
  queued := without (fun w -> String.equal w.key key) !queued

let opened () =
  let n = ref 0 in
  Array.iter (fun e -> if Option.is_none e.answer then incr n) (Web.table_values (cache ()));
  !n

let allowed () =
  !started && (match !prefetching with `Off -> false | _ -> true) && not (Navigation_web.save_data ())

let under trigger page =
  match Web.table_get (limits ()) page with Some l -> Prefetch.rank trigger <= Prefetch.rank l | None -> true

let rec start (trigger : Prefetch.level) key url =
  let low = match trigger with `Visible | `Idle -> true | _ -> false in
  let page = Navigation_web.absolute url in
  if under trigger page && Option.is_none (lookup true key) then begin
    let e =
      { key; answer = None; waiters = []; controller = Navigation_web.new_controller (); at = 0.;
        prefetched = true; overlay = true; warm = (match trigger with `Hover -> true | _ -> false) }
    in
    add e;
    let settle a =
      let w = e.waiters in
      e.waiters <- [];
      List.iter (fun f -> f a) (List.rev w);
      pump ()
    in
    Navigation_web.fetch_page (url, keys (), Prefetch.name trigger, low, e.controller, true)
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
          | (`Trajectory | `Visible | `Idle) when e.warm && (not waited) && allowed () -> start `Hover key url
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
  | w :: rest
    when opened () < 4 && allowed ()
         && match w.trigger with `Idle -> not (Navigation_web.hidden_or_slow ()) | _ -> true ->
      queued := rest;
      w.unobserve ();
      start w.trigger w.key w.url;
      pump ()
  | _ -> ()

let prefetch url =
  if allowed () then begin
    let key = page_key url in
    take key;
    match lookup true key with
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
  queued := without (fun w -> w.link == a && match w.trigger with `Visible -> true | _ -> false) !queued;
  match Web.link_href true a with
  | href when inside && href <> "" && allowed () ->
      let key = page_key href in
      if opened () < 4 || Option.is_some (lookup true key) then begin
        unobserve ();
        start `Visible key href
      end
      else queued := { link = a; key; url = href; trigger = `Visible; unobserve } :: !queued
  | _ -> if inside then unobserve ()

let rec waits key = function [] -> false | w :: rest -> String.equal w.key key || waits key rest

let pass () =
  allowed () && (not (Navigation_web.hidden_or_slow ()))
  && begin
    let here = Navigation_web.absolute (Web.current_url ()) and fresh = ref [] and n = ref 0 in
    Array.iter
      (fun a ->
        match Web.link_href true a with
        | href when href <> "" && !n < 15 ->
            let key = page_key href and page = Navigation_web.absolute href in
            if (not (String.equal page here)) && under `Idle page
               && Option.is_none (lookup true key)
               && not (waits key !queued || waits key !fresh)
            then begin
              incr n;
              fresh := { link = a; key; url = href; trigger = `Idle; unobserve = ignore } :: !fresh
            end
        | _ -> ())
      (Web.query_all (Web.document ()) "a[href]");
    queued := List.rev_append (List.rev !queued) (List.rev !fresh);
    pump ();
    true
  end

let show ~dir ~push ~restore url a =
  let final =
    match hash_of url with
    | "" -> a.final
    | h -> Navigation_web.no_hash a.final ^ h
  in
  match swappable a with
  | None -> assign final
  | Some target ->
      let over = is "overlay" (a.header "yuka-layer") in
      if push then begin
        let key = Web.fresh_key () in
        if over then
          overlays :=
            (match showing () with
            | Some o -> { o with key; direct = false }
            | None ->
                {
                  key;
                  under = !shown_key;
                  url = !loaded;
                  title = Navigation_web.title ();
                  focus = Navigation_web.active ();
                  route = Navigation_web.route_script ();
                  direct = true;
                })
            :: !overlays;
        Web.history_push_key key final;
        current_key := key
      end;
      let gen = !nav in
      let apply () =
        if !nav = gen then begin
          loaded := Web.current_url ();
          shown_key := !current_key;
          Navigation_state.set false;
          let target =
            if over then begin
              let el = Navigation_web.layer () in
              fill el a.header a.text;
              Some el
            end
            else begin
              overlays := without (fun (o : overlay) -> String.equal o.key !shown_key) !overlays;
              hide ();
              swap target final a.header a.text;
              Platform.kept := [];
              (match restore with
              | Some y -> Navigation_web.scroll_to y
              | None -> Navigation_web.scroll_to_hash (hash_of final));
              target
            end
          in
          !Platform.swapped target;
          !start_islands ();
          Navigation_web.live ();
          Navigation_web.settle (Option.value target ~default:(Web.document ())) (hash_of final)
        end
      in
      if !transitions_on then Navigation_web.transition dir apply else apply ()

let load ~overlay ~dir ~push ~restore url =
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
      Navigation_web.fetch_page (url, keys (), "", false, controller, overlay)
        (fun final status header text ->
          pending := None;
          let a = { final; status; header; text } in
          if max_age header > 0 && asked = !era then begin
            add { key; answer = Some a; waiters = []; controller; at = Navigation_web.now (); prefetched = false; overlay; warm = false };
            pump ()
          end;
          apply (Some a))
        (fun () ->
          pending := None;
          assign url)
    in
    match lookup overlay key with
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
  load ~overlay:true ~dir:"push" ~push:true ~restore:None url

let back () =
  match showing () with
  | Some o when not o.direct ->
      save_scroll ();
      load ~overlay:false ~dir:"back" ~push:true ~restore:None o.url
  | _ -> Web.history_back ()

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
  let observe () = Navigation_web.observe (Web.query_all (Web.document ()) "a[href]") seen in
  match !prefetching with
  | `Visible -> unwatch := observe ()
  | `Idle ->
      let skipped = ref false in
      let run () = skipped := not (pass ()) in
      let off = observe () and cancel = Web.on_idle run in
      let unlisten = Navigation_web.on_visible (fun () -> if !skipped then run () else pump ()) in
      unwatch :=
        fun () ->
          off ();
          cancel ();
          unlisten ()
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
  let shown = showing () in
  let closing = match shown with Some o -> String.equal next o.under | None -> false in
  if closing || Web.current_url () = !loaded || List.exists (String.equal next) !Platform.kept then begin
    shown_key := next;
    cancel_pending ();
    incr nav;
    Navigation_state.set false;
    Option.iter
      (fun o ->
        hide ();
        Navigation_web.set_title o.title;
        Option.iter
          (fun r ->
            Navigation_web.put_back r;
            !Platform.swapped (Some (snd r)))
          o.route;
        Navigation_web.refocus o.focus;
        on_out ())
      shown;
    if Web.current_url () <> !loaded then begin
      loaded := Web.current_url ();
      !Platform.moved ()
    end;
    if not closing then Navigation_web.scroll_to y
  end
  else
    load
      ~overlay:(List.exists (fun (o : overlay) -> String.equal o.key next && String.equal o.under (beneath ())) !overlays)
      ~dir ~push:false
      ~restore:(Some y) (Web.current_url ())

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
  shown_key := !current_key;
  Web.table_clear (limits ());
  (prefetching :=
     match Web.query_all (Web.document ()) "meta[name=yuka-prefetch]" with
     | [| m |] -> Option.value (Option.bind (Web.get_attribute m "content") Prefetch.of_name) ~default:Prefetch.default
     | _ -> Prefetch.default);
  transitions_on := transitions;
  !untrack ();
  (untrack :=
     match !prefetching with
     | `Trajectory | `Visible | `Idle -> Navigation_web.trajectory (Web.link_href true) predict
     | `Off | `Hover -> ignore);
  (Platform.acted :=
     fun () ->
       clear ();
       watch ());
  clear ();
  Navigation_web.adopt_stylesheets ();
  Navigation_web.live ();
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
  overlays := [];
  Array.iter (fun e -> if Option.is_none e.answer then Navigation_web.abort e.controller) (Web.table_values (cache ()));
  clear ();
  Platform.acted := ignore

let router : Types.router = { boot; navigate; back; handle; stop }
