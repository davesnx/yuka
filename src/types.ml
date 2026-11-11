type server
type client
type event = Web.event
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
    | Catch of {
        children : unit -> node;
        fallback : error:string -> reset:(unit -> unit) -> node;
        client : Obj.t option -> node;
      }

  and slot = { content : node option; dom : Obj.t list ref }

  and template = {
    mutable shape : shape option;
    code : string;
    fixed_root : bool;
    clones : int;
    markup : string;
    plan : Template_build.plan;
    mutable in_html : cache;
    mutable in_svg : cache;
    mutable ops : op array;
  }

  and op =
    | Raw of string
    | Static_text of string
    | Child_part of int
    | Only_part of int
    | Open of string * fixed_attr list
    | Subtree of shape
    | Enter of string
    | Leave

  and shape = Template_build.shape =
    | Fixed_text of string
    | Fixed_element of { tag : string; attrs : fixed_attr list; children : shape list }
    | Part of int

  and fixed_attr = Template_build.fixed_attr = Fixed of string * string | Part_attr of int

  and part = Child of node | Attribute of attr | No_attribute

  and cache = Empty | Compiled of Web.node * compiled option

  and compiled = { root : Web.node; kid_svg : int; attr_svg : int }

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
        inside_island : bool;
      }
    | Pending_async of { id : string; async : Json.t Async.t }
    | Pending_answer of { key : string; answer : Json.t Async.t }

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
    mutable id_prefix : string;
    mutable entry : string option;
    mutable current : string option;
    mutable in_fill : bool;
    mutable answers : (string * Json.t option) list;
    mutable answered : string list;
    mutable select_value : string option;
    mutable form : (string * string * (string * string) list * (string option * string) list) option;
    mutable csrf : (unit -> string) option;
    mutable sheets : string list;
    mutable held : string list;
  }

  let snapshot s = { s with streaming = s.streaming }

  let restore s
      { streaming = _; islands_only = _; islands; asyncs; awaits; pending; preload;
        preloaded; depth; queued; id_prefix; entry; current; in_fill; select_value; answers; answered; form;
        csrf; sheets; held } =
    s.islands <- islands;
    s.asyncs <- asyncs;
    s.awaits <- awaits;
    s.pending <- pending;
    s.preload <- preload;
    s.preloaded <- preloaded;
    s.depth <- depth;
    s.queued <- queued;
    s.id_prefix <- id_prefix;
    s.entry <- entry;
    s.current <- current;
    s.in_fill <- in_fill;
    s.select_value <- select_value;
    s.answers <- answers;
    s.answered <- answered;
    s.form <- form;
    s.csrf <- csrf;
    s.sheets <- sheets;
    s.held <- held

let warned = ref false

let log name value =
  if Dev.on && not !warned then begin
    warned := true;
    Web.console_error ("yuka: blocked an unsafe URL in " ^ name ^ ": " ^ value)
  end

let current_session : session option ref = ref None
let log_error : (string -> unit) ref = ref (fun m -> prerr_endline m)
let reject_prefix = "yuka.reject:"

let rejection message =
  let n = String.length reject_prefix in
  if String.length message >= n && String.sub message 0 n = reject_prefix then
    Some (String.sub message n (String.length message - n))
  else None

let async_error id message =
  match rejection message with
  | Some shown -> shown
  | None ->
      !log_error ("async value " ^ id ^ " failed: " ^ message);
      "failed"

let async_source : (string -> Json.t Async.t) ref =
  ref (fun _ -> Async.failed "no async transport")
