type node
type event = Types.event
type 'a promise

val in_browser : bool
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
val encode_uri : string -> string
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
val on_visible : node -> (unit -> unit) -> unit -> unit
val ready_state : unit -> string
val on_dom_ready : (unit -> unit) -> unit -> unit
val record_events : node -> (unit -> unit) * (unit -> unit)
val promise_map : ('a -> 'b) -> 'a promise -> 'b promise
val promise_then : ('a -> unit) -> (string -> unit) -> 'a promise -> unit

type controller

val location_assign : string -> unit
val current_url : unit -> string
val scroll_y : unit -> float
val scroll_to : float -> unit
val scroll_to_hash : string -> unit
val fresh_key : unit -> string
val history_key : unit -> string
val history_replace_key : string -> unit
val history_push_key : string -> string -> unit
val manual_scroll : unit -> unit
val new_controller : unit -> controller
val abort : controller -> unit
val click_href : event -> string
val fetch_page :
  string -> controller -> (string -> string -> unit) -> (unit -> unit) -> unit
val swap_page : string -> unit
