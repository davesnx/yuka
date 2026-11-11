let guarded = [ "Element"; "Await"; "Slot"; "Catch" ]
let allowed = [ "src/element.ml"; "src/template.ml"; "src/cycle.ml" ]

let name (lid : Longident.t) =
  match lid with Lident n -> n | Ldot (_, n) -> n.txt | Lapply _ -> ""

let ends_with suffix s =
  let n = String.length s and k = String.length suffix in
  n >= k && String.sub s (n - k) k = suffix

let check file =
  let ic = open_in_bin file in
  let lexbuf = Lexing.from_channel ic in
  Location.init lexbuf file;
  let ast = Parse.implementation lexbuf in
  close_in ic;
  let found = ref [] in
  let expr (self : Ast_iterator.iterator) (e : Parsetree.expression) =
    (match e.pexp_desc with
    | Pexp_construct ({ txt; loc }, _) when List.mem (name txt) guarded ->
        found := (name txt, loc.loc_start.pos_lnum) :: !found
    | _ -> ());
    Ast_iterator.default_iterator.expr self e
  in
  let it = { Ast_iterator.default_iterator with expr } in
  it.structure it ast;
  if List.exists (fun a -> ends_with a file) allowed then []
  else List.rev_map (fun (n, line) -> Printf.sprintf "%s:%d: %s" file line n) !found

let () =
  let files = List.tl (Array.to_list Sys.argv) in
  match List.concat_map check files with
  | [] -> Printf.printf "node constructors: only in %s\n" (String.concat ", " allowed)
  | bad ->
      List.iter print_endline bad;
      print_endline
        "node constructors: build these nodes with the function in src/element.ml that installs their client code";
      exit 1
