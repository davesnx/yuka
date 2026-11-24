open Platform

let on_window name handler = Base.own (!platform.on_window name (fun e -> Scheduler.batch (fun () -> handler e)))
let navigate ?(replace = false) ?(keep_scroll = false) url =
  if Url.unsafe ~tag:"a" "href" url then Types.log "navigate" url else !platform.navigate ~replace ~keep_scroll url
let refresh () = !platform.refresh ()

let block check =
  let open Navigation_stub in
  let f target = check ~target in
  if List.is_empty !blocks then Host.add_listener (Host.window ()) "beforeunload" hold;
  blocks := f :: !blocks;
  Base.own (fun () ->
      blocks := List.filter (fun g -> g != f) !blocks;
      if List.is_empty !blocks then Host.remove_listener (Host.window ()) "beforeunload" hold)

let confirm message = Host.confirm message
let prefetch url = if Url.unsafe ~tag:"a" "href" url then Types.log "prefetch" url else Navigation_stub.prefetch url
let back () = match !Navigation_stub.router with Some r -> r.back () | None -> Host.history_back ()
let navigating : bool State.read = State.of_signal Navigation_state.navigating

type navigation = Navigation_state.navigation = {
  url : string;
  from : string;
  kind : [ `Push | `Replace | `Traverse | `Reload ];
}

let navigation : navigation option State.read = State.of_signal Navigation_state.navigation
let stream : [ `Filling | `Done | `Broken ] State.read = State.of_signal Navigation_state.stream

let replace_url url =
  if Url.unsafe ~tag:"a" "href" url || not (Host.same_origin url) then Types.log "replace_url" url
  else begin
    Host.history_replace_url url;
    loaded := Host.current_url ()
  end

let cookie_name name =
  name <> ""
  && String.for_all
       (function
         | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '!' | '#' | '$' | '%' | '&' | '\'' | '*' | '+' | '-' | '.' | '^' | '_'
         | '`' | '|' | '~' ->
             true
         | _ -> false)
       name

let set_cookie ?max_age ?(path = "/") ?(same_site = `Lax) ?(secure = false) name value =
  if not (cookie_name name) then Error ("Yuka.Browser.set_cookie: invalid cookie name " ^ name)
  else if path = "" || path.[0] <> '/' || String.exists (fun c -> c = ';' || Char.code c < 32 || Char.code c = 127) path
  then Error ("Yuka.Browser.set_cookie: invalid path " ^ path)
  else
    match Host.encode_cookie_value value with
    | None -> Error "Yuka.Browser.set_cookie: invalid value, not valid UTF-16"
    | Some encoded ->
        let attribute = function
          | Some text -> "; " ^ text
          | None -> ""
        in
        Host.set_cookie
          (name ^ "=" ^ encoded ^ "; Path=" ^ path
          ^ attribute (Option.map (fun seconds -> "Max-Age=" ^ string_of_int seconds) max_age)
          ^ (match same_site with `Lax -> "; SameSite=Lax" | `Strict -> "; SameSite=Strict" | `None -> "; SameSite=None")
          ^ if secure || same_site = `None then "; Secure" else "");
        Ok ()

let focus id = Scheduler.after (fun () -> !platform.focus id)
let scroll_into_view id = Scheduler.after (fun () -> !platform.scroll_into_view id)
let on_frame handler =
  Base.own
    (Host.on_frame (fun time ->
         Base.in_frame := true;
         match Scheduler.batch (fun () -> handler time) with
         | () -> Base.in_frame := false
         | exception e ->
             Base.in_frame := false;
             raise e))
let on_visible id handler =
  match Host.element_by_id (Host.document ()) id with
  | Some element when Host.has_intersection_observer element ->
      Host.on_visible element (fun () -> Scheduler.batch handler)
  | _ -> ignore
let now () = Host.now ()
let count_elements selector = Array.length (Host.query_all (Host.document ()) selector)
