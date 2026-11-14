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
            let hex = "0123456789abcdef" and n = Char.code c in
            Buffer.add_string b "\\u00";
            Buffer.add_char b hex.[n lsr 4];
            Buffer.add_char b hex.[n land 15]
        | c -> Buffer.add_char b c)
      s;
    Buffer.add_char b '"'

  let float_repr f =
    if f <> f || f = infinity || f = neg_infinity then "null"
    else
      let s = Web.shortest_float f in
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

  let of_string : string -> (t, string) result = Web.parse_json

let mismatch what (j : t) =
  let s = to_string j in
  let s = if String.length s > 40 then Web.sub s 0 40 ^ "..." else s in
  Error ("expected " ^ what ^ ", got " ^ s)
