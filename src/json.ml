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
            Buffer.add_string b
              (Tiny_printf.Printf.sprintf "\\u%04x" (Char.code c))
        | c -> Buffer.add_char b c)
      s;
    Buffer.add_char b '"'

  let float_repr f =
    if Float.is_nan f || Float.abs f = Float.infinity then "null"
    else
      let rec try_precision p =
        let s = Tiny_printf.Printf.sprintf "%.*g" p f in
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

  let max_depth = 512

  let of_string s =
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
      else fail (Tiny_printf.Printf.sprintf "expected %C" c)
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
    let rec value depth : t =
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
