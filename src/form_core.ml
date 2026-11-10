type 'f errors = ('f option * string) list
type 'a kind = { read : string list -> ('a, string) result; write : 'a -> string list }

let first k = function v :: _ -> k v | [] -> Error "Missing"
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
    read = (function [] | [ "" ] -> Ok None | vs -> Result.map Option.some (k.read vs));
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

type 'f decoding = { values : (string * string) list; mutable failed : 'f errors }

let field d f name k =
  match k.read (List.filter_map (fun (n, v) -> if String.equal n name then Some v else None) d.values) with
  | Ok v -> Some v
  | Error m ->
      d.failed <- (Some f, m) :: d.failed;
      None

let get = function Some v -> v | None -> invalid_arg "Yuka.Form.get"
let finish d build = if d.failed = [] then Ok (build ()) else Error (List.rev d.failed)
let put name k v = List.map (fun s -> (name, s)) (k.write v)

type ('i, 'f) t = {
  names : ('f * string) list;
  read : 'f decoding -> ('i, 'f errors) result;
  write : 'i -> (string * string) list;
}

let fields ~names ~decode ~encode = { names; read = decode; write = encode }
let decode t values = t.read { values; failed = [] }
let encode t v = t.write v
let name t f = snd (List.find (fun (g, _) -> g == f) t.names)
let of_name t n = Option.map fst (List.find_opt (fun (_, m) -> String.equal m n) t.names)
let named t (errors : _ errors) = List.map (fun (f, m) -> (Option.map (name t) f, m)) errors

let unnamed t errors =
  List.map
    (fun (n, m) ->
      match Option.bind n (of_name t) with Some f -> (Some f, m) | None -> (None, m))
    errors
