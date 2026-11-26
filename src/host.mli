(* An element, or a node of any kind that the renderer walks and checks by nodeType. *)
type node = Web.DOM.element
type event = Web.DOM.event

(* Unchecked casts, for code that knows the node type from nodeType. *)
external as_element : 'a Web.DOM.node_like -> node = "%identity"
external as_elements : Web.DOM.node option -> node option = "%identity"
external as_data : 'a Web.DOM.node_like -> Web.DOM.characterData = "%identity"
external target_element : Web.DOM.eventTarget -> node = "%identity"
external as_window : node -> Web.DOM.window = "%identity"
type 'a promise

val in_browser : bool
val walk : node -> int array -> node array
val delete_between : node -> node -> node -> unit
val set_string : node -> string -> string -> unit
val set_bool : node -> string -> bool -> unit
val set_prop : 'o -> string -> 'a -> unit
val get_prop : 'o -> string -> 'a option
val set_flag : event -> string -> bool -> unit
val get_flag : event -> string -> bool option
val console_error : string -> unit
val console_warn : string -> unit
val console_info : string -> unit
val console_log : string -> unit
val console_debug : string -> unit
val exn_to_string : exn -> string
val encode_uri : string -> string
val encode_uri_component : string -> string option
val decode_uri_component : string -> string option
val encode_cookie_value : string -> string option
val fetch_post :
  string ->
  string ->
  (int -> string -> unit) ->
  (bool -> string -> unit) ->
  unit ->
  unit
val watch_added : (node array -> bool) -> unit -> unit
val navigate : bool -> string -> unit
val confirm : string -> bool
val focus : string -> unit
val focus_node : node -> unit
val scroll_into_view : string -> unit
val has_intersection_observer : node -> bool
val on_idle : (unit -> unit) -> unit -> unit
val on_frame : (float -> unit) -> unit -> unit
val now : unit -> float
val set_timeout : int -> (unit -> unit) -> unit -> unit
val microtask : (unit -> unit) -> unit
val form_values : event -> (string * string) array
val on_visible : node -> (unit -> unit) -> unit -> unit
val ready_state : unit -> string
val on_dom_ready : (unit -> unit) -> unit -> unit
val record_events : node -> (unit -> unit) * (unit -> unit)
val touched : node -> string -> int
val fire : node -> unit
val promise_map : ('a -> 'b) -> 'a promise -> 'b promise
val promise_then : ('a -> unit) -> (string -> unit) -> 'a promise -> unit

val current_url : unit -> string
val base : unit -> string
val local_url : string -> string
val same_origin : string -> bool
val fresh_key : unit -> string
val history_key : unit -> string
val history_replace_key : string -> unit
val history_push_key : string -> string -> unit
val scroll_y : unit -> float
val scroll_to : float -> unit
val scroll_box_to : float -> unit
val set_cookie : string -> unit
val history_at : unit -> int
val history_go : int -> unit
val history_back : unit -> unit
val history_replace_url : string -> unit
val scroll_restoration : string -> unit
val plain_click : event -> bool
val link_href : bool -> node -> string
val link : node -> node
val form_url : event -> string
type 'a table

val table : unit -> 'a table
val table_get : 'a table -> string -> 'a option
val table_set : 'a table -> string -> 'a -> unit
val table_has : 'a table -> string -> bool
val table_delete : 'a table -> string -> unit
val table_size : 'a table -> int
val table_values : 'a table -> 'a array
val table_clear : 'a table -> unit
val stored_scrolls : unit -> float table
val store_scrolls : float table -> unit

type ('k, 'v) keyed

val keyed : ('k -> 'k -> bool) -> ('k, 'v) keyed
val keyed_get : ('k, 'v) keyed -> 'k -> 'v option
val keyed_set : ('k, 'v) keyed -> 'k -> 'v -> unit
val keyed_size : ('k, 'v) keyed -> int
val keyed_keep : ('k, 'v) keyed -> ('v -> bool) -> unit
val keyed_clear : ('k, 'v) keyed -> unit

val shortest_float : float -> string
val parse_float : string -> float
val parse_int : string -> int option

type json =
  [ `Null
  | `Bool of bool
  | `Int of int
  | `Float of float
  | `String of string
  | `List of json list
  | `Assoc of (string * json) list ]

val parse_json : string -> (json, string) result

type socket

val socket_open : string -> (unit -> unit) -> (string -> unit) -> (int -> unit) -> socket
val socket_send : socket -> string -> unit
val socket_close : socket -> int -> unit
val live_url : unit -> string
val online : unit -> bool
val on_online : (unit -> unit) -> unit -> unit
val random : unit -> float
val nonce : unit -> string
val fetch_text : string -> (int -> string -> unit) -> (string -> unit) -> unit
val add_stylesheet : string -> unit
val read_file : string -> string option
(* The output buffer of the printer. *)
module Out : sig
  type t

  val create : int -> t
  val length : t -> int
  val clear : t -> unit
  val truncate : t -> int -> unit
  val add_char : t -> char -> unit
  val add_string : t -> string -> unit
  val add_substring : t -> string -> int -> int -> unit

  val add_escaped : t -> quote:bool -> string -> unit
  (** Escapes the ampersand and less-than, plus greater-than when not [quote] or the double quote when [quote]. *)

  val sub : t -> int -> int -> string
  val contents : t -> string
  val blit : t -> int -> bytes -> int -> int -> unit
end

val take_buffer : unit -> Out.t option
val give_buffer : Out.t -> unit
val take_bytes : int -> Bytes.t
val give_bytes : Bytes.t -> unit

type 'a local

val local : (unit -> 'a) -> 'a local
val local_get : 'a local -> 'a
val lowercase : string -> string
val skip_clean : string -> int -> int
val sub : string -> int -> int -> string
val of_char : char -> string
val refuse_url_name : string -> unit
val tree_digest : string -> string
