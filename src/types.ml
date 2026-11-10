type server
type client
type event
type trigger = [ `Idle | `Visible | `Interaction ]
type loading = [ `Load | trigger | `Lazy of trigger ]


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
    | Template of { template : template; parts : part array }
    | Each : {
        items : unit -> 'a list;
        key : 'a -> string;
        equal : 'a -> 'a -> bool;
        render : 'a -> node;
      }
        -> node

  and slot = { content : node option; dom : Obj.t list ref }

  and template = { shape : shape; mutable html : cache; mutable svg : cache }

  and shape =
    | Fixed_text of string
    | Fixed_element of { tag : string; attrs : fixed_attr list; children : shape list }
    | Part of int

  and fixed_attr = Fixed of string * string | Part_attr of int

  and part = Child of node | Attribute of attr | No_attribute

  and cache = ..

  and attr =
    | Static of string * string
    | Dynamic of string * (unit -> string option)
    | Handler of string * (event -> unit)

  type cache += Empty

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
        inside_island : bool;
      }
    | Pending_async of { id : string; async : Json.t Async.t }

  type session = {
    streaming : bool;
    mutable islands : int;
    mutable asyncs : int;
    mutable awaits : int;
    mutable pending : pending list;
    mutable preload : (string -> string option) option;
    mutable preloaded : string list;
    mutable depth : int;
    islands_only : bool;
    mutable queued : string list;
  }

let current_session : session option ref = ref None

let async_source : (string -> Json.t Async.t) ref =
  ref (fun _ -> Async.failed "no async transport")
