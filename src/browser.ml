open Platform

let on_window name handler = Base.own (!platform.on_window name (fun e -> Scheduler.batch (fun () -> handler e)))
let navigate url = if Url.unsafe ~tag:"a" "href" url then Types.log "navigate" url else !platform.navigate url
let back () = match !Navigation_stub.router with Some r -> r.back () | None -> Web.history_back ()
let navigating : bool State.read = State.of_signal Navigation_state.navigating

let replace_url url =
  if Url.unsafe ~tag:"a" "href" url || not (Web.same_origin url) then Types.log "replace_url" url
  else begin
    Web.history_replace_url url;
    loaded := Web.current_url ()
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
    match Web.encode_cookie_value value with
    | None -> Error "Yuka.Browser.set_cookie: invalid value, not valid UTF-16"
    | Some encoded ->
        let attribute = function
          | Some text -> "; " ^ text
          | None -> ""
        in
        Web.set_cookie
          (name ^ "=" ^ encoded ^ "; Path=" ^ path
          ^ attribute (Option.map (fun seconds -> "Max-Age=" ^ string_of_int seconds) max_age)
          ^ (match same_site with `Lax -> "; SameSite=Lax" | `Strict -> "; SameSite=Strict" | `None -> "; SameSite=None")
          ^ if secure || same_site = `None then "; Secure" else "");
        Ok ()

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
let now () = Web.now ()

let title text =
  let before = ref None and shown = ref None in
  Base.Effect.after (fun () ->
      let t = text () in
      if Option.is_none !before then before := Some (Web.title ());
      shown := Some t;
      Web.set_title t);
  Base.own (fun () ->
      match (!before, !shown) with
      | Some b, Some s when String.equal (Web.title ()) s -> Web.set_title b
      | _ -> ())
let count_elements selector = Array.length (Web.query_all (Web.document ()) selector)
