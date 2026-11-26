(* A small OCaml highlighter for the phrases and the answers of utop. It knows
   tokens, not grammar: good enough for one line of a toplevel. *)

type kind =
  | Plain
  | Keyword
  | String
  | Number
  | Type
  | Constructor
  | Name
  | Comment
  | Operator
  | Punctuation
  | Muted
  | Error
  | Warning

let class_of = function
  | Plain -> "tk"
  | Keyword -> "tk keyword"
  | String -> "tk string"
  | Number -> "tk number"
  | Type -> "tk type"
  | Constructor -> "tk constructor"
  | Name -> "tk name"
  | Comment -> "tk comment"
  | Operator -> "tk operator"
  | Punctuation -> "tk punctuation"
  | Muted -> "tk muted"
  | Error -> "tk error"
  | Warning -> "tk warning"

type token = kind * string

let keywords =
  [
    "and"; "as"; "assert"; "begin"; "class"; "constraint"; "do"; "done"; "downto"; "else"; "end"; "exception";
    "external"; "false"; "for"; "fun"; "function"; "functor"; "if"; "in"; "include"; "inherit"; "lazy"; "let";
    "match"; "method"; "module"; "mutable"; "new"; "nonrec"; "object"; "of"; "open"; "private"; "rec"; "sig";
    "struct"; "then"; "to"; "true"; "try"; "type"; "val"; "virtual"; "when"; "while"; "with"; "mod"; "land";
    "lor"; "lxor"; "lsl"; "lsr"; "asr";
  ]

let is_keyword word = List.mem word keywords
let is_lower c = (c >= 'a' && c <= 'z') || c = '_'
let is_upper c = c >= 'A' && c <= 'Z'
let is_digit c = c >= '0' && c <= '9'
let is_ident c = is_lower c || is_upper c || is_digit c || c = '\''
let is_operator c = String.contains "!$%&*+-./:<=>?@^|~" c
let is_punctuation c = String.contains "()[]{};,#" c

let blank text = String.for_all (fun c -> c = ' ' || c = '\n' || c = '\t') text

(* Merges neighbours of the same kind, and spaces into the token before them, so
   the page has fewer spans. *)
let merge tokens =
  List.rev
    (List.fold_left
       (fun acc (kind, text) ->
         match acc with
         | (k, previous) :: rest when k = kind || blank text -> (k, previous ^ text) :: rest
         | (_, previous) :: rest when blank previous -> (kind, previous ^ text) :: rest
         | _ -> (kind, text) :: acc)
       [] tokens)

(* [types]: lowercase names are types, as after the colon of [val x : int list]. *)
let tokens ?(types = false) source =
  let n = String.length source in
  let out = ref [] in
  let push kind start stop = out := (kind, String.sub source start (stop - start)) :: !out in
  let rec skip_while p i = if i < n && p source.[i] then skip_while p (i + 1) else i in
  let rec string_end i =
    if i >= n then n
    else match source.[i] with '\\' -> string_end (i + 2) | '"' -> i + 1 | _ -> string_end (i + 1)
  in
  let rec comment_end i =
    if i + 1 >= n then n else if source.[i] = '*' && source.[i + 1] = ')' then i + 2 else comment_end (i + 1)
  in
  let rec go i =
    if i < n then begin
      let c = source.[i] in
      if c = ' ' || c = '\n' || c = '\t' then (
        let j = skip_while (fun c -> c = ' ' || c = '\n' || c = '\t') i in
        push Plain i j;
        go j)
      else if c = '(' && i + 1 < n && source.[i + 1] = '*' then (
        let j = Int.min n (comment_end (i + 2)) in
        push Comment i j;
        go j)
      else if c = '"' then (
        let j = Int.min n (string_end (i + 1)) in
        push String i j;
        go j)
      else if c = '<' && i + 4 < n && String.sub source i 5 = "<fun>" then (
        push Muted i (i + 5);
        go (i + 5))
      else if c = '\'' && i + 2 < n && source.[i + 2] = '\'' then (
        push String i (i + 3);
        go (i + 3))
      else if c = '\'' && i + 1 < n && is_lower source.[i + 1] then (
        let j = skip_while is_ident (i + 1) in
        push Type i j;
        go j)
      else if is_digit c then (
        let j = skip_while (fun c -> is_digit c || c = '.' || c = '_' || c = 'e' || c = 'x') i in
        push Number i j;
        go j)
      else if is_lower c then (
        let j = skip_while is_ident i in
        let word = String.sub source i (j - i) in
        push (if is_keyword word then Keyword else if types then Type else Plain) i j;
        go j)
      else if is_upper c then (
        let j = skip_while is_ident i in
        push Constructor i j;
        go j)
      else if c = '#' && i = 0 then (
        let j = skip_while is_ident (i + 1) in
        push Keyword i j;
        go j)
      else if is_operator c then (
        let j = skip_while is_operator i in
        push Operator i j;
        go j)
      else (
        push (if is_punctuation c then Punctuation else Plain) i (i + 1);
        go (i + 1))
    end
  in
  go 0;
  merge (List.rev !out)

let phrase source = tokens source

let starts_with ~prefix s = String.starts_with ~prefix s

(* The index of the first " = " outside brackets after [from], or [None]. *)
let top_equal s ~from =
  let n = String.length s in
  let rec go i depth =
    if i + 2 >= n then None
    else
      match s.[i] with
      | '(' | '[' | '{' -> go (i + 1) (depth + 1)
      | ')' | ']' | '}' -> go (i + 1) (depth - 1)
      | ' ' when depth = 0 && s.[i + 1] = '=' && s.[i + 2] = ' ' -> Some i
      | _ -> go (i + 1) depth
  in
  go from 0

(* [val name : type = value] and [- : type = value]: the type in type colours, the
   value as code. *)
let binding line ~head ~colon =
  let head_tokens = merge [ (Keyword, String.sub line 0 head) ] in
  let name = String.sub line head (colon - head) in
  let rest = String.sub line colon (String.length line - colon) in
  let name_tokens = if String.trim name = "" then [] else [ (Name, name) ] in
  let typed =
    match top_equal rest ~from:0 with
    | Some eq ->
        tokens ~types:true (String.sub rest 0 eq)
        @ [ (Operator, " = ") ]
        @ tokens (String.sub rest (eq + 3) (String.length rest - eq - 3))
    | None -> tokens ~types:true rest
  in
  head_tokens @ name_tokens @ typed

(* The part of [- : int = 15] after "- :". *)
let binding_rest line =
  let rest = String.sub line 3 (String.length line - 3) in
  match top_equal rest ~from:0 with
  | Some eq ->
      tokens ~types:true (String.sub rest 0 eq)
      @ [ (Operator, " = ") ]
      @ tokens (String.sub rest (eq + 3) (String.length rest - eq - 3))
  | None -> tokens ~types:true rest

let answer_line line =
  if starts_with ~prefix:"val " line then
    match String.index_from_opt line 4 ':' with
    | Some colon -> binding line ~head:4 ~colon
    | None -> tokens line
  else if starts_with ~prefix:"- : " line then (Muted, "-") :: (Plain, " ") :: (Operator, ":") :: binding_rest line
  else if starts_with ~prefix:"Error:" line then (Error, "Error") :: [ (Plain, String.sub line 5 (String.length line - 5)) ]
  else if starts_with ~prefix:"Exception:" line then
    (Error, "Exception") :: (Plain, ":") :: tokens (String.sub line 10 (String.length line - 10))
  else if starts_with ~prefix:"Warning" line then [ (Warning, line) ]
  else if starts_with ~prefix:"Line " line then [ (Muted, line) ]
  else if starts_with ~prefix:"type " line || starts_with ~prefix:"module " line || starts_with ~prefix:"exception " line
  then tokens line
  else [ (Plain, line) ]

(* The lines of an answer, each a list of tokens. *)
let answer output = List.map answer_line (String.split_on_char '\n' output)
