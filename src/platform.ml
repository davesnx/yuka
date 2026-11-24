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

let target e = Host.target_element (Web.DOM.Event.target e)

let platform =
  ref
    {
      target_value = (fun e -> Web.DOM.HTMLInputElement.value (target e));
      target_checked = (fun e -> Web.DOM.HTMLInputElement.checked (target e));
      key = (fun e -> Web.DOM.KeyboardEvent.key e);
      meta_key = (fun e -> Web.DOM.MouseEvent.metaKey e);
      ctrl_key = (fun e -> Web.DOM.MouseEvent.ctrlKey e);
      prevent_default = (fun e -> Web.DOM.Event.preventDefault e);
      stop_propagation =
        (fun e ->
          Host.set_flag e stopped_key true;
          Web.DOM.Event.stopPropagation e);
      target_tag = (fun e -> Web.DOM.Element.localName (target e));
      shift_key = (fun e -> Web.DOM.MouseEvent.shiftKey e);
      alt_key = (fun e -> Web.DOM.MouseEvent.altKey e);
      client_x = (fun e -> Web.DOM.MouseEvent.clientX e);
      client_y = (fun e -> Web.DOM.MouseEvent.clientY e);
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
