open Types

let current_key = ref ""
let loaded = Platform.loaded
let on = ref false
let router : router option ref = ref None
let loader : (unit -> router Web.promise) ref = ref (fun () -> failwith "Yuka: navigation is off")
let loading = ref false
let attempt = ref 0
let failed = ref false
let timer : (unit -> unit) option ref = ref None
let waiting : ((router -> unit) * (unit -> unit)) list ref = ref []
let settings = ref (`Hover, false, ignore)
let listening : Web.node option ref = ref None
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
      Web.remove_listener (Web.window ()) "beforeunload" on_unload
  | None -> ()

and on_unload _ =
  waiting := [];
  Navigation_state.set false;
  cancel ()

let give_up message =
  cancel ();
  incr attempt;
  loading := false;
  if not !failed then begin
    failed := true;
    Web.console_error ("yuka: cannot load navigation: " ^ message)
  end;
  List.iter (fun (_, fail) -> fail ()) (take ())

let load () =
  if not !loading then begin
    loading := true;
    let a = !attempt in
    Web.promise_then
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
                    Web.console_error ("yuka: navigation: " ^ Web.exn_to_string e);
                    fail ())
                w
          | exception e ->
              (try r.stop () with _ -> ());
              give_up (Web.exn_to_string e);
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

let go f fail =
  Navigation_state.set true;
  let fail () =
    Navigation_state.set false;
    fail ()
  in
  match !router with
  | Some r -> f r
  | None when !failed -> fail ()
  | None ->
      waiting := (f, fail) :: !waiting;
      if Option.is_none !timer then begin
        timer := Some (Web.set_timeout 3000 (fun () -> give_up "no answer in 3 s"));
        Web.add_listener (Web.window ()) "beforeunload" on_unload
      end;
      load ()

let navigate href = go (fun r -> r.navigate href) (fun () -> Web.location_assign href)

let on_click e =
  if (not !failed) && Web.plain_click e then
    match Web.link_href false (Web.target e) with
    | "" -> ()
    | href ->
        Web.prevent_default e;
        navigate href

let on_link e =
  if Option.is_some !router || Web.link_href true (Web.target e) <> "" then
    use (fun r -> r.handle e)

let on_leave e = if !loading || Option.is_some !router then use (fun r -> r.handle e)

let on_popstate e =
  go
    (fun r -> r.handle e)
    (fun () -> if Web.current_url () <> !loaded then Web.location_assign (Web.current_url ()))

let start ~load ?lazy_entries ?(prefetch = `Hover) ?(transitions = false) entries =
  on := true;
  failed := false;
  loader := load;
  let islands () = Client.start ?lazy_entries entries in
  settings := (prefetch, transitions, islands);
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
      List.iter (fun n -> Web.add_listener doc n on_link) link_events;
      List.iter (fun n -> Web.add_listener doc n on_leave) leave_events;
      Web.add_listener (Web.window ()) "popstate" on_popstate);
  islands ();
  Platform.client_navigate := Some navigate;
  match (!router, prefetch) with
  | Some r, _ -> r.boot !settings
  | None, `Visible -> use ignore
  | None, `Hover when Array.length (Web.query_all doc "a[data-yuka-prefetch=visible]") > 0 ->
      use ignore
  | None, _ -> ()

let stop () =
  Platform.client_navigate := None;
  Navigation_state.set false;
  on := false;
  cancel ();
  incr attempt;
  loading := false;
  waiting := [];
  (match !listening with
  | Some doc ->
      listening := None;
      Web.remove_listener doc "click" on_click;
      List.iter (fun n -> Web.remove_listener doc n on_link) link_events;
      List.iter (fun n -> Web.remove_listener doc n on_leave) leave_events;
      Web.remove_listener (Web.window ()) "popstate" on_popstate
  | None -> ());
  Option.iter (fun r -> r.stop ()) !router;
  Client.stop ()
