open Web

type controller

val set_title : string -> unit
val scroll_y : unit -> float
val scroll_to : float -> unit
val scroll_to_hash : string -> unit
val history_push_key : string -> string -> unit
val new_controller : unit -> controller
val abort : controller -> unit
val fetch_page :
  string * string * string * bool * controller ->
  (string -> int -> (string -> string option) -> string -> unit) ->
  (unit -> unit) ->
  unit
val hash_of : string -> string
val no_hash : string -> string
val path_of : string -> string
val keys : unit -> string
val is_html : string -> bool
val event_type : event -> string
val swap_page : string -> unit
val absolute : string -> string
val max_age : string -> int
val key_before : string -> string -> bool
val now : unit -> float
val after : int -> (unit -> unit) -> unit -> unit
val save_data : unit -> bool
val observe : node array -> (node -> bool -> (unit -> unit) -> unit) -> unit -> unit
val warm : string -> string -> unit
val transition : string -> (unit -> unit) -> unit
val adopt_stylesheets : unit -> unit
