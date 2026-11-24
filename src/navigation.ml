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

let assign ~replace url =
  Navigation_state.set None;
  Web.navigate replace url

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
  Option.iter Navigation_web.set_title title

let swap target final header text =
  match target with
  | Some el ->
      fill el header text;
      mark_links el (Navigation_web.path_of final)
  | None ->
      Client.stop ();
      Navigation_web.swap_page text;
      Navigation_web.adopt_stylesheets ()

let html header =
  match header "content-type" with
  | Some t -> Navigation_web.is_html t
  | None -> false

type stream = {
  mutable parts : (string * string) list;
  mutable result : bool option;
  mutable next : (string * string) option -> unit;
  mutable cancel : unit -> unit;
}

type answer = { final : string; status : int; header : string -> string option; text : string; stream : stream option }

let stream cancel = { parts = []; result = None; next = ignore; cancel }

let got s id html =
  s.parts <- (id, html) :: s.parts;
  s.next (Some (id, html))

let ended s broke complete =
  s.result <- Some complete;
  if not complete then broke ();
  s.next None

let swappable a =
  let stale = match a.header "yuka-build" with Some b -> not (is b (build ())) | None -> false in
  let shown = (a.status >= 200 && a.status < 300) || a.status >= 400 in
  match outlet a.header with
  | Some None -> None
  | _ when stale || (not shown) || not (Option.is_some a.stream || html a.header) -> None
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
  Array.iter
    (fun e ->
      match e.answer with
      | None -> incr n
      | Some { stream = Some { result = None; _ }; _ } when e.prefetched -> incr n
      | Some _ -> ())
    (Web.table_values (cache ()));
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
    let s = stream ignore in
    Navigation_web.fetch_page (url, keys (), Prefetch.name trigger, low, e.controller, true)
      (fun final status header text streamed ->
        let a = { final; status; header; text; stream = (if streamed then Some s else None) } and waited = match e.waiters with [] -> false | _ -> true in
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
      (got s)
      (fun complete ->
        ended s (fun () -> drop e) complete;
        pump ())
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

let following : (Web.node * (unit -> unit)) list ref = ref []
let broken : Web.node list ref = ref []
let owners = ref 0

let report () =
  let value = match (!following, !broken) with _ :: _, _ -> `Filling | [], _ :: _ -> `Broken | [], [] -> `Done in
  Scheduler.batch (fun () -> Signal.set Navigation_state.stream value)

let unfollow gone =
  let page = Web.document () in
  let gone r = gone r || not (Web.contains page r) in
  following := without (fun (r, stop) -> gone r && (stop (); true)) !following;
  broken := without gone !broken;
  report ()

let break root =
  Array.iter (fun (id, html) -> Client.stop_within (Navigation_web.put root id html)) (Navigation_web.failed_views root);
  Navigation_web.fail_values root;
  Navigation_web.adopt_stylesheets ();
  broken := root :: !broken

let follow root place s =
  incr owners;
  let owner = !owners and live = ref true and place = ref place in
  let unlisten = ref ignore in
  let rec stop () =
    live := false;
    !unlisten ();
    following := without (fun (_, f) -> f == stop) !following;
    s.next <- ignore;
    s.cancel ();
    Navigation_web.hold root owner true
  in
  let put (id, html) =
    Client.stop_within (Navigation_web.put root id html);
    Navigation_web.adopt_stylesheets ()
  in
  List.iter put (List.rev s.parts);
  (match s.result with Some false -> break root | _ -> ());
  !place ();
  if Option.is_none s.result then begin
    Navigation_web.hold root owner false;
    following := (root, stop) :: !following;
    unlisten := Navigation_web.on_input (fun () -> place := ignore);
    s.next <-
      (fun p ->
        if !live then
          match p with
          | Some (("", _) as p) ->
              put p;
              !place ()
          | Some p ->
              put p;
              !place ();
              Navigation_web.hold root owner false;
              !start_islands ()
          | None ->
              !unlisten ();
              following := without (fun (_, f) -> f == stop) !following;
              (match s.result with Some false -> break root | _ -> ());
              Navigation_web.hold root owner true;
              !start_islands ();
              report ())
  end;
  report ()

let show ~dir ~push ~replace ~restore ~refresh url a =
  let final =
    match hash_of url with
    | "" -> a.final
    | h -> Navigation_web.no_hash a.final ^ h
  in
  match swappable a with
  | None -> assign ~replace final
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
                  direct = not replace;
                })
            :: !overlays;
        if replace || String.equal (Navigation_web.no_hash final) (Web.current_url ()) then begin
          Web.table_delete (scrolls ()) !current_key;
          Navigation_web.replace_entry key final
        end
        else Web.history_push_key key final;
        current_key := key;
        Navigation_stub.at := Web.history_at ()
      end;
      let gen = !nav in
      let apply () =
        if !nav = gen then begin
          let kept = if refresh then Navigation_web.hold_focus () else fun () -> false in
          loaded := Web.current_url ();
          shown_key := !current_key;
          Navigation_state.set None;
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
              target
            end
          in
          let root = Option.value target ~default:(Web.document ()) in
          unfollow (Web.contains root);
          let place =
            match (over, restore, hash_of final) with
            | true, _, _ -> ignore
            | false, Some y, _ -> fun () -> Navigation_web.scroll_to y
            | false, None, "" ->
                Navigation_web.scroll_to 0.;
                ignore
            | false, None, h -> fun () -> Navigation_web.scroll_to_hash h
          in
          (match a.stream with Some s -> follow root place s | None -> place ());
          !Platform.swapped target;
          !start_islands ();
          Navigation_web.live ();
          if not (kept ()) then Navigation_web.settle root (hash_of final) (not refresh)
        end
        else Option.iter (fun s -> s.cancel ()) a.stream
      in
      if !transitions_on then Navigation_web.transition dir apply else apply ()

let load ~overlay ~dir ~push ~replace ~restore ~refresh url =
  if not !started then assign ~replace url
  else begin
    cancel_pending ();
    !hover ();
    hover := ignore;
    incr nav;
    let gen = !nav in
    let apply = function
      | _ when !nav <> gen -> ()
      | Some a -> show ~dir ~push ~replace ~restore ~refresh url a
      | None -> assign ~replace url
    in
    let key = page_key url in
    take key;
    let fetch () =
      let controller = Navigation_web.new_controller () in
      let asked = !era and s = stream (fun () -> Navigation_web.abort controller) and cached = ref None in
      pending := Some controller;
      Navigation_web.fetch_page (url, keys (), "", false, controller, overlay)
        (fun final status header text streamed ->
          pending := None;
          let a = { final; status; header; text; stream = (if streamed then Some s else None) } in
          if max_age header > 0 && asked = !era then begin
            let e = { key; answer = Some a; waiters = []; controller; at = Navigation_web.now (); prefetched = false; overlay; warm = false } in
            s.cancel <- ignore;
            cached := Some e;
            add e;
            pump ()
          end;
          apply (Some a))
        (got s)
        (ended s (fun () -> Option.iter drop !cached))
        (fun () ->
          pending := None;
          assign ~replace url)
    in
    match if refresh then None else lookup overlay key with
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

let go ~replace ~keep_scroll ~refresh url =
  save_scroll ();
  load ~overlay:true ~dir:"push" ~push:true ~replace ~restore:(if keep_scroll then Some (Web.scroll_y ()) else None) ~refresh url

let navigate ~replace ~keep_scroll url = go ~replace ~keep_scroll ~refresh:false url
let refresh () = go ~replace:true ~keep_scroll:true ~refresh:true (Web.current_url ())

let back () =
  match showing () with
  | Some o when not o.direct ->
      if not (List.exists (fun check -> check o.url) !Navigation_stub.blocks) then begin
        save_scroll ();
        Navigation_state.set (Some { Navigation_state.url = o.url; from = !loaded; kind = `Push });
        load ~overlay:false ~dir:"back" ~push:true ~replace:false ~restore:None ~refresh:false o.url
      end
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
    Navigation_state.set None;
    Option.iter
      (fun o ->
        hide ();
        unfollow (fun _ -> false);
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
      ~dir ~push:false ~replace:false
      ~restore:(Some y) ~refresh:false (Web.current_url ())

let on_pagehide _ = if Option.is_none (showing ()) then Web.scroll_restoration "auto"

let handle e =
  match Navigation_web.event_type e with
  | "popstate" -> on_popstate e
  | "pagehide" -> on_pagehide e
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
  List.iter (fun (_, f) -> f ()) !following;
  broken := [];
  report ();
  started := false;
  Navigation_state.set None;
  start_islands := (fun () -> ());
  on_out ();
  !unwatch ();
  unwatch := ignore;
  !untrack ();
  untrack := ignore;
  incr nav;
  overlays := [];
  Array.iter (fun e -> Navigation_web.abort e.controller) (Web.table_values (cache ()));
  clear ();
  Platform.acted := ignore

let router : Types.router = { boot; navigate; refresh; prefetch; back; handle; stop }
