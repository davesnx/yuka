open Platform

let on_window name handler = Base.own (!platform.on_window name (fun e -> Scheduler.batch (fun () -> handler e)))
let navigate ?(replace = false) ?(keep_scroll = false) url =
  if Url.unsafe ~tag:"a" "href" url then Types.log "navigate" url else !platform.navigate ~replace ~keep_scroll url
let refresh () = !platform.refresh ()

let block check =
  let open Navigation_stub in
  let f target = check ~target in
  if List.is_empty !blocks then Web.add_listener (Web.window ()) "beforeunload" hold;
  blocks := f :: !blocks;
  Base.own (fun () ->
      blocks := List.filter (fun g -> g != f) !blocks;
      if List.is_empty !blocks then Web.remove_listener (Web.window ()) "beforeunload" hold)

let confirm message = Web.confirm message
let prefetch url = if Url.unsafe ~tag:"a" "href" url then Types.log "prefetch" url else Navigation_stub.prefetch url
let back () = match !Navigation_stub.router with Some r -> r.back () | None -> Web.history_back ()
let navigating : bool State.read = State.of_signal Navigation_state.navigating

type navigation = Navigation_state.navigation = {
  url : string;
  from : string;
  kind : [ `Push | `Replace | `Traverse | `Reload ];
}

let navigation : navigation option State.read = State.of_signal Navigation_state.navigation
let stream : [ `Filling | `Done | `Broken ] State.read = State.of_signal Navigation_state.stream

let replace_url url =
  if Url.unsafe ~tag:"a" "href" url || not (Web.same_origin url) then Types.log "replace_url" url
  else begin
    Web.history_replace_url url;
    loaded := Web.current_url ()
  end

let set_cookie ?max_age ?(path = "/") ?(same_site = `Lax) ?(secure = false) name value =
  Result.map Web.set_cookie
    (Cookie.header ~who:"Yuka.Browser.set_cookie" ?max_age ~path ~same_site
       ~secure:(secure || same_site = `None)
       ~http_only:false name value)

let focus id = Scheduler.after (fun () -> !platform.focus id)
let scroll_into_view id = Scheduler.after (fun () -> !platform.scroll_into_view id)
let on_frame handler =
  Base.own
    (Web.on_frame (fun time ->
         Base.in_frame := true;
         match Scheduler.batch (fun () -> handler time) with
         | () -> Base.in_frame := false
         | exception e ->
             Base.in_frame := false;
             raise e))
let on_visible id handler =
  match Web.element_by_id (Web.document ()) id with
  | Some element when Web.has_intersection_observer element ->
      Web.on_visible element (fun () -> Scheduler.batch handler)
  | _ -> ignore
let now () = Web.now ()
let count_elements selector = Array.length (Web.query_all (Web.document ()) selector)
