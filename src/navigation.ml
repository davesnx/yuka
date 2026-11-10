let started = ref false
let listening : Web.node option ref = ref None
let pending : Web.controller option ref = ref None
let scroll_table : float Web.table option ref = ref None

let scrolls () =
  match !scroll_table with
  | Some t -> t
  | None ->
      let t = Web.table () in
      scroll_table := Some t;
      t

let current_key = ref ""
let loaded = ref ""
let start_islands : (unit -> unit) ref = ref (fun () -> ())

let cancel_pending () =
  match !pending with
  | Some c ->
      pending := None;
      Web.abort c
  | None -> ()

let save_scroll () = Web.table_set (scrolls ()) !current_key (Web.scroll_y ())

let hash_of url =
  match String.index_opt url '#' with
  | Some i -> String.sub url i (String.length url - i)
  | None -> ""

let outlets () = Web.query_all (Web.document ()) "yuka-outlet"

let keys () =
  match List.filter_map (fun o -> Web.get_attribute o "data-k") (Array.to_list (outlets ())) with
  | [] -> "-"
  | keys -> String.concat " " keys

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
        match (Web.get_attribute a "href" = Some path, Web.get_attribute a "aria-current") with
        | true, None -> Web.set_attribute a "aria-current" "page"
        | false, Some "page" -> Web.remove_attribute a "aria-current"
        | _ -> ())
    (Web.query_all doc "a")

let outlet header =
  Option.map
    (fun key -> Array.find_opt (fun o -> Web.get_attribute o "data-k" = Some key) (outlets ()))
    (header "yuka-outlet")

let swap target final header text =
  match target with
  | Some el ->
      let title =
        Option.map (fun t -> try Web.decode_uri t with _ -> t) (header "yuka-title")
      in
      Client.stop_within el;
      Web.set_inner_html el text;
      Web.adopt_stylesheets ();
      Option.iter Web.set_title title;
      mark_links el (fst (Router.split_target final))
  | None ->
      Client.stop ();
      Web.swap_page text;
      Web.adopt_stylesheets ()

let html header =
  match header "content-type" with
  | Some t -> String.starts_with ~prefix:"text/html" (String.lowercase_ascii t)
  | None -> false

type answer = { final : string; status : int; header : string -> string option; text : string }

type entry = {
  key : string;
  mutable answer : answer option;
  mutable waiters : (answer option -> unit) list;
  controller : Web.controller;
  mutable at : float;
  prefetched : bool;
}

let cache_table : entry Web.table option ref = ref None

let cache () =
  match !cache_table with
  | Some t -> t
  | None ->
      let t = Web.table () in
      cache_table := Some t;
      t

let max_age header = Web.max_age (Option.value (header "cache-control") ~default:"")

let drop e =
  match Web.table_get (cache ()) e.key with
  | Some x when x == e -> Web.table_delete (cache ()) e.key
  | _ -> ()

let discard e =
  drop e;
  match (e.answer, e.waiters) with None, [] -> Web.abort e.controller | _ -> ()

let era = ref 0

let lookup key =
  match Web.table_get (cache ()) key with
  | Some e -> (
      match e.answer with
      | None -> Some e
      | Some a ->
          let age = Web.now () -. e.at and n = max_age a.header in
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

let page_key url = Web.absolute url ^ " " ^ keys ()

let prefetching : [ `Hover | `Visible | `Off ] ref = ref `Hover
let transitions_on = ref false
let nav = ref 0
let hover = ref ignore

let prefetch url =
  if !started && (match !prefetching with `Off -> false | _ -> true) && not (Web.save_data ()) then begin
    let key = page_key url in
    if Option.is_none (lookup key) then begin
      let e =
        { key; answer = None; waiters = []; controller = Web.new_controller (); at = 0.;
          prefetched = true }
      in
      add e;
      let settle a =
        let w = e.waiters in
        e.waiters <- [];
        List.iter (fun f -> f a) (List.rev w)
      in
      Web.fetch_page url (keys ()) true e.controller
        (fun final status header text ->
          e.at <- Web.now ();
          e.answer <- Some { final; status; header; text };
          settle e.answer)
        (fun () ->
          drop e;
          settle None)
    end
  end

let show ~dir ~push ~restore url a =
  let final =
    match (hash_of url, String.index_opt a.final '#') with
    | "", _ -> a.final
    | h, Some i -> String.sub a.final 0 i ^ h
    | h, None -> a.final ^ h
  in
  let stale = match a.header "yuka-build" with Some b -> build () <> Some b | None -> false in
  let shown = (a.status >= 200 && a.status < 300) || a.status >= 400 in
  match outlet a.header with
  | Some None -> Web.location_assign final
  | _ when stale || (not shown) || not (html a.header) -> Web.location_assign final
  | target ->
      if push then begin
        let key = Web.fresh_key () in
        Web.history_push_key key final;
        current_key := key
      end;
      loaded := Web.current_url ();
      let apply () =
        swap (Option.join target) final a.header a.text;
        (match restore with
        | Some y -> Web.scroll_to y
        | None -> Web.scroll_to_hash (hash_of final));
        !start_islands ()
      in
      if !transitions_on then Web.transition dir apply else apply ()

let load ~dir ~push ~restore url =
  if not !started then Web.location_assign url
  else begin
    cancel_pending ();
    !hover ();
    hover := ignore;
    incr nav;
    let gen = !nav in
    let apply = function
      | _ when !nav <> gen -> ()
      | Some a -> show ~dir ~push ~restore url a
      | None -> Web.location_assign url
    in
    let key = page_key url in
    match lookup key with
    | Some e -> (
        let use a =
          (match a with Some a when max_age a.header = 0 -> drop e | _ -> ());
          apply a
        in
        match e.answer with
        | Some _ -> use e.answer
        | None -> e.waiters <- use :: e.waiters)
    | None ->
        let controller = Web.new_controller () in
        let asked = !era in
        pending := Some controller;
        Web.fetch_page url (keys ()) false controller
          (fun final status header text ->
            pending := None;
            let a = { final; status; header; text } in
            if max_age header > 0 && asked = !era then
              add { key; answer = Some a; waiters = []; controller; at = Web.now (); prefetched = false };
            apply (Some a))
          (fun () ->
            pending := None;
            Web.location_assign url)
  end

let navigate url =
  save_scroll ();
  load ~dir:"push" ~push:true ~restore:None url

let on_click e =
  if Web.plain_click e then
    match Web.link_href false (Web.target e) with
    | "" -> ()
    | href ->
        Web.prevent_default e;
        navigate href

let on_over e =
  match Web.link_href true (Web.target e) with
  | "" -> ()
  | href ->
      !hover ();
      hover := Web.after 50 (fun () -> prefetch href)

let on_out _ =
  !hover ();
  hover := ignore

let on_touch e =
  match Web.link_href true (Web.target e) with "" -> () | href -> prefetch href

let on_down e = if Web.plain_click e then on_touch e

let unwatch = ref ignore

let watch () =
  !unwatch ();
  unwatch := ignore;
  match !prefetching with
  | `Off -> ()
  | mode ->
    unwatch :=
      Web.observe
        (Web.query_all (Web.document ())
           (match mode with `Visible -> "a[href]" | _ -> "a[data-yuka-prefetch=visible]"))
        (fun a -> match Web.link_href true a with "" -> () | href -> prefetch href)

let clear () =
  incr era;
  Array.iter discard (Web.table_values (cache ()));
  Web.table_clear (cache ())

let prefetch_events =
  [ ("pointerover", on_over); ("focusin", on_over); ("pointerout", on_out); ("focusout", on_out);
    ("pointerdown", on_down); ("touchstart", on_touch) ]

let on_popstate _ =
  save_scroll ();
  let next = Web.history_key () in
  let dir = if Web.key_before next !current_key then "back" else "forward" in
  current_key := next;
  let y = Option.value (Web.table_get (scrolls ()) !current_key) ~default:0. in
  if Web.current_url () = !loaded then begin
    cancel_pending ();
    incr nav;
    Web.scroll_to y
  end
  else load ~dir ~push:false ~restore:(Some y) (Web.current_url ())

let start ?lazy_entries ?(prefetch = `Hover) ?(transitions = false) entries =
  cancel_pending ();
  started := true;
  prefetching := prefetch;
  transitions_on := transitions;
  Platform.acted := clear;
  clear ();
  Web.manual_scroll ();
  current_key := Web.history_key ();
  if !current_key = "" then begin
    current_key := Web.fresh_key ();
    Web.history_replace_key !current_key
  end;
  loaded := Web.current_url ();
  let doc = Web.document () in
  (match !listening with
  | Some d when d == doc -> ()
  | _ ->
      listening := Some doc;
      Web.add_listener doc "click" on_click;
      List.iter (fun (n, f) -> Web.add_listener doc n f) prefetch_events;
      Web.add_listener (Web.window ()) "popstate" on_popstate);
  (start_islands :=
     fun () ->
       Client.start ?lazy_entries entries;
       Platform.platform := { !Platform.platform with navigate };
       watch ());
  !start_islands ()

let stop () =
  cancel_pending ();
  started := false;
  (match !listening with
  | Some doc ->
      listening := None;
      Web.remove_listener doc "click" on_click;
      List.iter (fun (n, f) -> Web.remove_listener doc n f) prefetch_events;
      Web.remove_listener (Web.window ()) "popstate" on_popstate
  | None -> ());
  start_islands := (fun () -> ());
  on_out ();
  !unwatch ();
  unwatch := ignore;
  incr nav;
  Array.iter (fun e -> if Option.is_none e.answer then Web.abort e.controller) (Web.table_values (cache ()));
  clear ();
  Platform.acted := ignore;
  if !Platform.platform.navigate == navigate then
    Platform.platform := { !Platform.platform with navigate = Web.navigate };
  Client.stop ()
