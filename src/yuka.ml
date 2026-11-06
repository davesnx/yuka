module Json = struct
  type t =
    [ `Null
    | `Bool of bool
    | `Int of int
    | `Float of float
    | `String of string
    | `List of t list
    | `Assoc of (string * t) list ]

  let add_string b s =
    Buffer.add_char b '"';
    String.iter
      (function
        | '"' -> Buffer.add_string b "\\\""
        | '\\' -> Buffer.add_string b "\\\\"
        | '\n' -> Buffer.add_string b "\\n"
        | '\r' -> Buffer.add_string b "\\r"
        | '\t' -> Buffer.add_string b "\\t"
        | '\b' -> Buffer.add_string b "\\b"
        | '\012' -> Buffer.add_string b "\\f"
        | ('<' | '\000' .. '\031') as c ->
            Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
        | c -> Buffer.add_char b c)
      s;
    Buffer.add_char b '"'

  let float_repr f =
    if Float.is_nan f || Float.abs f = Float.infinity then "null"
    else
      let rec try_precision p =
        let s = Printf.sprintf "%.*g" p f in
        if p >= 17 || float_of_string s = f then s else try_precision (p + 1)
      in
      let s = try_precision 15 in
      if String.contains s '.' || String.contains s 'e' || String.contains s 'E'
      then s
      else s ^ ".0"

  let to_string (v : t) =
    let b = Buffer.create 64 in
    let rec go : t -> unit = function
      | `Null -> Buffer.add_string b "null"
      | `Bool true -> Buffer.add_string b "true"
      | `Bool false -> Buffer.add_string b "false"
      | `Int i -> Buffer.add_string b (string_of_int i)
      | `Float f -> Buffer.add_string b (float_repr f)
      | `String s -> add_string b s
      | `List l ->
          Buffer.add_char b '[';
          List.iteri
            (fun i x ->
              if i > 0 then Buffer.add_char b ',';
              go x)
            l;
          Buffer.add_char b ']'
      | `Assoc l ->
          Buffer.add_char b '{';
          List.iteri
            (fun i (k, x) ->
              if i > 0 then Buffer.add_char b ',';
              add_string b k;
              Buffer.add_char b ':';
              go x)
            l;
          Buffer.add_char b '}'
    in
    go v;
    Buffer.contents b

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

  let of_string s =
    let n = String.length s in
    let i = ref 0 in
    let fail msg = raise (Parse (Printf.sprintf "%s at %d" msg !i)) in
    let peek () = if !i < n then s.[!i] else '\000' in
    let rec ws () =
      if !i < n && (match s.[!i] with ' ' | '\t' | '\n' | '\r' -> true | _ -> false)
      then (incr i; ws ())
    in
    let expect c =
      if !i < n && s.[!i] = c then incr i
      else fail (Printf.sprintf "expected %C" c)
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
      if !is_float then `Float (float_of_string text)
      else
        match int_of_string_opt text with
        | Some v -> `Int v
        | None -> `Float (float_of_string text)
    in
    let rec value () : t =
      ws ();
      if !i >= n then fail "unexpected end";
      match s.[!i] with
      | 'n' -> literal "null" `Null
      | 't' -> literal "true" (`Bool true)
      | 'f' -> literal "false" (`Bool false)
      | '"' -> `String (parse_string ())
      | '[' ->
          incr i;
          ws ();
          if peek () = ']' then (incr i; `List [])
          else
            let rec items acc =
              let v = value () in
              ws ();
              match peek () with
              | ',' -> incr i; items (v :: acc)
              | ']' -> incr i; `List (List.rev (v :: acc))
              | _ -> fail "expected ',' or ']'"
            in
            items []
      | '{' ->
          incr i;
          ws ();
          if peek () = '}' then (incr i; `Assoc [])
          else
            let rec fields acc =
              ws ();
              let k = parse_string () in
              ws ();
              expect ':';
              let v = value () in
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
      let v = value () in
      ws ();
      if !i < n then fail "trailing characters";
      v
    with
    | v -> Ok v
    | exception Parse m -> Error m
end

type owner = { mutable next : int; disposers : (int, unit -> unit) Hashtbl.t }

let current_owner : owner option ref = ref None
let new_owner () = { next = 0; disposers = Hashtbl.create 8 }

let add_disposer o dispose =
  o.next <- o.next + 1;
  Hashtbl.replace o.disposers o.next dispose;
  o.next

let own dispose =
  match !current_owner with
  | Some o -> ignore (add_disposer o dispose)
  | None -> ()

let with_owner o f =
  let prev = !current_owner in
  current_owner := Some o;
  match f () with
  | result ->
      current_owner := prev;
      result
  | exception e ->
      current_owner := prev;
      raise e

let dispose_owner o =
  let all = Hashtbl.fold (fun id dispose acc -> (id, dispose) :: acc) o.disposers [] in
  Hashtbl.reset o.disposers;
  List.iter
    (fun (_, dispose) -> dispose ())
    (List.sort (fun (a, _) (b, _) -> compare b a) all)

let mount f =
  let o = new_owner () in
  let result = with_owner o f in
  (result, fun () -> dispose_owner o)

module State = struct
  type 'a t = 'a Signal.t

  let make = Signal.make
  let get = Signal.get
  let peek = Signal.peek
  let set = Signal.set
  let update = Signal.update

  let memo ?equal f =
    let s = Signal.computed ?equal f in
    own (fun () -> Signal.dispose_computed s);
    s
end

let server_rendering = ref false

module Effect = struct
  let run ?cleanup body =
    if !server_rendering then () else
    let child = new_owner () in
    let last = ref None in
    let teardown () =
      dispose_owner child;
      match !last with
      | None -> ()
      | Some result ->
          last := None;
          Option.iter (fun cleanup -> cleanup result) cleanup
    in
    let node =
      Core.make_effect_node (fun () ->
          teardown ();
          last := Some (with_owner child body))
    in
    let stop () =
      node.run <- None;
      teardown ();
      Core.clear_deps node
    in
    (match Scheduler.with_tracking node (fun () -> Scheduler.run_body node.run) with
    | () -> ()
    | exception e ->
        stop ();
        raise e);
    Core.clear_dirty node;
    node.level <- Scheduler.compute_level node;
    own stop

  let on_change ?(equal = Signal.default_equal) state f =
    let prev = ref (Signal.peek state) in
    run (fun () ->
        let next = Signal.get state in
        if Signal.differs equal !prev next then begin
          let p = !prev in
          prev := next;
          Scheduler.untrack (fun () -> f ~prev:p ~next)
        end)
end


module Async = struct
  type 'a status = Pending | Done of 'a | Failed of string

  type 'a t = {
    mutable status : 'a status;
    mutable waiters : ('a status -> unit) list;
  }

  let settle t st =
    match t.status with
    | Pending ->
        t.status <- st;
        let waiters = List.rev t.waiters in
        t.waiters <- [];
        List.iter (fun w -> w st) waiters
    | _ -> ()

  let make () =
    let t = { status = Pending; waiters = [] } in
    (t, (fun v -> settle t (Done v)), fun e -> settle t (Failed e))

  let resolved v = { status = Done v; waiters = [] }
  let failed e = { status = Failed e; waiters = [] }
  let status t = t.status

  let on_settled t f =
    match t.status with
    | Pending -> t.waiters <- f :: t.waiters
    | st -> f st

  let on_result t f =
    on_settled t (function
      | Pending -> ()
      | Done v -> f (Ok v)
      | Failed m -> f (Error m))

  let bind t f =
    let r, resolve, fail = make () in
    on_settled t (function
      | Pending -> ()
      | Failed e -> fail e
      | Done v ->
          on_settled (f v) (function
            | Pending -> ()
            | Failed e -> fail e
            | Done x -> resolve x));
    r

  let map f t = bind t (fun v -> resolved (f v))

  let watch t =
    let s = State.make t.status in
    on_settled t (fun st -> State.set s st);
    s
end

type server
type client
type event
type loading = [ `Load | `Idle | `Visible | `Interaction ]

module Types = struct
  type node =
    | Text of string
    | Element of { tag : string; attrs : attr list; children : node list }
    | Fragment of node list
    | Hole of (unit -> node)
    | Island of {
        name : string;
        props : Json.t;
        render : unit -> node;
        loading : loading;
      }
    | Await : {
        async : 'a Async.t;
        loading : node;
        failed : string -> node;
        render : 'a -> node;
      }
        -> node
    | Slot of slot
    | Template of { id : string; node : node }
    | Each : {
        items : unit -> 'a list;
        key : 'a -> string;
        equal : 'a -> 'a -> bool;
        render : 'a -> node;
      }
        -> node

  and slot = { content : node option; dom : Obj.t list ref }

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
      }
    | Pending_async of { id : string; async : Json.t Async.t }

  type session = {
    streaming : bool;
    mutable islands : int;
    mutable asyncs : int;
    mutable awaits : int;
    mutable pending : pending list;
  }
end

open Types

type slot = Types.slot

let current_session : session option ref = ref None

let async_source : (string -> Json.t Async.t) ref =
  ref (fun _ -> Async.failed "no async transport")

module Codec_base = struct
  type 'a t = { encode : 'a -> Json.t; decode : Json.t -> ('a, string) result }

  let mismatch what (j : Json.t) =
    let s = Json.to_string j in
    let s = if String.length s > 40 then String.sub s 0 40 ^ "..." else s in
    Error (Printf.sprintf "expected %s, got %s" what s)

  let int =
    { encode = (fun i -> `Int i);
      decode = (function `Int i -> Ok i | j -> mismatch "int" j) }

  let float =
    { encode = (fun f -> `Float f);
      decode =
        (function
        | `Float f -> Ok f
        | `Int i -> Ok (float_of_int i)
        | j -> mismatch "float" j) }

  let string =
    { encode = (fun s -> `String s);
      decode = (function `String s -> Ok s | j -> mismatch "string" j) }

  let bool =
    { encode = (fun b -> `Bool b);
      decode = (function `Bool b -> Ok b | j -> mismatch "bool" j) }

  let unit =
    { encode = (fun () -> `Null);
      decode = (function `Null -> Ok () | j -> mismatch "null" j) }

  let list c =
    { encode = (fun l -> `List (List.map c.encode l));
      decode =
        (function
        | `List l ->
            let rec go acc = function
              | [] -> Ok (List.rev acc)
              | x :: rest -> (
                  match c.decode x with
                  | Ok v -> go (v :: acc) rest
                  | Error _ as e -> e)
            in
            go [] l
        | j -> mismatch "list" j) }

  let array c =
    let l = list c in
    { encode = (fun a -> l.encode (Array.to_list a));
      decode = (fun j -> Result.map Array.of_list (l.decode j)) }

  let option c =
    { encode = (function None -> `Null | Some v -> c.encode v);
      decode =
        (function `Null -> Ok None | j -> Result.map Option.some (c.decode j)) }

  let result a e =
    {
      encode =
        (function
        | Ok v -> `Assoc [ ("ok", a.encode v) ]
        | Error v -> `Assoc [ ("error", e.encode v) ]);
      decode =
        (function
        | `Assoc [ ("ok", j) ] -> Result.map (fun v -> Ok v) (a.decode j)
        | `Assoc [ ("error", j) ] -> Result.map (fun v -> Error v) (e.decode j)
        | j -> mismatch "result" j);
    }

  let encode c v = c.encode v
  let decode c j = c.decode j
end

let async_codec c : 'a Async.t Codec_base.t =
  let open Codec_base in
  {
    encode =
      (fun a ->
        let j = Async.map c.encode a in
        let id, streaming =
          match !current_session with
          | Some s ->
              s.asyncs <- s.asyncs + 1;
              ("a" ^ string_of_int s.asyncs, s.streaming)
          | None -> ("a0", false)
        in
        let assoc extra : Json.t = `Assoc (("$async", `String id) :: extra) in
        match Async.status j with
        | Async.Done v -> assoc [ ("ok", v) ]
        | Async.Failed m -> assoc [ ("error", `String m) ]
        | Async.Pending -> (
            match !current_session with
            | Some s when streaming ->
                s.pending <- Pending_async { id; async = j } :: s.pending;
                assoc []
            | _ -> assoc [ ("error", `String "pending at render") ]));
    decode =
      (function
      | `Assoc (("$async", `String id) :: rest) -> (
          let of_json j =
            match c.decode j with
            | Ok v -> Async.resolved v
            | Error m -> Async.failed m
          in
          match rest with
          | [ ("ok", j) ] -> Ok (of_json j)
          | [ ("error", `String m) ] -> Ok (Async.failed m)
          | [] -> Ok (Async.bind (!async_source id) of_json)
          | _ -> Error "bad async reference")
      | j -> mismatch "async reference" j);
  }

type 'kind element = node
type 'kind attribute = attr

let text s = Text s
let int n = Text (string_of_int n)
let float f = Text (Json.to_string (`Float f))
let empty = Fragment []
let list children = Fragment children
let fragment children = Fragment children
let lower tag attrs children = Element { tag; attrs; children }
let attr name value = Static (name, value)
module Codec = struct
  include Codec_base

  let async = async_codec

  let slot : slot t =
    {
      encode = (fun _ -> `Null);
      decode = (fun _ -> Ok { content = None; dom = ref [] });
    }
end

let hole f = Hole f
let slot s = Slot s
let template id node = Template { id; node }

module Slot = struct
  let make content = { content = Some content; dom = ref [] }
end

let await ?(failed = fun _ -> Fragment []) async ~loading render =
  Await { async; loading; failed; render }
let hole_attr name f = Dynamic (name, f)
let on name handler = Handler (name, handler)

let each ?(equal = ( = )) ~key items render =
  Each { items; key; equal; render }


module Client = struct
  type entry = { name : string; decode : Json.t -> (unit -> node, string) result }

  let island ?(loading = `Load) ~name ~props render =
    Island { name; props; render; loading }
  let entry ~name decode = { name; decode }
end

module Action = struct
  type ('i, 'o) t = { name : string; input : 'i Codec.t; output : 'o Codec.t }

  let declare ~name ~input ~output = { name; input; output }
  let name a = a.name
  let transport : (string -> Json.t -> Json.t Async.t) ref =
    ref (fun _ _ -> Async.failed "no action transport")

  let call a i =
    Async.bind (!transport a.name (a.input.encode i)) (fun j ->
        match a.output.decode j with
        | Ok v -> Async.resolved v
        | Error e -> Async.failed e)
end

let browser_only _ = failwith "Yuka: this function runs only in the browser"

let platform =
  ref
    {
      target_value = browser_only;
      target_checked = browser_only;
      key = browser_only;
      meta_key = browser_only;
      ctrl_key = browser_only;
      prevent_default = browser_only;
      on_window = (fun _ _ -> browser_only ());
      stop_propagation = browser_only;
      target_tag = browser_only;
      shift_key = browser_only;
      alt_key = browser_only;
      navigate = browser_only;
      focus = browser_only;
      scroll_into_view = browser_only;
    }

module Event = struct
  type t = event

  let target_value e = !platform.target_value e
  let target_checked e = !platform.target_checked e
  let key e = !platform.key e
  let meta_key e = !platform.meta_key e
  let ctrl_key e = !platform.ctrl_key e
  let prevent_default e = !platform.prevent_default e
  let stop_propagation e = !platform.stop_propagation e
  let target_tag e = !platform.target_tag e
  let shift_key e = !platform.shift_key e
  let alt_key e = !platform.alt_key e
end

module Browser = struct
  let on_window name handler = own (!platform.on_window name handler)
  let navigate url = !platform.navigate url
  let focus id = !platform.focus id
  let scroll_into_view id = !platform.scroll_into_view id
end

module Internal = struct
  include Types

  let node n = n
  let element n = n

  let owned f =
    let o = new_owner () in
    let parent = !current_owner in
    let id =
      Option.map (fun p -> (p, add_disposer p (fun () -> dispose_owner o))) parent
    in
    let result = with_owner o f in
    ( result,
      fun () ->
        Option.iter (fun (p, id) -> Hashtbl.remove p.disposers id) id;
        dispose_owner o )

  let server_rendering = server_rendering
  let platform = platform
  let entry_name (e : Client.entry) = e.name
  let entry_decode (e : Client.entry) j = e.decode j
  let untracked = Scheduler.untrack
  let owner_size () =
    match !current_owner with
    | Some o -> Hashtbl.length o.disposers
    | None -> 0
  let slot_content (s : slot) = s.content
  let slot_dom (s : slot) = s.dom
  let call_action = Action.transport
  let async_source = async_source
  let action_codecs (a : (_, _) Action.t) = (a.input, a.output)

  let escape ~quote s =
    let b = Buffer.create (String.length s) in
    String.iter
      (function
        | '&' -> Buffer.add_string b "&amp;"
        | '<' -> Buffer.add_string b "&lt;"
        | '>' when not quote -> Buffer.add_string b "&gt;"
        | '"' when quote -> Buffer.add_string b "&quot;"
        | c -> Buffer.add_char b c)
      s;
    Buffer.contents b

  let void_tags =
    [ "area"; "base"; "br"; "col"; "embed"; "hr"; "img"; "input"; "link";
      "meta"; "source"; "track"; "wbr" ]

  let fill_script =
    "<script>window.__yukaFill=function(id){var t=document.querySelector('template[data-yuka-fill=\"'+id+'\"]'),w=document.createTreeWalker(document,128),c;while(c=w.nextNode())if(c.data==='['+id)break;if(!t||!c)return;var d=1,n=c.nextSibling,x;while(n){if(n.nodeType===8){if(n.data.charAt(0)==='[')d++;else if(n.data===']'&&--d===0)break}x=n.nextSibling;n.parentNode.removeChild(n);n=x}n.parentNode.insertBefore(t.content,n);t.remove();if(document.currentScript)document.currentScript.remove()};</script>"

  let skeleton_html root =
    let b = Buffer.create 256 in
    let after_text = ref false in
    let select_value = ref None in
    let marker m =
      Buffer.add_string b m;
      after_text := false
    in
    let rec go = function
      | Text "" -> ()
      | Text t ->
          if !after_text then Buffer.add_string b "<!---->";
          Buffer.add_string b (escape ~quote:false t);
          after_text := true
      | Fragment children -> List.iter go children
      | Template { node; _ } -> go node
      | Hole _ | Await _ | Each _ | Island _ -> marker "<!--[--><!--]-->"
      | Slot _ -> marker "<!--[$--><!--]-->"
      | Element { tag; attrs; children } ->
          let resolved =
            List.filter_map
              (function Static (name, value) -> Some (name, value) | _ -> None)
              attrs
          in
          let value = List.assoc_opt "value" resolved in
          let resolved =
            if tag = "select" || tag = "textarea" then
              List.filter (fun (name, _) -> name <> "value") resolved
            else if
              tag = "option" && value <> None && !select_value = value
              && not (List.mem_assoc "selected" resolved)
            then resolved @ [ ("selected", "") ]
            else resolved
          in
          Buffer.add_char b '<';
          Buffer.add_string b tag;
          List.iter
            (fun (name, v) ->
              Buffer.add_char b ' ';
              Buffer.add_string b name;
              Buffer.add_string b "=\"";
              Buffer.add_string b (escape ~quote:true v);
              Buffer.add_char b '"')
            resolved;
          Buffer.add_char b '>';
          after_text := false;
          if not (List.mem tag void_tags) then begin
            (match (tag, value) with
            | "textarea", Some v ->
                if String.length v > 0 && v.[0] = '\n' then
                  Buffer.add_char b '\n';
                Buffer.add_string b (escape ~quote:false v)
            | "select", _ ->
                let outer = !select_value in
                select_value := value;
                List.iter go children;
                select_value := outer
            | _ -> List.iter go children);
            Buffer.add_string b "</";
            Buffer.add_string b tag;
            Buffer.add_char b '>';
            after_text := false
          end
    in
    go root;
    Buffer.contents b

  let session ~streaming =
    { streaming; islands = 0; asyncs = 0; awaits = 0; pending = [] }

  let take_pending s =
    let p = List.rev s.pending in
    s.pending <- [];
    p

  let rec print s build =
    let b = Buffer.create 256 in
    let after_text = ref false in
    let select_value = ref None in
    let marker m =
      Buffer.add_string b m;
      after_text := false
    in
    let rec go = function
      | Text "" -> ()
      | Text t ->
          if !after_text then Buffer.add_string b "<!---->";
          Buffer.add_string b (escape ~quote:false t);
          after_text := true
      | Fragment children -> List.iter go children
      | Hole f ->
          marker "<!--[-->";
          go (f ());
          marker "<!--]-->"
      | Await { async; loading; failed; render } -> (
          let body () =
            match Async.status async with
            | Async.Done v -> render v
            | Async.Failed m -> failed m
            | Async.Pending -> loading
          in
          match Async.status async with
          | Async.Pending when s.streaming ->
              s.awaits <- s.awaits + 1;
              let id = "s" ^ string_of_int s.awaits in
              s.pending <-
                Pending_await
                  {
                    id;
                    subscribe =
                      (fun cb -> Async.on_settled async (fun _ -> cb ()));
                    fill = (fun () -> print s body);
                    fill_failed = (fun m -> print s (fun () -> failed m));
                  }
                :: s.pending;
              marker ("<!--[" ^ id ^ "-->");
              go loading;
              marker "<!--]-->"
          | _ ->
              marker "<!--[-->";
              go (body ());
              marker "<!--]-->")
      | Template { node; _ } -> go node
      | Slot { content; _ } ->
          marker "<!--[$-->";
          Option.iter go content;
          marker "<!--]-->"
      | Island { name; props; render; loading } ->
          s.islands <- s.islands + 1;
          let id = "i" ^ string_of_int s.islands in
          Buffer.add_string b
            (Printf.sprintf
               "<yuka-island data-name=\"%s\" data-id=\"%s\" style=\"display:contents\"%s>"
               (escape ~quote:true name) id
               (match loading with
               | `Load -> ""
               | `Idle -> " data-start=\"idle\""
               | `Visible -> " data-start=\"visible\""
               | `Interaction -> " data-start=\"interaction\""));
          after_text := false;
          go (render ());
          Buffer.add_string b "</yuka-island>";
          Buffer.add_string b
            (Printf.sprintf
               "<script type=\"application/json\" data-yuka-props=\"%s\">%s</script>"
               id (Json.to_string props));
          after_text := false
      | Each { items; key = _; equal = _; render } ->
          marker "<!--[-->";
          List.iter
            (fun item ->
              marker "<!--[-->";
              go (render item);
              marker "<!--]-->")
            (items ());
          marker "<!--]-->"
      | Element { tag; attrs; children } ->
          let resolved =
            List.filter_map
              (function
                | Static (name, value) -> Some (name, value)
                | Dynamic (name, f) -> Option.map (fun v -> (name, v)) (f ())
                | Handler _ -> None)
              attrs
          in
          let value = List.assoc_opt "value" resolved in
          let resolved =
            if tag = "select" || tag = "textarea" then
              List.filter (fun (name, _) -> name <> "value") resolved
            else if
              tag = "option" && value <> None && !select_value = value
              && not (List.mem_assoc "selected" resolved)
            then resolved @ [ ("selected", "") ]
            else resolved
          in
          Buffer.add_char b '<';
          Buffer.add_string b tag;
          List.iter
            (fun (name, v) ->
              Buffer.add_char b ' ';
              Buffer.add_string b name;
              Buffer.add_string b "=\"";
              Buffer.add_string b (escape ~quote:true v);
              Buffer.add_char b '"')
            resolved;
          Buffer.add_char b '>';
          after_text := false;
          if not (List.mem tag void_tags) then begin
            (match (tag, value) with
            | "textarea", Some v ->
                if String.length v > 0 && v.[0] = '\n' then
                  Buffer.add_char b '\n';
                Buffer.add_string b (escape ~quote:false v)
            | "select", _ ->
                let outer = !select_value in
                select_value := value;
                List.iter go children;
                select_value := outer
            | _ -> List.iter go children);
            Buffer.add_string b "</";
            Buffer.add_string b tag;
            Buffer.add_char b '>';
            after_text := false
          end
    in
    let previous = !server_rendering in
    let previous_session = !current_session in
    server_rendering := true;
    current_session := Some s;
    let restore () =
      server_rendering := previous;
      current_session := previous_session
    in
    (match go (build ()) with
    | () -> restore ()
    | exception e ->
        restore ();
        raise e);
    Buffer.contents b

  let render_html build = print (session ~streaming:false) build

  let to_html root = render_html (fun () -> root)
end
