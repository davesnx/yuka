type 'f errors = ('f option * string) list
type file = { filename : string; content_type : string; size : int; content : string }
type input = Text of string | File of file
type 'a field_kind = { read : input list -> ('a, string) result; write : 'a -> string list }

let first k = function Text v :: _ -> k v | File _ :: _ -> Error "Not valid" | [] -> Error "Missing"
let string = { read = first (fun v -> Ok v); write = (fun v -> [ v ]) }

let int =
  {
    read = first (fun v -> match int_of_string_opt (String.trim v) with Some n -> Ok n | None -> Error "Not a whole number");
    write = (fun n -> [ string_of_int n ]);
  }

let float =
  {
    read = first (fun v -> match float_of_string_opt (String.trim v) with Some f -> Ok f | None -> Error "Not a number");
    write = (fun f -> [ Json.float_repr f ]);
  }

let bool = { read = (function [] -> Ok false | _ -> Ok true); write = (fun b -> if b then [ "on" ] else []) }

let option k =
  {
    read = (function [] | [ Text "" ] -> Ok None | vs -> Result.map Option.some (k.read vs));
    write = (function None -> [] | Some v -> k.write v);
  }

let list k =
  {
    read =
      (fun vs ->
        List.fold_right
          (fun v acc ->
            match (k.read [ v ], acc) with
            | Ok x, Ok xs -> Ok (x :: xs)
            | Error m, _ | _, Error m -> Error m)
          vs (Ok []));
    write = List.concat_map k.write;
  }

let custom of_string to_string =
  {
    read = first (fun v -> match of_string v with Some x -> Ok x | None -> Error "Not valid");
    write = (fun v -> [ to_string v ]);
  }

let file max_bytes =
  {
    read =
      (function
      | File f :: _ when f.size > max_bytes -> Error ("File is too large (at most " ^ string_of_int max_bytes ^ " bytes)")
      | File f :: _ -> Ok f
      | Text _ :: _ -> Error "Not a file"
      | [] -> Error "Missing");
    write = (fun _ -> []);
  }

let check k f = { k with read = (fun vs -> Result.bind (k.read vs) (fun v -> Result.map (fun () -> v) (f v))) }

let all f items =
  List.fold_right (fun x acc -> match (f x, acc) with Some y, Some ys -> Some (y :: ys) | _ -> None) items (Some [])

let pairs_of_json : Json.t -> _ = function
  | `List items -> all (function `List [ `String k; `String v ] -> Some (k, v) | _ -> None) items
  | _ -> None

type 'f decoding = { values : (string * input) list; mutable failed : 'f errors }

let field d f name k =
  match k.read (List.filter_map (fun (n, v) -> if String.equal n name then Some v else None) d.values) with
  | Ok v -> Some v
  | Error m ->
      d.failed <- (Some f, m) :: d.failed;
      None

let get = function Some v -> v | None -> invalid_arg "Yuka.Form.get"
let finish d build = if d.failed = [] then Ok (build ()) else Error (List.rev d.failed)
let put name k v = List.map (fun s -> (name, s)) (k.write v)

type upload = {
  limits : (string * int) list;
  files : Web.event -> (string * input) list;
  send :
    string -> Web.event -> (float -> unit) -> (int -> string -> unit) -> (bool -> string -> unit) -> unit -> unit;
}

type ('i, 'f) t = {
  names : ('f * string) list;
  read : 'f decoding -> ('i, 'f errors) result;
  write : 'i -> (string * string) list;
  uploads : upload option;
}

let fields ?uploads ~names ~decode ~encode () = { names; read = decode; write = encode; uploads }
let decode_inputs t values = t.read { values; failed = [] }
let decode t values = decode_inputs t (List.map (fun (k, v) -> (k, Text v)) values)
let texts values = List.filter_map (function k, Text v -> Some (k, v) | _, File _ -> None) values
let upload_limit t = match t.uploads with Some u -> List.fold_left (fun n (_, m) -> n + m) 0 u.limits | None -> 0
let encode t v = t.write v
let name t f = snd (List.find (fun (g, _) -> g == f) t.names)
let of_name t n = Option.map fst (List.find_opt (fun (_, m) -> String.equal m n) t.names)
let named t (errors : _ errors) = List.map (fun (f, m) -> (Option.map (name t) f, m)) errors

let unnamed t errors =
  List.map
    (fun (n, m) ->
      match Option.bind n (of_name t) with Some f -> (Some f, m) | None -> (None, m))
    errors
