open Ppxlib
open Ast_builder.Default

type target = Server | Browser

let mode : expression option ref = ref None
let () = Driver.Cookies.add_simple_handler "compilation-mode" Ast_pattern.__ ~f:(fun v -> mode := v)
let fail ~loc fmt = Location.raise_errorf ~loc ("[yuka] " ^^ fmt)

let shape =
  "let%action <name> = Yuka.Action.mutation ~input:<codec> ~output:<codec> (fun ctx input -> ...), or the same \
   with Yuka.Action.query"

let bad_shape ~loc fmt = Printf.ksprintf (fun what -> fail ~loc "%s. let%%action takes the form: %s" what shape) fmt

let target ~loc =
  match !mode with
  | None ->
      fail ~loc
        "let%%action needs the compilation-mode cookie to know if it compiles for the server or the browser: use \
         (lang dune 3.26) or later in dune-project, or pass the cookie to the ppx: (preprocess (pps yuka.ppx -- --cookie \
         'compilation-mode=\"ocaml\"')) and (melange.preprocess (pps yuka.ppx -- --cookie \
         'compilation-mode=\"melange\"'))"
  | Some { pexp_desc = Pexp_constant (Pconst_string ("ocaml", _, _)); _ } -> Server
  | Some { pexp_desc = Pexp_constant (Pconst_string ("melange", _, _)); _ } -> Browser
  | Some e ->
      fail ~loc "let%%action: the compilation-mode cookie is %s; it must be \"ocaml\" or \"melange\""
        (Pprintast.string_of_expression e)

type parts = { input : expression option; output : expression option; implementation : expression list }

let split_args ~loc args =
  let add parts (label, e) =
    let eloc = e.pexp_loc in
    match label with
    | Labelled "input" when Option.is_none parts.input -> { parts with input = Some e }
    | Labelled "output" when Option.is_none parts.output -> { parts with output = Some e }
    | Labelled (("input" | "output") as l) -> bad_shape ~loc:eloc "~%s is given twice" l
    | Labelled "name" | Optional "name" -> bad_shape ~loc:eloc "let%%action sets the name of the action: remove ~name"
    | Labelled l | Optional l -> bad_shape ~loc:eloc "unexpected argument ~%s" l
    | Nolabel -> { parts with implementation = parts.implementation @ [ e ] }
  in
  match List.fold_left add { input = None; output = None; implementation = [] } args with
  | { input = None; _ } -> bad_shape ~loc "~input is missing"
  | { output = None; _ } -> bad_shape ~loc "~output is missing"
  | { implementation = []; _ } -> bad_shape ~loc "the implementation is missing"
  | { input = Some input; output = Some output; implementation = [ f ] } -> (input, output, f)
  | { implementation = _ :: extra :: _; _ } ->
      bad_shape ~loc:extra.pexp_loc "let%%action takes one implementation, a function of the context and the input"

let expand ~is_action_module ~submodules ~library ~loc ~name_loc payload =
  let vb =
    match payload with
    | PStr [ { pstr_desc = Pstr_value (Nonrecursive, [ vb ]); _ } ] -> vb
    | PStr [ { pstr_desc = Pstr_value (Recursive, _); pstr_loc } ] ->
        bad_shape ~loc:pstr_loc "let%%action cannot be recursive"
    | PStr [ { pstr_desc = Pstr_value (_, _ :: vb :: _); _ } ] ->
        bad_shape ~loc:vb.pvb_loc "let%%action takes one binding"
    | _ -> bad_shape ~loc "let%%action takes a let binding"
  in
  let var =
    match (vb.pvb_pat.ppat_desc, vb.pvb_constraint) with
    | Ppat_var v, None -> v
    | _ -> bad_shape ~loc:vb.pvb_pat.ppat_loc "the name of a let%%action must be a plain variable"
  in
  let e = vb.pvb_expr in
  let fn, args =
    match e.pexp_desc with
    | Pexp_apply (({ pexp_desc = Pexp_ident { txt = Ldot (m, ("mutation" | "query")); _ }; _ } as fn), args)
      when is_action_module m ->
        (fn, args)
    | Pexp_apply ({ pexp_desc = Pexp_ident { txt = Ldot (m, f); loc }; _ }, _) when is_action_module m ->
        bad_shape ~loc "Yuka.Action.%s cannot be a let%%action: use Yuka.Action.mutation or Yuka.Action.query" f
    | Pexp_apply ({ pexp_desc = Pexp_ident { txt = Ldot (Lident "Action", f); loc }; _ }, _) ->
        bad_shape ~loc
          "Action here is not Yuka.Action (the ppx knows only an open Yuka at the top of the file, and no module \
           Action of the file): write Yuka.Action.%s"
          f
    | _ -> bad_shape ~loc:e.pexp_loc "expected Yuka.Action.mutation or Yuka.Action.query"
  in
  let input, output, implementation = split_args ~loc:e.pexp_loc args in
  let path =
    List.fold_left
      (fun path (m : string loc) -> Code_path.enter_module ~loc:m.loc m.txt path)
      (Code_path.top_level ~file_path:loc.loc_start.pos_fname)
      submodules
    |> Code_path.enter_value ~loc:var.loc var.txt
  in
  let name =
    match library with
    | Some l -> l ^ "." ^ Code_path.fully_qualified_path path
    | None -> Code_path.fully_qualified_path path
  in
  let gloc = { loc with loc_ghost = true } in
  let declaration =
    pexp_apply ~loc:e.pexp_loc fn
      [ (Labelled "name", estring ~loc:gloc name); (Labelled "input", input); (Labelled "output", output) ]
  in
  let bind pvb_expr = pstr_value ~loc Nonrecursive [ { vb with pvb_expr } ] in
  match target ~loc:name_loc with
  | Browser -> [ bind declaration ]
  | Server ->
      let loc = gloc in
      [
        bind
          [%expr
            (fun action implementation ->
              Yuka.Server.Action.implement action implementation;
              action)
              [%e declaration] [%e implementation]];
      ]
