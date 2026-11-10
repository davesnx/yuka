type sheet = { file : string; classes : (string * string) list; text : string }

exception Error of string

let hash text = String.sub (Digest.to_hex (Digest.string text)) 0 8

let is_name_start c = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c = '_'

let is_name_char c = is_name_start c || (c >= '0' && c <= '9') || c = '-'

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
  let rename s bracket =
    let m = String.length s in
    let i = ref 0 in
    while !i < m do
      let c = s.[!i] in
      if c = '[' then incr bracket else if c = ']' then decr bracket;
      let starts =
        c = '.' && !bracket = 0 && !i + 1 < m
        && (is_name_start s.[!i + 1]
           || (s.[!i + 1] = '-' && !i + 2 < m && (is_name_start s.[!i + 2] || s.[!i + 2] = '-')))
      in
      if starts then begin
        let j = ref (!i + 1) in
        while !j < m && is_name_char s.[!j] do incr j done;
        let name = String.sub s (!i + 1) (!j - !i - 1) in
        if not (List.mem name !names) then names := name :: !names;
        Buffer.add_char out '.';
        Buffer.add_string out (scoped ~hash:h name);
        i := !j
      end
      else begin
        Buffer.add_char out c;
        incr i
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
    let rule = prelude && match first_code with Some s -> s.[0] <> '@' | None -> false in
    let bracket = ref 0 in
    List.iter
      (function
        | `Code s when rule -> rename s bracket
        | `Code s | `Opaque s -> Buffer.add_string out s)
      parts
  in
  let rec go i =
    if i >= n then flush ~prelude:false
    else
      let c = text.[i] in
      if c = '/' && at (i + 1) = '*' then begin
        let rec close k =
          if k + 1 >= n then n else if text.[k] = '*' && text.[k + 1] = '/' then k + 2 else close (k + 1)
        in
        let e = close (i + 2) in
        opaque (String.sub text i (e - i));
        go e
      end
      else if c = '"' || c = '\'' then begin
        let rec close k =
          if k >= n then n else if text.[k] = '\\' then close (k + 2) else if text.[k] = c then k + 1 else close (k + 1)
        in
        let e = min n (close (i + 1)) in
        opaque (String.sub text i (e - i));
        go e
      end
      else if
        (c = 'u' || c = 'U')
        && i + 3 < n
        && String.lowercase_ascii (String.sub text i 4) = "url("
        && (i = 0 || not (is_name_char text.[i - 1]))
      then begin
        let rec close k = if k >= n then n else if text.[k] = ')' then k + 1 else close (k + 1) in
        let e = close (i + 4) in
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
  (h, List.rev !names, Buffer.contents out)

let keywords =
  [ "and"; "as"; "assert"; "begin"; "class"; "constraint"; "do"; "done"; "downto"; "else"; "end";
    "exception"; "external"; "false"; "for"; "fun"; "function"; "functor"; "if"; "in"; "include";
    "inherit"; "initializer"; "lazy"; "let"; "match"; "method"; "module"; "mutable"; "new";
    "nonrec"; "object"; "of"; "open"; "or"; "private"; "rec"; "sig"; "struct"; "then"; "to";
    "true"; "try"; "type"; "val"; "virtual"; "when"; "while"; "with"; "mod"; "land"; "lor";
    "lxor"; "lsl"; "lsr"; "asr"; "effect" ]

let value_name name =
  let s = String.map (fun c -> if c = '-' then '_' else c) name in
  let s = if s.[0] = '_' then s else String.uncapitalize_ascii s in
  if List.mem s keywords || s = "stylesheet" then s ^ "_" else s

let sheet ~path text =
  let h, names, rewritten = rewrite text in
  let base = Filename.remove_extension (Filename.basename path) in
  let classes = List.map (fun name -> (value_name name, scoped ~hash:h name)) names in
  let rec check = function
    | [] -> ()
    | (v, _) :: rest ->
        (match List.find_opt (fun (w, _) -> String.equal v w) rest with
         | Some _ ->
             raise
               (Error
                  (Printf.sprintf "%s: two classes have the OCaml name %s; rename one of them"
                     path v))
         | None -> ());
        check rest
  in
  check classes;
  { file = base ^ "-" ^ h ^ ".css"; classes; text = rewritten }
