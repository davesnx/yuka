open Types

let current_key = ref ""
let shown_key = ref ""

let table r =
  match !r with
  | Some t -> t
  | None ->
      let t = Host.table () in
      r := Some t;
      t

let scroll_table : float Host.table option ref = ref None
let save_scroll () =
  Host.scroll_restoration "manual";
  Host.table_set (table scroll_table) !shown_key (Host.scroll_y ())

let loaded = Platform.loaded
let on = ref false
let router : router option ref = ref None
let loader : (unit -> router Host.promise) ref = ref (fun () -> failwith "Yuka: navigation is off")
let loading = ref false
let attempt = ref 0
let failed = ref false
let timer : (unit -> unit) option ref = ref None
let waiting : ((router -> unit) * (unit -> unit)) list ref = ref []
let settings = ref (false, ignore)
let listening : Web.DOM.document option ref = ref None
let link_events = [ "pointerover"; "focusin"; "pointerdown"; "touchstart" ]
let leave_events = [ "pointerout"; "focusout" ]

let take () =
  let w = List.rev !waiting in
  waiting := [];
  w

let rec cancel () =
  match !timer with
  | Some c ->
      timer := None;
      c ();
      Web.DOM.Window.removeEventListener "beforeunload" on_unload Web.DOM.window
  | None -> ()

and on_unload _ =
  waiting := [];
  Navigation_state.set None;
  cancel ()

let give_up message =
  cancel ();
  incr attempt;
  loading := false;
  if not !failed then begin
    failed := true;
    Host.console_error ("yuka: cannot load navigation: " ^ message)
  end;
  List.iter (fun (_, fail) -> fail ()) (take ())

let load () =
  if not !loading then begin
    loading := true;
    let a = !attempt in
    Host.promise_then
      (fun r ->
        if !attempt = a then begin
          cancel ();
          loading := false;
          let w = take () in
          match r.boot !settings with
          | () ->
              router := Some r;
              List.iter
                (fun (f, fail) ->
                  try f r
                  with e ->
                    Host.console_error ("yuka: navigation: " ^ Host.exn_to_string e);
                    fail ())
                w
          | exception e ->
              (try r.stop () with _ -> ());
              give_up (Host.exn_to_string e);
              List.iter (fun (_, fail) -> fail ()) w
        end)
      (fun message -> if !attempt = a then give_up message)
      (!loader ())
  end

let use f =
  match !router with
  | Some r -> f r
  | None ->
      if not !failed then begin
        waiting := (f, ignore) :: !waiting;
        load ()
      end

let go ?link kind url f fail =
  Navigation_state.set ?link (Some { Navigation_state.url; from = !loaded; kind });
  let fail () =
    Navigation_state.set None;
    fail ()
  in
  match !router with
  | Some r -> f r
  | None when !failed -> fail ()
  | None ->
      waiting := (f, fail) :: !waiting;
      if Option.is_none !timer then begin
        timer := Some (Host.set_timeout 3000 (fun () -> give_up "no answer in 3 s"));
        Web.DOM.Window.addEventListener "beforeunload" on_unload Web.DOM.window
      end;
      load ()

let blocks : (string -> bool) list ref = ref []
let hold = Web.DOM.Event.preventDefault

let target e = Host.target_element (Web.DOM.Event.target e)
let inside url = Option.is_some (Site.strip (Host.base ()) url)

let navigate ?link ~replace ~keep_scroll href =
  let url = Host.local_url href in
  if List.exists (fun check -> check url) !blocks then ()
  else if not (inside url) then Host.navigate replace href
  else
    go ?link
      (if replace || String.equal url (Host.current_url ()) then `Replace else `Push)
      url
      (fun r -> r.navigate ~replace ~keep_scroll href)
      (fun () -> Host.navigate replace href)

let refresh () = go `Reload (Host.current_url ()) (fun r -> r.refresh ()) Platform.reload

let prefetch url =
  if !on && Host.same_origin url && inside (Host.local_url url)
     && Array.length (Web.DOM.NodeList.toArray (Web.DOM.Document.querySelectorAll "meta[name=yuka-prefetch][content=off]" Web.DOM.document)) = 0
  then use (fun r -> r.prefetch url)

let on_click e =
  if (not !failed) && Host.plain_click e then
    match Host.link_href false (target e) with
    | "" -> ()
    | href ->
        let link = Host.link (target e) in
        let flag name = Option.is_some (Web.DOM.Element.getAttribute name link) in
        Web.DOM.Event.preventDefault e;
        navigate ~link ~replace:(flag "data-yuka-replace") ~keep_scroll:(flag "data-yuka-keep-scroll") href

let on_submit e =
  if not !failed then
    match Host.form_url e with
    | "" -> ()
    | href ->
        Web.DOM.Event.preventDefault e;
        navigate ~link:(target e) ~replace:false ~keep_scroll:false href

let on_link e =
  if Option.is_some !router || Host.link_href true (target e) <> "" then
    use (fun r -> r.handle e)

let rec on_move e =
  if Web.DOM.PointerEvent.pointerType e = "mouse" then begin
    Web.DOM.EventTarget.removeEventListener "pointermove" on_move Web.DOM.document;
    use ignore
  end

let on_leave e = if !loading || Option.is_some !router then use (fun r -> r.handle e)

let at = ref 0
let undo = ref None

let on_popstate e =
  let next = Host.history_at () and url = Host.current_url () in
  match !undo with
  | Some n when n = next -> undo := None
  | _ ->
      undo := None;
      if
        next <> !at && url <> !loaded
        && (not (List.exists (String.equal (Host.history_key ())) !Platform.kept))
        && List.exists (fun check -> check url) !blocks
      then begin
        undo := Some !at;
        Host.history_go (!at - next)
      end
      else begin
        at := next;
        go `Traverse url
          (fun r -> r.handle e)
          (fun () -> if Host.current_url () <> !loaded then Host.navigate false (Host.current_url ()))
      end

(* The browser restores the window scroll of a reload, or of a return from another document,
   before any script runs, also while a streamed page grows, but not the scroll of an element:
   [start] sets the element that scrolls the outlet. Client navigation sets [manual] again in
   [save_scroll], before each history change it makes. The router keeps [manual] while an
   overlay is shown, since the window then has the scroll of the page under it. *)
let on_pagehide e =
  Host.table_delete (table scroll_table) !shown_key;
  save_scroll ();
  Host.store_scrolls (table scroll_table);
  match !router with Some r -> r.handle e | None -> Host.scroll_restoration "auto"

let on_pageshow e = if Web.DOM.PageTransitionEvent.persisted e then Host.scroll_restoration "manual"

let start ~load ?lazy_entries ?(transitions = false) entries =
  on := true;
  failed := false;
  loader := load;
  let islands () = Client.start ?lazy_entries entries in
  settings := (transitions, islands);
  current_key := Host.history_key ();
  if !current_key = "" then begin
    current_key := Host.fresh_key ();
    Host.history_replace_key !current_key
  end;
  shown_key := !current_key;
  at := Host.history_at ();
  loaded := Host.current_url ();
  let doc = Web.DOM.document in
  (match !listening with
  | Some d when d == doc -> ()
  | _ ->
      listening := Some doc;
      Web.DOM.Window.addEventListener "click" on_click Web.DOM.window;
      List.iter (fun n -> Web.DOM.EventTarget.addEventListener n on_link doc) link_events;
      List.iter (fun n -> Web.DOM.EventTarget.addEventListener n on_leave doc) leave_events;
      Web.DOM.Window.addEventListener "submit" on_submit Web.DOM.window;
      Web.DOM.Window.addEventListener "popstate" on_popstate Web.DOM.window;
      Web.DOM.Window.addEventListener "pagehide" on_pagehide Web.DOM.window;
      Web.DOM.Window.addEventListener "pageshow" on_pageshow Web.DOM.window);
  islands ();
  (match !scroll_table with
  | None ->
      let t = Host.stored_scrolls () in
      scroll_table := Some t;
      Option.iter Host.scroll_box_to (Host.table_get t !shown_key)
  | Some _ -> ());
  Platform.client_navigate := Some (navigate ?link:None);
  Platform.client_refresh := refresh;
  match !router with
  | Some r -> r.boot !settings
  | None when Array.length (Web.DOM.NodeList.toArray (Web.DOM.Document.querySelectorAll "meta[name=yuka-prefetch][content=visible],meta[name=yuka-prefetch][content=idle]" doc)) > 0 ->
      use ignore
  | None when Array.length (Web.DOM.NodeList.toArray (Web.DOM.Document.querySelectorAll "meta[name=yuka-prefetch]" doc)) = 0 ->
      Web.DOM.EventTarget.addEventListener "pointermove" on_move doc
  | None -> ()

let stop () =
  Platform.client_navigate := None;
  Platform.client_refresh := Platform.reload;
  Navigation_state.set None;
  on := false;
  cancel ();
  incr attempt;
  loading := false;
  waiting := [];
  (match !listening with
  | Some doc ->
      listening := None;
      Web.DOM.Window.removeEventListener "click" on_click Web.DOM.window;
      List.iter (fun n -> Web.DOM.EventTarget.removeEventListener n on_link doc) link_events;
      List.iter (fun n -> Web.DOM.EventTarget.removeEventListener n on_leave doc) leave_events;
      Web.DOM.EventTarget.removeEventListener "pointermove" on_move doc;
      Web.DOM.Window.removeEventListener "submit" on_submit Web.DOM.window;
      Web.DOM.Window.removeEventListener "popstate" on_popstate Web.DOM.window;
      Web.DOM.Window.removeEventListener "pagehide" on_pagehide Web.DOM.window;
      Web.DOM.Window.removeEventListener "pageshow" on_pageshow Web.DOM.window
  | None -> ());
  Option.iter (fun r -> r.stop ()) !router;
  Client.stop ()
