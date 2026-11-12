type server
type client
type event = Web.event
type trigger = [ `Idle | `Visible | `Interaction ]
type start = [ `Load | trigger | `Lazy of trigger ]


  type node =
    | Text of string
    | Element of { tag : string; attrs : attr list; children : node list }
    | Fragment of node list
    | Hole of (unit -> node)
    | Island of {
        name : string;
        props : Json.t;
        render : unit -> node;
        start : start;
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
        items : unit -> 'a array;
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

  type context = {
    meth : Router.meth;
    path : string;
    header : string -> string option;
    session : unit -> string option;
    log : string -> unit;
    live : string -> Json.t -> (Json.t, Status_error.t) result Async.t;
  }

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
    mutable context : context option;
  }

  let snapshot s = { s with streaming = s.streaming }

  let restore s
      { streaming = _; islands_only = _; islands; asyncs; awaits; pending; preload;
        preloaded; depth; queued; id_prefix; entry; current; in_fill; select_value; answers; answered; form;
        csrf; sheets; held; context } =
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
    s.held <- held;
    s.context <- context

let warned = ref false

let log name value =
  if Dev.on && not !warned then begin
    warned := true;
    Web.console_error ("yuka: blocked an unsafe URL in " ^ name ^ ": " ^ value)
  end

let current_session : session option ref = ref None

let default_log : (string -> unit) ref = ref prerr_endline

let log_in session message =
  match session with Some { context = Some c; _ } -> c.log message | _ -> !default_log message

let log_message message = log_in !current_session message

let reject_prefix = lazy ("yuka.reject." ^ Web.nonce () ^ ":")

let reject message = Lazy.force reject_prefix ^ message

let rejection message =
  let prefix = Lazy.force reject_prefix in
  let n = String.length prefix in
  if String.length message >= n && String.sub message 0 n = prefix then
    Some (String.sub message n (String.length message - n))
  else None

let shown ?(session = !current_session) what message =
  match rejection message with
  | Some m -> m
  | None ->
      log_in session (what ^ " failed: " ^ message);
      "server error"

let async_error ?session id message = shown ?session ("async value " ^ id) message

let transport : (string -> Json.t -> (Json.t, Status_error.t) result Async.t) ref =
  ref (fun _ _ -> Async.return (Error (Status_error.Network "no action transport")))

let async_source : (string -> Json.t Async.t) ref =
  ref (fun _ -> Async.failed "no async transport")
