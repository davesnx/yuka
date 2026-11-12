open Types

let current_key = ref ""
let loaded = ref ""
let on = ref false
let router : router option ref = ref None
let loader : (unit -> router Web.promise) ref = ref (fun () -> failwith "Yuka: navigation is off")
let loading = ref false
let failed = ref false
let waiting : ((router -> unit) * (unit -> unit)) list ref = ref []
let settings = ref (`Hover, false, ignore)
let listening : Web.node option ref = ref None
let link_events = [ "pointerover"; "focusin"; "pointerdown"; "touchstart" ]
let leave_events = [ "pointerout"; "focusout" ]

let take () =
  let w = List.rev !waiting in
  waiting := [];
  w

let give_up message =
  if not !failed then begin
    failed := true;
    loading := false;
    Web.console_error ("yuka: cannot load navigation: " ^ message);
    List.iter (fun (_, fail) -> fail ()) (take ())
  end

let use f fail =
  match !router with
  | Some r -> f r
  | None when !failed -> fail ()
  | None ->
      waiting := (f, fail) :: !waiting;
      if not !loading then begin
        loading := true;
        let (_ : unit -> unit) =
          Web.set_timeout 3000 (fun () -> if !loading then give_up "no answer in 3 s")
        in
        Web.promise_then
          (fun r ->
            if not !failed then begin
              loading := false;
              router := Some r;
              let w = take () in
              if !on then
                match r.boot !settings with
                | () ->
                    List.iter
                      (fun (f, fail) ->
                        try f r
                        with e ->
                          Web.console_error ("yuka: navigation: " ^ Web.exn_to_string e);
                          fail ())
                      w
                | exception e ->
                    router := None;
                    give_up (Web.exn_to_string e);
                    List.iter (fun (_, fail) -> fail ()) w
            end)
          give_up (!loader ())
      end

let navigate href = use (fun r -> r.navigate href) (fun () -> Web.location_assign href)

let on_click e =
  if (not !failed) && Web.plain_click e then
    match Web.link_href false (Web.target e) with
    | "" -> ()
    | href ->
        Web.prevent_default e;
        navigate href

let on_link e =
  if Option.is_some !router || Web.link_href true (Web.target e) <> "" then
    use (fun r -> r.handle e) ignore

let on_leave e = if !loading || Option.is_some !router then use (fun r -> r.handle e) ignore

let on_popstate e =
  use
    (fun r -> r.handle e)
    (fun () -> if Web.current_url () <> !loaded then Web.location_assign (Web.current_url ()))

let start ~load ?lazy_entries ?(prefetch = `Hover) ?(transitions = false) entries =
  on := true;
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
  | None, `Visible -> use ignore ignore
  | None, `Hover when Array.length (Web.query_all doc "a[data-yuka-prefetch=visible]") > 0 ->
      use ignore ignore
  | None, _ -> ()

let stop () =
  Platform.client_navigate := None;
  on := false;
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
