(* The fake toplevel: it answers a phrase from the answers written in advance, and
   evaluates integer arithmetic and [let x = <arithmetic>;;] itself. *)

type env = (string * int) list

(* One space between words, and no space before the final ";;". *)
let normalize phrase =
  let words = String.split_on_char ' ' (String.trim (String.map (fun c -> if c = '\n' || c = '\t' then ' ' else c) phrase)) in
  let joined = String.concat " " (List.filter (fun w -> w <> "") words) in
  let n = String.length joined in
  if n >= 3 && String.sub joined (n - 3) 3 = " ;;" then String.sub joined 0 (n - 3) ^ ";;" else joined

let complete phrase =
  let trimmed = String.trim phrase in
  String.length trimmed >= 2 && String.sub trimmed (String.length trimmed - 2) 2 = ";;"

(* Integer arithmetic: + - * / mod, parentheses, unary minus and names of [env]. *)
module Arith = struct
  type token = Int of int | Ident of string * int | Op of string | Lparen | Rparen

  exception Unbound of string * int
  exception Syntax

  let lex source =
    let n = String.length source in
    let rec go i acc =
      if i >= n then List.rev acc
      else
        let c = source.[i] in
        if c = ' ' then go (i + 1) acc
        else if Highlight.is_digit c then (
          let j = ref i in
          while !j < n && (Highlight.is_digit source.[!j] || source.[!j] = '_') do incr j done;
          let digits = String.concat "" (String.split_on_char '_' (String.sub source i (!j - i))) in
          match int_of_string_opt digits with Some v -> go !j (Int v :: acc) | None -> raise Syntax)
        else if Highlight.is_lower c then (
          let j = ref i in
          while !j < n && Highlight.is_ident source.[!j] do incr j done;
          let word = String.sub source i (!j - i) in
          go !j ((if word = "mod" then Op "mod" else Ident (word, i)) :: acc))
        else if c = '(' then go (i + 1) (Lparen :: acc)
        else if c = ')' then go (i + 1) (Rparen :: acc)
        else if String.contains "+-*/" c then go (i + 1) (Op (String.make 1 c) :: acc)
        else raise Syntax
    in
    go 0 []

  (* expr := term (('+' | '-') term)*, term := unary (('*' | '/' | 'mod') unary)* *)
  let eval env source =
    let tokens = ref (lex source) in
    let peek () = match !tokens with t :: _ -> Some t | [] -> None in
    let next () = match !tokens with t :: rest -> tokens := rest; t | [] -> raise Syntax in
    let rec expr () =
      let rec loop acc =
        match peek () with
        | Some (Op "+") -> ignore (next ()); loop (acc + term ())
        | Some (Op "-") -> ignore (next ()); loop (acc - term ())
        | _ -> acc
      in
      loop (term ())
    and term () =
      let rec loop acc =
        match peek () with
        | Some (Op "*") -> ignore (next ()); loop (acc * unary ())
        | Some (Op "/") -> ignore (next ()); loop (acc / unary ())
        | Some (Op "mod") -> ignore (next ()); loop (acc mod unary ())
        | _ -> acc
      in
      loop (unary ())
    and unary () =
      match next () with
      | Op "-" -> -unary ()
      | Int v -> v
      | Ident (name, at) -> (
          match List.assoc_opt name env with Some v -> v | None -> raise (Unbound (name, at)))
      | Lparen ->
          let v = expr () in
          (match next () with Rparen -> v | _ -> raise Syntax)
      | Op _ | Rparen -> raise Syntax
    in
    let v = expr () in
    if !tokens <> [] then raise Syntax;
    v
end

type result = { output : string; env : env; quit : bool }

let unbound ~offset name at =
  let start = offset + at in
  Printf.sprintf "Line 1, characters %d-%d:\nError: Unbound value %s" start (start + String.length name) name

let syntax_error phrase =
  Printf.sprintf "Line 1, characters 0-%d:\nError: Syntax error" (String.length phrase - 2)

(* The first lowercase word that is not a keyword nor a name of [env], for the error
   message of a phrase that has no answer. *)
let first_unknown env phrase =
  let n = String.length phrase in
  let rec go i =
    if i >= n then None
    else if phrase.[i] = '"' then
      let rec close j = if j >= n then n else if phrase.[j] = '"' then j + 1 else close (j + 1) in
      go (close (i + 1))
    else if Highlight.is_lower phrase.[i] && (i = 0 || not (Highlight.is_ident phrase.[i - 1] || phrase.[i - 1] = '.')) then (
      let j = ref i in
      while !j < n && Highlight.is_ident phrase.[!j] do incr j done;
      let word = String.sub phrase i (!j - i) in
      if Highlight.is_keyword word || List.mem_assoc word env || word = "_" then go !j else Some (word, i))
    else go (i + 1)
  in
  go 0

let evaluate ~(answers : Session.entry list) ~env phrase =
  let phrase = normalize phrase in
  let body = String.sub phrase 0 (String.length phrase - 2) in
  let answer = List.find_opt (fun (e : Session.entry) -> normalize e.input = phrase) answers in
  match answer with
  | Some e -> { output = e.output; env; quit = phrase = "#quit;;" }
  | None when String.length body > 0 && body.[0] = '#' ->
      let name = match String.index_opt body ' ' with Some i -> String.sub body 1 (i - 1) | None -> String.sub body 1 (String.length body - 1) in
      { output = Printf.sprintf "Unknown directive \"%s\"." name; env; quit = false }
  | None -> (
      let binding =
        if String.starts_with ~prefix:"let " body then
          match String.index_opt body '=' with
          | Some eq ->
              let name = String.trim (String.sub body 4 (eq - 4)) in
              if name <> "" && Highlight.is_lower name.[0] && String.for_all Highlight.is_ident name then
                Some (name, eq + 1)
              else None
          | None -> None
        else None
      in
      let source, offset = match binding with Some (_, at) -> (String.sub body at (String.length body - at), at) | None -> (body, 0) in
      match Arith.eval env source with
      | value -> (
          let shown = Int.to_string value in
          match binding with
          | Some (name, _) ->
              { output = Printf.sprintf "val %s : int = %s" name shown; env = (name, value) :: List.remove_assoc name env; quit = false }
          | None -> { output = "- : int = " ^ shown; env; quit = false })
      | exception Division_by_zero -> { output = "Exception: Division_by_zero."; env; quit = false }
      | exception Arith.Unbound (name, at) -> { output = unbound ~offset name at; env; quit = false }
      | exception Arith.Syntax -> (
          match first_unknown env body with
          | Some (name, at) when binding = None -> { output = unbound ~offset:0 name at; env; quit = false }
          | _ -> { output = syntax_error phrase; env; quit = false }))

(* Completion: the words that start as the word before the cursor. *)
let stdlib_modules =
  [
    "Arg"; "Array"; "ArrayLabels"; "Atomic"; "Bigarray"; "Bool"; "Buffer"; "Bytes"; "Char"; "Domain"; "Effect";
    "Either"; "Filename"; "Float"; "Format"; "Fun"; "Gc"; "Hashtbl"; "In_channel"; "Int"; "Int64"; "Lazy";
    "Lexing"; "List"; "ListLabels"; "Map"; "Option"; "Out_channel"; "Printexc"; "Printf"; "Queue"; "Random";
    "Result"; "Seq"; "Set"; "Stack"; "String"; "Sys"; "Uchar"; "Unit";
  ]

let module_values =
  [
    ("List", [ "append"; "concat"; "exists"; "filter"; "filter_map"; "find"; "fold_left"; "fold_right"; "init"; "iter"; "length"; "map"; "mapi"; "mem"; "nth"; "rev"; "sort" ]);
    ("String", [ "concat"; "contains"; "equal"; "index"; "length"; "lowercase_ascii"; "make"; "map"; "split_on_char"; "sub"; "trim"; "uppercase_ascii" ]);
    ("Array", [ "append"; "blit"; "fold_left"; "init"; "iter"; "length"; "make"; "map"; "of_list"; "sort"; "to_list" ]);
    ("Float", [ "abs"; "ceil"; "floor"; "hypot"; "of_int"; "pi"; "round"; "sqrt"; "to_string" ]);
    ("Option", [ "bind"; "get"; "is_none"; "is_some"; "map"; "value" ]);
    ("Sys", [ "argv"; "getenv"; "ocaml_version"; "time" ]);
  ]

let toplevel_values =
  [ "fst"; "ignore"; "incr"; "int_of_string"; "List"; "print_endline"; "print_string"; "ref"; "snd"; "string_of_int" ]

let directives = [ "#help"; "#quit"; "#show"; "#show_type"; "#use"; "#utop_help"; "#require" ]

let word_before input =
  let n = String.length input in
  let rec go i = if i > 0 && (Highlight.is_ident input.[i - 1] || input.[i - 1] = '.' || input.[i - 1] = '#') then go (i - 1) else i in
  let start = go n in
  String.sub input start (n - start)

let candidates ~(env : env) input =
  let word = word_before input in
  if word = "" then stdlib_modules
  else if word.[0] = '#' then List.filter (fun d -> String.starts_with ~prefix:word d) directives
  else
    match String.rindex_opt word '.' with
    | Some dot -> (
        let modname = String.sub word 0 dot in
        let prefix = String.sub word (dot + 1) (String.length word - dot - 1) in
        match List.assoc_opt modname module_values with
        | Some values -> List.filter (String.starts_with ~prefix) values
        | None -> [])
    | None ->
        let names = List.sort_uniq compare (List.map fst env @ toplevel_values @ stdlib_modules) in
        List.filter (fun w -> w <> word && String.starts_with ~prefix:word w) names

(* [input] with the word before the cursor replaced by [candidate]. *)
let accept input candidate =
  let word = word_before input in
  let keep = String.length input - String.length word in
  let start = match String.rindex_opt word '.' with Some dot -> keep + dot + 1 | None -> keep in
  String.sub input 0 start ^ candidate
