open Web

type controller = unit

let browser_only () = failwith "Yuka: browser only"
let set_title : string -> unit = fun _ -> browser_only ()
let scroll_y : unit -> float = fun _ -> browser_only ()
let scroll_to : float -> unit = fun _ -> browser_only ()
let scroll_to_hash : string -> unit = fun _ -> browser_only ()
let history_push_key : string -> string -> unit = fun _ _ -> browser_only ()
let new_controller : unit -> controller = fun _ -> browser_only ()
let abort : controller -> unit = fun _ -> browser_only ()
let fetch_page :
    string * string * string * bool * controller -> (string -> int -> (string -> string option) -> string -> unit) -> (unit -> unit) -> unit =
 fun _ _ _ -> browser_only ()
let hash_of : string -> string = fun _ -> browser_only ()
let no_hash : string -> string = fun _ -> browser_only ()
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
let observe : node array -> (node -> bool -> (unit -> unit) -> unit) -> unit -> unit = fun _ _ -> browser_only ()
let warm : string -> string -> unit = fun _ _ -> browser_only ()
let transition : string -> (unit -> unit) -> unit = fun _ _ -> browser_only ()
let swap_page : string -> unit = fun _ -> browser_only ()
let adopt_stylesheets : unit -> unit = fun _ -> browser_only ()
