type node = unit
type event = unit
type 'a promise = unit

let in_browser = false

let browser_only () = failwith "Yuka: browser only"

let window : unit -> node = fun _ -> browser_only ()
let document : unit -> node = fun _ -> browser_only ()
let owner_document : node -> node = fun _ -> browser_only ()
let create_element : node -> string -> node = fun _ _ -> browser_only ()
let create_element_ns : node -> string -> string -> node = fun _ _ _ -> browser_only ()
let create_text : node -> string -> node = fun _ _ -> browser_only ()
let create_comment : node -> string -> node = fun _ _ -> browser_only ()
let node_type : node -> int = fun _ -> browser_only ()
let local_name : node -> string = fun _ -> browser_only ()
let data : node -> string = fun _ -> browser_only ()
let set_data : node -> string -> unit = fun _ _ -> browser_only ()
let first_child : node -> node option = fun _ -> browser_only ()
let next_sibling : node -> node option = fun _ -> browser_only ()
let parent_node : node -> node option = fun _ -> browser_only ()
let first_element_child : node -> node option = fun _ -> browser_only ()
let child_at : node -> int -> node = fun _ _ -> browser_only ()
let previous_sibling : node -> node option = fun _ -> browser_only ()
let last_child : node -> node option = fun _ -> browser_only ()
let clone_node : node -> bool -> node = fun _ _ -> browser_only ()
let walk : node -> int array -> node array = fun _ _ -> browser_only ()
let delete_between : node -> node -> node -> unit = fun _ _ _ -> browser_only ()
let append_child : node -> node -> unit = fun _ _ -> browser_only ()
let insert_before : node -> node -> node -> unit = fun _ _ _ -> browser_only ()
let remove : node -> unit = fun _ -> browser_only ()
let clear : node -> string -> unit = fun _ _ -> browser_only ()
let set_attribute : node -> string -> string -> unit = fun _ _ _ -> browser_only ()
let remove_attribute : node -> string -> unit = fun _ _ -> browser_only ()
let set_string : node -> string -> string -> unit = fun _ _ _ -> browser_only ()
let set_bool : node -> string -> bool -> unit = fun _ _ _ -> browser_only ()
let set_prop : node -> string -> 'a -> unit = fun _ _ _ -> browser_only ()
let get_prop : node -> string -> 'a option = fun _ _ -> browser_only ()
let add_listener : node -> string -> (event -> unit) -> unit = fun _ _ _ -> browser_only ()
let remove_listener : node -> string -> (event -> unit) -> unit = fun _ _ _ -> browser_only ()
let target : event -> node = fun _ -> browser_only ()
let value : node -> string = fun _ -> browser_only ()
let checked : node -> bool = fun _ -> browser_only ()
let key : event -> string = fun _ -> browser_only ()
let meta_key : event -> bool = fun _ -> browser_only ()
let ctrl_key : event -> bool = fun _ -> browser_only ()
let shift_key : event -> bool = fun _ -> browser_only ()
let alt_key : event -> bool = fun _ -> browser_only ()
let prevent_default : event -> unit = fun _ -> browser_only ()
let stop_propagation : event -> unit = fun _ -> browser_only ()
let set_flag : event -> string -> bool -> unit = fun _ _ _ -> browser_only ()
let get_flag : event -> string -> bool option = fun _ _ -> browser_only ()
let query_all : node -> string -> node array = fun _ _ -> browser_only ()
let get_attribute : node -> string -> string option = fun _ _ -> browser_only ()
let text_content : node -> string = fun _ -> browser_only ()
let set_inner_html : node -> string -> unit = fun _ _ -> browser_only ()
let content : node -> node = fun _ -> browser_only ()
let import_node : node -> node -> bool -> node = fun _ _ _ -> browser_only ()
let console_error : string -> unit = fun _ -> browser_only ()
let exn_to_string = Printexc.to_string
let encode_uri : string -> string = fun _ -> browser_only ()
let decode_uri : string -> string = fun _ -> browser_only ()
let contains : node -> node -> bool = fun _ _ -> browser_only ()
let set_title : string -> unit = fun _ -> browser_only ()
let fetch_post : string -> string -> (int -> string -> unit) -> (bool -> string -> unit) -> unit -> unit = fun _ _ _ _ _ -> browser_only ()
let watch_added : (node array -> bool) -> unit -> unit = fun _ _ -> browser_only ()
let navigate : string -> unit = fun _ -> browser_only ()
let focus : string -> unit = fun _ -> browser_only ()
let scroll_into_view : string -> unit = fun _ -> browser_only ()
let has_intersection_observer : node -> bool = fun _ -> browser_only ()
let on_idle : (unit -> unit) -> unit -> unit = fun _ _ -> browser_only ()
let set_timeout : int -> (unit -> unit) -> unit -> unit = fun _ _ () -> ()
let form_values : event -> (string * string) array = fun _ -> browser_only ()
let on_visible : node -> (unit -> unit) -> unit -> unit = fun _ _ _ -> browser_only ()
let ready_state : unit -> string = fun _ -> browser_only ()
let on_dom_ready : (unit -> unit) -> unit -> unit = fun _ _ -> browser_only ()
let record_events : node -> (unit -> unit) * (unit -> unit) = fun _ -> browser_only ()
let promise_map : ('a -> 'b) -> 'a promise -> 'b promise = fun _ _ -> browser_only ()
let promise_then : ('a -> unit) -> (string -> unit) -> 'a promise -> unit = fun _ _ _ -> browser_only ()

type controller = unit

let location_assign : string -> unit = fun _ -> browser_only ()
let current_url : unit -> string = fun _ -> browser_only ()
let scroll_y : unit -> float = fun _ -> browser_only ()
let scroll_to : float -> unit = fun _ -> browser_only ()
let scroll_to_hash : string -> unit = fun _ -> browser_only ()
let fresh_key : unit -> string = fun _ -> browser_only ()
let history_key : unit -> string = fun _ -> browser_only ()
let history_replace_key : string -> unit = fun _ -> browser_only ()
let history_push_key : string -> string -> unit = fun _ _ -> browser_only ()
let manual_scroll : unit -> unit = fun _ -> browser_only ()
let new_controller : unit -> controller = fun _ -> browser_only ()
let abort : controller -> unit = fun _ -> browser_only ()
let plain_click : event -> bool = fun _ -> browser_only ()
let link_href : bool -> node -> string = fun _ _ -> browser_only ()
let fetch_page :
    string -> string -> bool -> controller -> (string -> int -> (string -> string option) -> string -> unit) -> (unit -> unit) -> unit =
 fun _ _ _ _ _ _ -> browser_only ()
let absolute : string -> string = fun _ -> browser_only ()
let max_age : string -> int = fun _ -> browser_only ()
let key_before : string -> string -> bool = fun _ _ -> browser_only ()
let now : unit -> float = fun _ -> browser_only ()
let after : int -> (unit -> unit) -> unit -> unit = fun _ _ -> browser_only ()
let save_data : unit -> bool = fun _ -> browser_only ()
let observe : node array -> (node -> unit) -> unit -> unit = fun _ _ -> browser_only ()
let transition : string -> (unit -> unit) -> unit = fun _ _ -> browser_only ()
let swap_page : string -> unit = fun _ -> browser_only ()

type 'a table = (string, 'a) Hashtbl.t

let table () = Hashtbl.create 8
let table_get = Hashtbl.find_opt
let table_set = Hashtbl.replace
let table_has = Hashtbl.mem
let table_delete = Hashtbl.remove
let table_size = Hashtbl.length
let table_values t = Array.of_seq (Hashtbl.to_seq_values t)
let table_clear = Hashtbl.reset

let shortest_float f =
  let rec try_precision p =
    let s = Printf.sprintf "%.*g" p f in
    if p >= 17 || float_of_string s = f then s else try_precision (p + 1)
  in
  try_precision 15

let parse_float = float_of_string
let parse_int = int_of_string_opt

type socket = unit

let socket_open : string -> (unit -> unit) -> (string -> unit) -> (int -> unit) -> socket =
 fun _ _ _ _ -> browser_only ()

let socket_send : socket -> string -> unit = fun _ _ -> browser_only ()
let socket_close : socket -> int -> unit = fun _ _ -> browser_only ()
let live_url : unit -> string = fun _ -> browser_only ()
let online : unit -> bool = fun _ -> browser_only ()
let on_online : (unit -> unit) -> unit -> unit = fun _ _ -> browser_only ()
let random : unit -> float = fun () -> Random.float 1.
let fetch_text : string -> (int -> string -> unit) -> (string -> unit) -> unit = fun _ _ _ -> browser_only ()
let add_stylesheet : string -> unit = fun _ -> browser_only ()
let adopt_stylesheets : unit -> unit = fun _ -> browser_only ()
let read_file path = try Some (In_channel.with_open_bin path In_channel.input_all) with Sys_error _ -> None

let buffers : Buffer.t list ref = ref []
let buffers_lock = Mutex.create ()

let take_buffer () =
  Mutex.protect buffers_lock (fun () ->
      match !buffers with
      | b :: rest ->
          buffers := rest;
          Some b
      | [] -> None)

let give_buffer b = Mutex.protect buffers_lock (fun () -> buffers := b :: !buffers)
let lowercase = String.lowercase_ascii
let refuse_url_name name =
  let bad c = c <= ' ' || c = '\127' || c = '"' || c = '\'' || c = '>' || c = '/' || c = '=' || c = '<' in
  match String.lowercase_ascii name with
  | "" | "href" | "src" | "action" | "formaction" | "xlink:href" | "xlinkhref" | "poster" | "cite" | "data"
  | "background" | "longdesc" | "manifest" | "codebase" | "icon" | "srcdoc" ->
      invalid_arg ("Yuka: refused attribute name " ^ name)
  | _ when String.exists bad name || String.starts_with ~prefix:"on" (String.lowercase_ascii name) -> invalid_arg ("Yuka: refused attribute name " ^ name)
  | _ -> ()
