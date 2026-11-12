type node
type event
type 'a promise

val in_browser : bool
val check_state_write : Scheduler.node -> unit
val seal_states : unit -> unit
val window : unit -> node
val document : unit -> node
val owner_document : node -> node
val create_element : node -> string -> node
val create_element_ns : node -> string -> string -> node
val create_text : node -> string -> node
val create_comment : node -> string -> node
val node_type : node -> int
val local_name : node -> string
val data : node -> string
val set_data : node -> string -> unit
val first_child : node -> node option
val next_sibling : node -> node option
val parent_node : node -> node option
val first_element_child : node -> node option
val child_at : node -> int -> node
val previous_sibling : node -> node option
val last_child : node -> node option
val clone_node : node -> bool -> node
val walk : node -> int array -> node array
val delete_between : node -> node -> node -> unit
val append_child : node -> node -> unit
val insert_before : node -> node -> node -> unit
val remove : node -> unit
val clear : node -> string -> unit
val set_attribute : node -> string -> string -> unit
val remove_attribute : node -> string -> unit
val set_string : node -> string -> string -> unit
val set_bool : node -> string -> bool -> unit
val set_prop : node -> string -> 'a -> unit
val get_prop : node -> string -> 'a option
val add_listener : node -> string -> (event -> unit) -> unit
val remove_listener : node -> string -> (event -> unit) -> unit
val target : event -> node
val value : node -> string
val checked : node -> bool
val key : event -> string
val meta_key : event -> bool
val ctrl_key : event -> bool
val shift_key : event -> bool
val alt_key : event -> bool
val prevent_default : event -> unit
val stop_propagation : event -> unit
val set_flag : event -> string -> bool -> unit
val get_flag : event -> string -> bool option
val query_all : node -> string -> node array
val get_attribute : node -> string -> string option
val text_content : node -> string
val set_inner_html : node -> string -> unit
val content : node -> node
val import_node : node -> node -> bool -> node
val console_error : string -> unit
val console_warn : string -> unit
val console_info : string -> unit
val console_log : string -> unit
val console_debug : string -> unit
val exn_to_string : exn -> string
val encode_uri : string -> string
val decode_uri : string -> string
val contains : node -> node -> bool
val fetch_post :
  string ->
  string ->
  (int -> string -> unit) ->
  (bool -> string -> unit) ->
  unit ->
  unit
val watch_added : (node array -> bool) -> unit -> unit
val navigate : string -> unit
val focus : string -> unit
val scroll_into_view : string -> unit
val has_intersection_observer : node -> bool
val on_idle : (unit -> unit) -> unit -> unit
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

val location_assign : string -> unit
val current_url : unit -> string
val same_origin : string -> bool
val fresh_key : unit -> string
val history_key : unit -> string
val history_replace_key : string -> unit
val manual_scroll : unit -> unit
val plain_click : event -> bool
val link_href : bool -> node -> string
type 'a table

val table : unit -> 'a table
val table_get : 'a table -> string -> 'a option
val table_set : 'a table -> string -> 'a -> unit
val table_has : 'a table -> string -> bool
val table_delete : 'a table -> string -> unit
val table_size : 'a table -> int
val table_values : 'a table -> 'a array
val table_clear : 'a table -> unit

val shortest_float : float -> string
val parse_float : string -> float
val parse_int : string -> int option

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
val take_buffer : unit -> Buffer.t option
val give_buffer : Buffer.t -> unit
val lowercase : string -> string
val refuse_url_name : string -> unit
