open Types

let stopped_key = "__yuka_stopped"
let acted : (unit -> unit) ref = ref ignore
let live_mark : ((string * Json.t) list -> unit) ref = ref ignore
let client_navigate : (replace:bool -> keep_scroll:bool -> string -> unit) option ref = ref None
let reload () = Host.navigate true (Host.current_url ())
let client_refresh = ref reload
let loaded = ref ""
let no_swap (_ : Host.node option) = ()
let swapped = ref no_swap
let cleared : (unit -> unit) ref = ref ignore
let kept : string list ref = ref []
let moved : (unit -> unit) ref = ref ignore

let platform =
  ref
    {
      target_value = (fun e -> Host.value (Host.target e));
      target_checked = (fun e -> Host.checked (Host.target e));
      key = Host.key;
      meta_key = Host.meta_key;
      ctrl_key = Host.ctrl_key;
      prevent_default = Host.prevent_default;
      stop_propagation =
        (fun e ->
          Host.set_flag e stopped_key true;
          Host.stop_propagation e);
      target_tag = (fun e -> Web.DOM.Element.localName (Host.target e));
      shift_key = Host.shift_key;
      alt_key = Host.alt_key;
      client_x = Host.client_x;
      client_y = Host.client_y;
      navigate =
        (fun ~replace ~keep_scroll url ->
          match !client_navigate with Some f -> f ~replace ~keep_scroll url | None -> Host.navigate replace url);
      refresh = (fun () -> !client_refresh ());
      focus = Host.focus;
      scroll_into_view = Host.scroll_into_view;
      on_window =
        (fun name handler ->
          Web.DOM.Window.addEventListener name handler Web.DOM.window;
          fun () -> Web.DOM.Window.removeEventListener name handler Web.DOM.window);
    }
