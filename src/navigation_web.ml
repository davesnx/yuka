open Host

type controller = unit

let browser_only () = invalid_arg "Yuka: browser only"
let set_title : string -> unit = fun _ -> browser_only ()
let title : unit -> string = fun _ -> browser_only ()
let active : unit -> node = fun _ -> browser_only ()
let refocus : node -> unit = fun _ -> browser_only ()
let route_script : unit -> (node * node) option = fun _ -> browser_only ()
let put_back : node * node -> unit = fun _ -> browser_only ()
let layer : unit -> node = fun _ -> browser_only ()
let scroll_to = Host.scroll_to
let scroll_to_hash : string -> unit = fun _ -> browser_only ()
let new_controller : unit -> controller = fun _ -> browser_only ()
let abort : controller -> unit = fun _ -> browser_only ()
let fetch_page :
    string * string * string * bool * controller * bool ->
    (string -> int -> (string -> string option) -> string -> bool -> unit) ->
    (string -> string -> unit) ->
    (bool -> unit) ->
    (unit -> unit) ->
    unit =
 fun _ _ _ _ _ -> browser_only ()
let put : node -> string -> string -> node = fun _ _ _ -> browser_only ()
let failed_views : node -> (string * string) array = fun _ -> browser_only ()
let fail_values : node -> unit = fun _ -> browser_only ()
let hold : node -> int -> bool -> unit = fun _ _ _ -> browser_only ()
let hash_of : string -> string = fun _ -> browser_only ()
let no_hash : string -> string = fun _ -> browser_only ()
let replace_entry : string -> string -> unit = fun _ _ -> browser_only ()
let path_of : string -> string = fun _ -> browser_only ()
let keys : unit -> string = fun _ -> browser_only ()
let is_html : string -> bool = fun _ -> browser_only ()
let event_type : event -> string = fun _ -> browser_only ()
let absolute : string -> string = fun _ -> browser_only ()
let max_age : string -> int = fun _ -> browser_only ()
let key_before : string -> string -> bool = fun _ _ -> browser_only ()
let now : unit -> float = fun _ -> browser_only ()
let after : int -> (unit -> unit) -> unit -> unit = fun _ _ -> browser_only ()
let save_data : unit -> bool = fun _ -> browser_only ()
let hidden_or_slow : unit -> bool = fun _ -> browser_only ()
let on_visible : (unit -> unit) -> unit -> unit = fun _ _ -> browser_only ()
let on_input : (unit -> unit) -> unit -> unit = fun _ _ -> browser_only ()
let observe : node array -> (node -> bool -> (unit -> unit) -> unit) -> unit -> unit = fun _ _ -> browser_only ()
let trajectory : (node -> string) -> (string -> unit) -> unit -> unit = fun _ _ -> browser_only ()
let warm : string -> string -> unit = fun _ _ -> browser_only ()
let transition : string -> (unit -> unit) -> unit = fun _ _ -> browser_only ()
let swap_page : string -> unit = fun _ -> browser_only ()
let adopt_stylesheets : unit -> unit = fun _ -> browser_only ()
let live : unit -> unit = fun _ -> browser_only ()
let settle : node -> string -> bool -> unit = fun _ _ _ -> browser_only ()
let hold_focus : unit -> unit -> bool = fun _ -> browser_only ()
