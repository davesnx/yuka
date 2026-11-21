open Types

let stopped_key = "__yuka_stopped"
let acted : ((string * Json.t) list -> unit) ref = ref ignore
let live_mark : ((string * Json.t) list -> unit) ref = ref ignore
let client_navigate : (string -> unit) option ref = ref None
let loaded = ref ""
let no_swap (_ : Web.node option) = ()
let swapped = ref no_swap
let cleared : (unit -> unit) ref = ref ignore
let kept : string list ref = ref []
let moved : (unit -> unit) ref = ref ignore

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
      client_x = Web.client_x;
      client_y = Web.client_y;
      navigate = (fun url -> match !client_navigate with Some f -> f url | None -> Web.navigate url);
      focus = Web.focus;
      scroll_into_view = Web.scroll_into_view;
      on_window =
        (fun name handler ->
          Web.add_listener (Web.window ()) name handler;
          fun () -> Web.remove_listener (Web.window ()) name handler);
    }
