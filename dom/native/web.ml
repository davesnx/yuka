module Buffer = Stdlib.Buffer

type node = unit
type event = unit
type 'a promise = unit

let in_browser = false
let last_module_node = ref (-1)
let seal_states () = if !last_module_node < 0 then last_module_node := !Scheduler.ids

let check_state_write (n : Scheduler.node) =
  if n.id <= !last_module_node then
    invalid_arg
      "Yuka.State: a write to a State made at module level, before the first server render or request. The server process has one copy for every request. Create the State inside a component."

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
let client_x : event -> float = fun _ -> browser_only ()
let client_y : event -> float = fun _ -> browser_only ()
let pointer_type : event -> string = fun _ -> browser_only ()
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
let console_warn : string -> unit = fun _ -> browser_only ()
let console_info : string -> unit = fun _ -> browser_only ()
let console_log : string -> unit = fun _ -> browser_only ()
let console_debug : string -> unit = fun _ -> browser_only ()
let exn_to_string = Printexc.to_string
let encode_uri : string -> string = fun _ -> browser_only ()
let decode_uri s =
  let n = String.length s and out = Buffer.create (String.length s) and run = Buffer.create 4 in
  let hex i =
    if i >= n then -1
    else match s.[i] with '0' .. '9' as c -> Char.code c - 48 | 'a' .. 'f' as c -> Char.code c - 87 | 'A' .. 'F' as c -> Char.code c - 55 | _ -> -1
  in
  let rec go i =
    if i < n && s.[i] = '%' then
      let h = hex (i + 1) and l = hex (i + 2) in
      h >= 0 && l >= 0
      && begin
           Buffer.add_char run (Char.chr ((h * 16) + l));
           go (i + 3)
         end
    else
      String.is_valid_utf_8 (Buffer.contents run)
      && begin
           Buffer.add_buffer out run;
           Buffer.clear run;
           i = n || (Buffer.add_char out s.[i]; go (i + 1))
         end
  in
  if go 0 then Some (Buffer.contents out) else None
let contains : node -> node -> bool = fun _ _ -> browser_only ()
let fetch_post : string -> string -> (int -> string -> unit) -> (bool -> string -> unit) -> unit -> unit = fun _ _ _ _ _ -> browser_only ()
let watch_added : (node array -> bool) -> unit -> unit = fun _ _ -> browser_only ()
let navigate : string -> unit = fun _ -> browser_only ()
let focus : string -> unit = fun _ -> browser_only ()
let scroll_into_view : string -> unit = fun _ -> browser_only ()
let has_intersection_observer : node -> bool = fun _ -> browser_only ()
let on_idle : (unit -> unit) -> unit -> unit = fun _ _ -> browser_only ()
let on_frame : (float -> unit) -> unit -> unit = fun _ _ -> browser_only ()
let now : unit -> float = fun () -> browser_only ()
let set_timeout : int -> (unit -> unit) -> unit -> unit = fun _ _ () -> ()
let microtask f = f ()
let form_values : event -> (string * string) array = fun _ -> browser_only ()
let on_visible : node -> (unit -> unit) -> unit -> unit = fun _ _ _ -> browser_only ()
let ready_state : unit -> string = fun _ -> browser_only ()
let on_dom_ready : (unit -> unit) -> unit -> unit = fun _ _ -> browser_only ()
let record_events : node -> (unit -> unit) * (unit -> unit) = fun _ -> browser_only ()
let touched : node -> string -> int = fun _ _ -> browser_only ()
let fire : node -> unit = fun _ -> browser_only ()
let promise_map : ('a -> 'b) -> 'a promise -> 'b promise = fun _ _ -> browser_only ()
let promise_then : ('a -> unit) -> (string -> unit) -> 'a promise -> unit = fun _ _ _ -> browser_only ()

let location_assign : string -> unit = fun _ -> browser_only ()
let current_url : unit -> string = fun _ -> browser_only ()
let same_origin : string -> bool = fun _ -> browser_only ()
let fresh_key : unit -> string = fun _ -> browser_only ()
let history_key : unit -> string = fun _ -> browser_only ()
let history_replace_key : string -> unit = fun _ -> browser_only ()
let history_replace_url : string -> unit = fun _ -> browser_only ()
let manual_scroll : unit -> unit = fun _ -> browser_only ()
let plain_click : event -> bool = fun _ -> browser_only ()
let link_href : bool -> node -> string = fun _ _ -> browser_only ()
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

type json =
  [ `Null
  | `Bool of bool
  | `Int of int
  | `Float of float
  | `String of string
  | `List of json list
  | `Assoc of (string * json) list ]

exception Parse of string

let add_utf8 b cp =
  let c x = Buffer.add_char b (Char.chr x) in
  if cp < 0x80 then c cp
  else if cp < 0x800 then (
    c (0xC0 lor (cp lsr 6));
    c (0x80 lor (cp land 0x3F)))
  else if cp < 0x10000 then (
    c (0xE0 lor (cp lsr 12));
    c (0x80 lor ((cp lsr 6) land 0x3F));
    c (0x80 lor (cp land 0x3F)))
  else (
    c (0xF0 lor (cp lsr 18));
    c (0x80 lor ((cp lsr 12) land 0x3F));
    c (0x80 lor ((cp lsr 6) land 0x3F));
    c (0x80 lor (cp land 0x3F)))

let max_depth = 512

let parse_json s =
  let n = String.length s in
  let i = ref 0 in
  let fail msg = raise (Parse (msg ^ " at " ^ string_of_int !i)) in
  let peek () = if !i < n then s.[!i] else '\000' in
  let rec ws () =
    if !i < n && (match s.[!i] with ' ' | '\t' | '\n' | '\r' -> true | _ -> false)
    then (incr i; ws ())
  in
  let expect c =
    if !i < n && s.[!i] = c then incr i
    else fail ("expected '" ^ String.make 1 c ^ "'")
  in
  let literal word v =
    let l = String.length word in
    if !i + l <= n && String.sub s !i l = word then (i := !i + l; v)
    else fail "invalid literal"
  in
  let hex4 () =
    if !i + 4 > n then fail "short \\u escape";
    let v = ref 0 in
    for k = 0 to 3 do
      let d =
        match s.[!i + k] with
        | '0' .. '9' as c -> Char.code c - 48
        | 'a' .. 'f' as c -> Char.code c - 87
        | 'A' .. 'F' as c -> Char.code c - 55
        | _ -> fail "invalid \\u escape"
      in
      v := (!v * 16) + d
    done;
    i := !i + 4;
    !v
  in
  let parse_string () =
    expect '"';
    let b = Buffer.create 16 in
    let rec loop () =
      if !i >= n then fail "unterminated string";
      match s.[!i] with
      | '"' -> incr i
      | '\\' ->
          incr i;
          if !i >= n then fail "unterminated string";
          let c = s.[!i] in
          incr i;
          (match c with
          | '"' -> Buffer.add_char b '"'
          | '\\' -> Buffer.add_char b '\\'
          | '/' -> Buffer.add_char b '/'
          | 'b' -> Buffer.add_char b '\b'
          | 'f' -> Buffer.add_char b '\012'
          | 'n' -> Buffer.add_char b '\n'
          | 'r' -> Buffer.add_char b '\r'
          | 't' -> Buffer.add_char b '\t'
          | 'u' ->
              let hi = hex4 () in
              if hi >= 0xD800 && hi <= 0xDBFF then (
                if !i + 2 <= n && s.[!i] = '\\' && s.[!i + 1] = 'u' then (
                  i := !i + 2;
                  let lo = hex4 () in
                  if lo >= 0xDC00 && lo <= 0xDFFF then
                    add_utf8 b (0x10000 + ((hi - 0xD800) lsl 10) + (lo - 0xDC00))
                  else fail "invalid surrogate pair")
                else fail "lone surrogate")
              else if hi >= 0xDC00 && hi <= 0xDFFF then fail "lone surrogate"
              else add_utf8 b hi
          | _ -> fail "invalid escape");
          loop ()
      | c when Char.code c < 32 -> fail "control character in string"
      | c ->
          Buffer.add_char b c;
          incr i;
          loop ()
    in
    loop ();
    Buffer.contents b
  in
  let digits () =
    let start = !i in
    while !i < n && s.[!i] >= '0' && s.[!i] <= '9' do incr i done;
    if !i = start then fail "digit expected"
  in
  let parse_number () =
    let start = !i in
    if peek () = '-' then incr i;
    if peek () = '0' then incr i else digits ();
    let is_float = ref false in
    if peek () = '.' then (is_float := true; incr i; digits ());
    if peek () = 'e' || peek () = 'E' then (
      is_float := true;
      incr i;
      if peek () = '+' || peek () = '-' then incr i;
      digits ());
    let text = String.sub s start (!i - start) in
    if !is_float then `Float (parse_float text)
    else
      match parse_int text with
      | Some v -> `Int v
      | None -> `Float (parse_float text)
  in
  let rec value depth : json =
    ws ();
    if !i >= n then fail "unexpected end";
    match s.[!i] with
    | 'n' -> literal "null" `Null
    | 't' -> literal "true" (`Bool true)
    | 'f' -> literal "false" (`Bool false)
    | '"' -> `String (parse_string ())
    | '[' ->
        if depth > max_depth then fail "nesting too deep";
        incr i;
        ws ();
        if peek () = ']' then (incr i; `List [])
        else
          let rec items acc =
            let v = value (depth + 1) in
            ws ();
            match peek () with
            | ',' -> incr i; items (v :: acc)
            | ']' -> incr i; `List (List.rev (v :: acc))
            | _ -> fail "expected ',' or ']'"
          in
          items []
    | '{' ->
        if depth > max_depth then fail "nesting too deep";
        incr i;
        ws ();
        if peek () = '}' then (incr i; `Assoc [])
        else
          let rec fields acc =
            ws ();
            let k = parse_string () in
            ws ();
            expect ':';
            let v = value (depth + 1) in
            ws ();
            match peek () with
            | ',' -> incr i; fields ((k, v) :: acc)
            | '}' -> incr i; `Assoc (List.rev ((k, v) :: acc))
            | _ -> fail "expected ',' or '}'"
          in
          fields []
    | '-' | '0' .. '9' -> parse_number ()
    | _ -> fail "unexpected character"
  in
  match
    let v = value 1 in
    ws ();
    if !i < n then fail "trailing characters";
    v
  with
  | v -> Ok v
  | exception Parse m -> Error m

type socket = unit

let socket_open : string -> (unit -> unit) -> (string -> unit) -> (int -> unit) -> socket =
 fun _ _ _ _ -> browser_only ()

let socket_send : socket -> string -> unit = fun _ _ -> browser_only ()
let socket_close : socket -> int -> unit = fun _ _ -> browser_only ()
let live_url : unit -> string = fun _ -> browser_only ()
let online : unit -> bool = fun _ -> browser_only ()
let on_online : (unit -> unit) -> unit -> unit = fun _ _ -> browser_only ()
let random : unit -> float = fun () -> Random.float 1.

let nonce () =
  let r = Random.State.make_self_init () in
  let part () = string_of_int (Random.State.bits r) in
  part () ^ "." ^ part () ^ "." ^ part ()
let fetch_text : string -> (int -> string -> unit) -> (string -> unit) -> unit = fun _ _ _ -> browser_only ()
let add_stylesheet : string -> unit = fun _ -> browser_only ()
let read_file path = try Some (In_channel.with_open_bin path In_channel.input_all) with Sys_error _ -> None

let buffers : Stdlib.Buffer.t list ref = ref []
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
let sub = String.sub
let of_char c = String.make 1 c
let refuse_url_name name =
  let bad c = c <= ' ' || c = '\127' || c = '"' || c = '\'' || c = '>' || c = '/' || c = '=' || c = '<' in
  match String.lowercase_ascii name with
  | "" | "href" | "src" | "action" | "formaction" | "xlink:href" | "xlinkhref" | "poster" | "cite" | "data"
  | "background" | "longdesc" | "manifest" | "codebase" | "icon" | "srcdoc" ->
      invalid_arg ("Yuka: refused attribute name " ^ name)
  | _ when String.exists bad name || String.starts_with ~prefix:"on" (String.lowercase_ascii name) -> invalid_arg ("Yuka: refused attribute name " ^ name)
  | _ -> ()
