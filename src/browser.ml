open Platform

let on_window name handler = Base.own (!platform.on_window name (fun e -> Scheduler.batch (fun () -> handler e)))
let navigate url = if Url.unsafe ~tag:"a" "href" url then Types.log "navigate" url else !platform.navigate url
let navigating = Navigation_state.navigating
let focus id = Scheduler.after (fun () -> !platform.focus id)
let scroll_into_view id = Scheduler.after (fun () -> !platform.scroll_into_view id)
