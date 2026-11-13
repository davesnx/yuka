open Platform

let on_window name handler = Base.own (!platform.on_window name (fun e -> Scheduler.batch (fun () -> handler e)))
let navigate url = if Url.unsafe ~tag:"a" "href" url then Types.log "navigate" url else !platform.navigate url
let navigating = Navigation_state.navigating

let replace_url url =
  if Url.unsafe ~tag:"a" "href" url || not (Web.same_origin url) then Types.log "replace_url" url
  else begin
    Web.history_replace_url url;
    loaded := Web.current_url ()
  end

let focus id = Scheduler.after (fun () -> !platform.focus id)
let scroll_into_view id = Scheduler.after (fun () -> !platform.scroll_into_view id)
let on_frame handler = Base.own (Web.on_frame (fun time -> Scheduler.batch (fun () -> handler time)))
let now () = Web.now ()
let count_elements selector = Array.length (Web.query_all (Web.document ()) selector)
