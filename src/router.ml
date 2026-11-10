open Tiny_hashtbl

type ('a, 'r) t =
  | Root : ('r, 'r) t
  | Lit : string -> ('r, 'r) t
  | Str : (string -> 'r, 'r) t
  | Int : (int -> 'r, 'r) t
  | Seq : ('a, 'b) t * ('b, 'c) t -> ('a, 'c) t

let root = Root

let s text =
  if text = "" || String.contains text '/' then invalid_arg "Yuka.Router.s";
  Lit text

let string = Str
let int = Int
let ( / ) a b = Seq (a, b)

let encode text =
  let b = Buffer.create (String.length text) in
  String.iter
    (function
      | ('A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '-' | '.' | '_' | '~') as c ->
          Buffer.add_char b c
      | c ->
          Buffer.add_string b
            (Tiny_printf.Printf.sprintf "%%%02X" (Char.code c)))
    text;
  Buffer.contents b

let hex = function
  | '0' .. '9' as c -> Some (Char.code c - 48)
  | 'a' .. 'f' as c -> Some (Char.code c - 87)
  | 'A' .. 'F' as c -> Some (Char.code c - 55)
  | _ -> None

let decode ~plus text =
  let n = String.length text in
  let b = Buffer.create n in
  let i = ref 0 in
  while !i < n do
    (match text.[!i] with
    | '%' when !i + 2 < n -> (
        match (hex text.[!i + 1], hex text.[!i + 2]) with
        | Some h, Some l ->
            Buffer.add_char b (Char.chr ((h * 16) + l));
            i := !i + 2
        | _ -> Buffer.add_char b '%')
    | '+' when plus -> Buffer.add_char b ' '
    | c -> Buffer.add_char b c);
    incr i
  done;
  Buffer.contents b

let rec build : type a r. (a, r) t -> string list -> (string list -> r) -> a =
 fun path acc k ->
  match path with
  | Root -> k acc
  | Lit text -> k (encode text :: acc)
  | Str -> fun v -> k (encode v :: acc)
  | Int -> fun v -> k (encode (string_of_int v) :: acc)
  | Seq (x, y) -> build x acc (fun acc -> build y acc k)

let href ?(query = []) path =
  build path [] (fun acc ->
      let p = match acc with [] -> "/" | _ -> "/" ^ String.concat "/" (List.rev acc) in
      match query with
      | [] -> p
      | _ ->
          p ^ "?"
          ^ String.concat "&"
              (List.map (fun (k, v) -> encode k ^ "=" ^ encode v) query))

let is_int text =
  let n = String.length text in
  let start = if n > 0 && text.[0] = '-' then 1 else 0 in
  n > start
  &&
  let ok = ref true in
  String.iteri (fun i c -> if i >= start && (c < '0' || c > '9') then ok := false) text;
  !ok

let rec walk : type a r. (a, r) t -> string list -> a -> (string list * r) option =
 fun path segs f ->
  match path with
  | Root -> Some (segs, f)
  | Lit text -> (
      match segs with
      | x :: rest when decode ~plus:false x = text -> Some (rest, f)
      | _ -> None)
  | Str -> (
      match segs with x :: rest -> Some (rest, f (decode ~plus:false x)) | [] -> None)
  | Int -> (
      match segs with
      | x :: rest when is_int x -> (
          match int_of_string_opt x with Some v -> Some (rest, f v) | None -> None)
      | _ -> None)
  | Seq (x, y) -> (
      match walk x segs f with Some (rest, g) -> walk y rest g | None -> None)

let cut text c =
  match String.index_opt text c with
  | Some i -> (String.sub text 0 i, Some (String.sub text (i + 1) (String.length text - i - 1)))
  | None -> (text, None)

let split_target target =
  let target, _ = cut target '#' in
  cut target '?'

let segments p =
  List.filter (fun x -> x <> "") (String.split_on_char '/' p)

let parse path f target =
  let p, _ = split_target target in
  match walk path (segments p) f with Some ([], r) -> Some r | _ -> None

let query target =
  match split_target target with
  | _, None | _, Some "" -> []
  | _, Some q ->
      List.filter_map
        (fun pair ->
          if pair = "" then None
          else
            let k, v = cut pair '=' in
            Some
              ( decode ~plus:true k,
                decode ~plus:true (Option.value v ~default:"") ))
        (String.split_on_char '&' q)

type 'r case = Case : ('a, 'r) t * 'a -> 'r case

let case path f = Case (path, f)

let rec dispatch cases target =
  match cases with
  | [] -> None
  | Case (path, f) :: rest -> (
      match parse path f target with Some _ as r -> r | None -> dispatch rest target)

let started = ref false
let listening : Web.node option ref = ref None
let pending : Web.controller option ref = ref None
let scrolls : (string, float) Hashtbl.t = Hashtbl.create 16
let current_key = ref ""
let loaded = ref ""
let start_islands : (unit -> unit) ref = ref (fun () -> ())

let cancel_pending () =
  match !pending with
  | Some c ->
      pending := None;
      Web.abort c
  | None -> ()

let save_scroll () = Hashtbl.replace scrolls !current_key (Web.scroll_y ())

let hash_of url =
  match String.index_opt url '#' with
  | Some i -> String.sub url i (String.length url - i)
  | None -> ""

let load ~push ~restore url =
  if not !started then Web.location_assign url
  else begin
    cancel_pending ();
    let controller = Web.new_controller () in
    pending := Some controller;
    Web.fetch_page url controller
      (fun final text ->
        pending := None;
        Client.stop ();
        Web.swap_page text;
        if push then begin
          let key = Web.fresh_key () in
          Web.history_push_key key final;
          current_key := key
        end;
        loaded := Web.current_url ();
        (match restore with
        | Some y -> Web.scroll_to y
        | None -> Web.scroll_to_hash (hash_of final));
        !start_islands ())
      (fun () ->
        pending := None;
        Web.location_assign url)
  end

let navigate url =
  save_scroll ();
  load ~push:true ~restore:None url

let on_click e =
  match Web.click_href e with
  | "" -> ()
  | href ->
      Web.prevent_default e;
      navigate href

let on_popstate _ =
  save_scroll ();
  current_key := Web.history_key ();
  let y = Option.value (Hashtbl.find_opt scrolls !current_key) ~default:0. in
  if Web.current_url () = !loaded then begin
    cancel_pending ();
    Web.scroll_to y
  end
  else load ~push:false ~restore:(Some y) (Web.current_url ())

let start ?lazy_entries entries =
  cancel_pending ();
  started := true;
  Web.manual_scroll ();
  current_key := Web.history_key ();
  if !current_key = "" then begin
    current_key := Web.fresh_key ();
    Web.history_replace_key !current_key
  end;
  loaded := Web.current_url ();
  let doc = Web.document () in
  (match !listening with
  | Some d when d == doc -> ()
  | _ ->
      listening := Some doc;
      Web.add_listener doc "click" on_click;
      Web.add_listener (Web.window ()) "popstate" on_popstate);
  (start_islands :=
     fun () ->
       Client.start ?lazy_entries entries;
       Platform.platform := { !Platform.platform with navigate });
  !start_islands ()
