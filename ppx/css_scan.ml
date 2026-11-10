type sheet = { file : string; classes : (string * string) list; text : string }

exception Error of string

let hash text = String.sub (Digest.to_hex (Digest.string text)) 0 8

let is_letter c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
let is_digit c = c >= '0' && c <= '9'
let is_hex c = is_digit c || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
let is_space c = c = ' ' || c = '\t' || c = '\n' || c = '\r' || c = '\012'
let is_name_start c = is_letter c || c = '_' || Char.code c >= 0x80
let is_name_char c = is_name_start c || is_digit c || c = '-'

let starts_escape s i = i + 1 < String.length s && s.[i] = '\\' && s.[i + 1] <> '\n'

let ident_start s i =
  let m = String.length s in
  i < m
  && (is_name_start s.[i]
     || starts_escape s i
     || (s.[i] = '-' && i + 1 < m && (is_name_start s.[i + 1] || s.[i + 1] = '-' || starts_escape s (i + 1))))

let read_ident s i =
  let m = String.length s in
  let value = Buffer.create 16 in
  let rec go j =
    if j < m && is_name_char s.[j] then begin
      Buffer.add_char value s.[j];
      go (j + 1)
    end
    else if starts_escape s j then
      if is_hex s.[j + 1] then begin
        let k = ref (j + 1) in
        while !k < m && !k < j + 7 && is_hex s.[!k] do incr k done;
        let code = int_of_string ("0x" ^ String.sub s (j + 1) (!k - j - 1)) in
        let u = if code = 0 || not (Uchar.is_valid code) then Uchar.rep else Uchar.of_int code in
        Buffer.add_utf_8_uchar value u;
        go (if !k < m && is_space s.[!k] then !k + 1 else !k)
      end
      else begin
        Buffer.add_char value s.[j + 1];
        go (j + 2)
      end
    else j
  in
  let stop = go i in
  (stop, Buffer.contents value)

let scoped ~hash name = name ^ "_" ^ hash

let rewrite text =
  let h = hash text in
  let n = String.length text in
  let out = Buffer.create (n + 64) in
  let at i = if i < n then text.[i] else '\000' in
  let pieces = ref [] in
  let code = Buffer.create 64 in
  let names = ref [] in
  let end_code () =
    if Buffer.length code > 0 then begin
      pieces := `Code (Buffer.contents code) :: !pieces;
      Buffer.clear code
    end
  in
  let opaque s =
    end_code ();
    pieces := `Opaque s :: !pieces
  in
  let bracket = ref 0 and depth = ref 0 in
  let rename ~supports s =
    let m = String.length s in
    let i = ref 0 in
    while !i < m do
      let c = s.[!i] in
      let selector_here =
        supports && !depth = 0 && !i + 9 <= m && String.lowercase_ascii (String.sub s !i 9) = "selector("
      in
      if selector_here then begin
        Buffer.add_string out (String.sub s !i 9);
        depth := 1;
        i := !i + 9
      end
      else begin
        if supports && !depth > 0 then
          if c = '(' then incr depth else if c = ')' then decr depth;
        if c = '[' then incr bracket else if c = ']' then decr bracket;
        let active = (not supports) || !depth > 0 in
        if c = '\\' && !i + 1 < m then begin
          Buffer.add_string out (String.sub s !i 2);
          i := !i + 2
        end
        else if active && c = '.' && !bracket = 0 && ident_start s (!i + 1) then begin
          let stop, value = read_ident s (!i + 1) in
          if not (List.mem_assoc value !names) then names := (value, ()) :: !names;
          Buffer.add_char out '.';
          Buffer.add_string out (String.sub s (!i + 1) (stop - !i - 1));
          Buffer.add_string out ("_" ^ h);
          i := stop
        end
        else begin
          Buffer.add_char out c;
          incr i
        end
      end
    done
  in
  let flush ~prelude =
    end_code ();
    let parts = List.rev !pieces in
    pieces := [];
    let first_code =
      List.find_map (function `Code s when String.trim s <> "" -> Some (String.trim s) | _ -> None) parts
    in
    let at_rule =
      match first_code with
      | Some s when s.[0] = '@' ->
          let j = ref 1 in
          while !j < String.length s && (is_letter s.[!j] || s.[!j] = '-') do incr j done;
          Some (String.lowercase_ascii (String.sub s 1 (!j - 1)))
      | _ -> None
    in
    let mode =
      if not prelude then `None
      else
        match (first_code, at_rule) with
        | None, _ -> `None
        | Some _, None -> `All
        | _, Some "scope" -> `All
        | _, Some "supports" -> `Supports
        | _, Some _ -> `None
    in
    bracket := 0;
    depth := 0;
    List.iter
      (function
        | `Code s when mode = `All -> rename ~supports:false s
        | `Code s when mode = `Supports -> rename ~supports:true s
        | `Code s | `Opaque s -> Buffer.add_string out s)
      parts
  in
  let string_end q i =
    let rec close k =
      if k >= n then n else if text.[k] = '\\' then close (k + 2) else if text.[k] = q then k + 1 else close (k + 1)
    in
    min n (close i)
  in
  let rec go i =
    if i >= n then flush ~prelude:false
    else
      let c = text.[i] in
      if c = '\\' && i + 1 < n then begin
        Buffer.add_string code (String.sub text i 2);
        go (i + 2)
      end
      else if c = '/' && at (i + 1) = '*' then begin
        let rec close k =
          if k + 1 >= n then n else if text.[k] = '*' && text.[k + 1] = '/' then k + 2 else close (k + 1)
        in
        let e = close (i + 2) in
        opaque (String.sub text i (e - i));
        go e
      end
      else if c = '"' || c = '\'' then begin
        let e = string_end c (i + 1) in
        opaque (String.sub text i (e - i));
        go e
      end
      else if
        (c = 'u' || c = 'U')
        && i + 3 < n
        && String.lowercase_ascii (String.sub text i 4) = "url("
        && (i = 0 || not (is_name_char text.[i - 1]))
      then begin
        let k = ref (i + 4) in
        while !k < n && is_space text.[!k] do incr k done;
        if !k < n && (text.[!k] = '"' || text.[!k] = '\'') then k := string_end text.[!k] (!k + 1);
        let rec close k =
          if k >= n then n else if text.[k] = '\\' then close (k + 2) else if text.[k] = ')' then k + 1 else close (k + 1)
        in
        let e = min n (close !k) in
        opaque (String.sub text i (e - i));
        go e
      end
      else if c = '{' then begin
        flush ~prelude:true;
        Buffer.add_char out c;
        go (i + 1)
      end
      else if c = '}' || c = ';' then begin
        flush ~prelude:false;
        Buffer.add_char out c;
        go (i + 1)
      end
      else begin
        Buffer.add_char code c;
        go (i + 1)
      end
  in
  go 0;
  (h, List.rev_map fst !names, Buffer.contents out)

let keywords =
  [ "and"; "as"; "assert"; "begin"; "class"; "constraint"; "do"; "done"; "downto"; "else"; "end";
    "exception"; "external"; "false"; "for"; "fun"; "function"; "functor"; "if"; "in"; "include";
    "inherit"; "initializer"; "lazy"; "let"; "match"; "method"; "module"; "mutable"; "new";
    "nonrec"; "object"; "of"; "open"; "or"; "private"; "rec"; "sig"; "struct"; "then"; "to";
    "true"; "try"; "type"; "val"; "virtual"; "when"; "while"; "with"; "mod"; "land"; "lor";
    "lxor"; "lsl"; "lsr"; "asr"; "effect" ]

let value_name ~path name =
  if String.exists (fun c -> Char.code c >= 0x80) name then
    raise
      (Error
         (Printf.sprintf "%s: the class %S has characters an OCaml name cannot have; rename it" path name));
  let s = String.map (fun c -> if is_letter c || is_digit c || c = '_' then c else '_') name in
  let s = if is_digit s.[0] then "_" ^ s else String.uncapitalize_ascii s in
  if List.mem s keywords || s = "stylesheet" then s ^ "_" else s

let sheet ~path text =
  let h, names, rewritten = rewrite text in
  let base = Filename.remove_extension (Filename.basename path) in
  let classes = List.map (fun name -> (value_name ~path name, scoped ~hash:h name)) names in
  let rec check = function
    | [] -> ()
    | (v, _) :: rest ->
        (match List.find_opt (fun (w, _) -> String.equal v w) rest with
         | Some _ ->
             raise
               (Error
                  (Printf.sprintf "%s: two classes have the OCaml name %s; rename one of them" path v))
         | None -> ());
        check rest
  in
  check classes;
  { file = base ^ "-" ^ h ^ ".css"; classes; text = rewritten }
