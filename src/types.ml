type server
type client
type event
type loading = [ `Load | `Idle | `Visible | `Interaction ]


  type node =
    | Text of string
    | Element of { tag : string; attrs : attr list; children : node list }
    | Fragment of node list
    | Hole of (unit -> node)
    | Island of {
        name : string;
        props : Json.t;
        render : unit -> node;
        loading : loading;
      }
    | Await : {
        async : 'a Async.t;
        loading : node;
        failed : string -> node;
        render : 'a -> node;
      }
        -> node
    | Slot of slot
    | Template of { id : string; node : node }
    | Each : {
        items : unit -> 'a list;
        key : 'a -> string;
        equal : 'a -> 'a -> bool;
        render : 'a -> node;
      }
        -> node

  and slot = { content : node option; dom : Obj.t list ref }

  and attr =
    | Static of string * string
    | Dynamic of string * (unit -> string option)
    | Handler of string * (event -> unit)

  type platform = {
    target_value : event -> string;
    target_checked : event -> bool;
    key : event -> string;
    meta_key : event -> bool;
    ctrl_key : event -> bool;
    prevent_default : event -> unit;
    on_window : string -> (event -> unit) -> unit -> unit;
    stop_propagation : event -> unit;
    target_tag : event -> string;
    shift_key : event -> bool;
    alt_key : event -> bool;
    navigate : string -> unit;
    focus : string -> unit;
    scroll_into_view : string -> unit;
  }

  type pending =
    | Pending_await of {
        id : string;
        subscribe : (unit -> unit) -> unit;
        fill : unit -> string;
        fill_failed : string -> string;
      }
    | Pending_async of { id : string; async : Json.t Async.t }

  type session = {
    streaming : bool;
    mutable islands : int;
    mutable asyncs : int;
    mutable awaits : int;
    mutable pending : pending list;
  }

let current_session : session option ref = ref None

let async_source : (string -> Json.t Async.t) ref =
  ref (fun _ -> Async.failed "no async transport")
