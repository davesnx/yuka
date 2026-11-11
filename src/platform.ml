open Types
open Base

let stopped_key = "__yuka_stopped"
let acted : (unit -> unit) ref = ref ignore
let live_mark : ((string * Json.t) list -> unit) ref = ref ignore

let platform =
  ref
    {
      target_value = (fun e -> Web.value (Web.target e));
      target_checked = (fun e -> Web.checked (Web.target e));
      key = Web.key;
      meta_key = Web.meta_key;
      ctrl_key = Web.ctrl_key;
      prevent_default = Web.prevent_default;
      stop_propagation =
        (fun e ->
          Web.set_flag e stopped_key true;
          Web.stop_propagation e);
      target_tag = (fun e -> Web.local_name (Web.target e));
      shift_key = Web.shift_key;
      alt_key = Web.alt_key;
      navigate = Web.navigate;
      focus = Web.focus;
      scroll_into_view = Web.scroll_into_view;
      on_window =
        (fun name handler ->
          Web.add_listener (Web.window ()) name handler;
          fun () -> Web.remove_listener (Web.window ()) name handler);
    }

module Event = struct
  type t = event

  let target_value e = !platform.target_value e
  let target_checked e = !platform.target_checked e
  let key e = !platform.key e
  let meta_key e = !platform.meta_key e
  let ctrl_key e = !platform.ctrl_key e
  let prevent_default e = !platform.prevent_default e
  let stop_propagation e = !platform.stop_propagation e
  let target_tag e = !platform.target_tag e
  let shift_key e = !platform.shift_key e
  let alt_key e = !platform.alt_key e
end

module Browser = struct
  let on_window name handler = own (!platform.on_window name handler)
  let navigate url = if Url.unsafe ~tag:"a" "href" url then Types.log "navigate" url else !platform.navigate url
  let focus id = !platform.focus id
  let scroll_into_view id = !platform.scroll_into_view id
end
