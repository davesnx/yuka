open Ppxlib
open Ast_builder.Default

let fail ~loc fmt = Location.raise_errorf ~loc ("[yuka] " ^^ fmt)

let read path = In_channel.with_open_bin path In_channel.input_all

let file_of_payload ~loc payload =
  match payload with
  | PStr [ { pstr_desc = Pstr_eval (e, _); _ } ] -> (
      match e.pexp_desc with
      | Pexp_constant (Pconst_string (file, _, _)) -> file
      | _ -> fail ~loc "[%%yuka.css] takes a file name: module Css = [%%yuka.css \"file.css\"]")
  | _ -> fail ~loc "[%%yuka.css] takes a file name: module Css = [%%yuka.css \"file.css\"]"

let expand ~loc payload =
  let file = file_of_payload ~loc payload in
  let dir = Filename.dirname loc.loc_start.pos_fname in
  let path = if Filename.is_relative file then Filename.concat dir file else file in
  let text =
    try read path
    with Sys_error _ ->
      fail ~loc
        "cannot read %s; list it in the dune file of this library: (preprocessor_deps %s)" file file
  in
  let sheet = try Css_scan.sheet ~path:file text with Css_scan.Error m -> fail ~loc "%s" m in
  let href = "/_yuka/css/" ^ sheet.file in
  let stylesheet = [%stri let stylesheet = Yuka.runtime_stylesheet [%e estring ~loc href]] in
  let classes =
    List.map
      (fun (name, value) ->
        pstr_value ~loc Nonrecursive
          [ value_binding ~loc ~pat:(pvar ~loc name) ~expr:(estring ~loc value) ])
      sheet.classes
  in
  pmod_structure ~loc (stylesheet :: classes)

let use sheet (body : expression) =
  let loc = body.pexp_loc in
  [%expr Yuka.use_css [%e pexp_ident ~loc { txt = Ldot (Lident sheet, "stylesheet"); loc }] [%e body]]

let is_jsx e = List.exists (fun (a : attribute) -> a.attr_name.txt = "JSX") e.pexp_attributes

let rec is_element_type t =
  match t.ptyp_desc with
  | Ptyp_arrow (_, _, r) -> is_element_type r
  | Ptyp_poly (_, t) -> is_element_type t
  | Ptyp_constr ({ txt = Lident "element" | Ldot (_, "element"); _ }, _) -> true
  | _ -> false

let rec returns_element e =
  is_jsx e
  ||
  match e.pexp_desc with
  | Pexp_constraint (e, t) -> is_element_type t || returns_element e
  | Pexp_let (_, _, b) | Pexp_sequence (_, b) | Pexp_letmodule (_, _, b) | Pexp_open (_, b)
  | Pexp_letexception (_, b) | Pexp_newtype (_, b) ->
      returns_element b
  | Pexp_ifthenelse (_, a, b) -> returns_element a || Option.fold ~none:false ~some:returns_element b
  | Pexp_match (_, cases) | Pexp_try (_, cases) -> List.exists (fun c -> returns_element c.pc_rhs) cases
  | Pexp_function (_, Some (Pconstraint t), _) -> is_element_type t
  | Pexp_function (_, _, Pfunction_body b) -> returns_element b
  | Pexp_function (_, _, Pfunction_cases (cases, _, _)) -> List.exists (fun c -> returns_element c.pc_rhs) cases
  | _ -> false

let constrained_element (vb : value_binding) =
  match vb.pvb_constraint with
  | Some (Pvc_constraint { typ; _ }) -> is_element_type typ
  | Some (Pvc_coercion { coercion; _ }) -> is_element_type coercion
  | None -> false

let rec wrap_function sheet e =
  match e.pexp_desc with
  | Pexp_function ((_ :: _ as params), c, Pfunction_body body) ->
      Some { e with pexp_desc = Pexp_function (params, c, Pfunction_body (use sheet body)) }
  | Pexp_function (params, c, Pfunction_cases (cases, loc, attrs)) ->
      let cases = List.map (fun c -> { c with pc_rhs = use sheet c.pc_rhs }) cases in
      Some { e with pexp_desc = Pexp_function (params, c, Pfunction_cases (cases, loc, attrs)) }
  | Pexp_constraint (inner, t) ->
      Option.map (fun inner -> { e with pexp_desc = Pexp_constraint (inner, t) }) (wrap_function sheet inner)
  | Pexp_newtype (n, inner) ->
      Option.map (fun inner -> { e with pexp_desc = Pexp_newtype (n, inner) }) (wrap_function sheet inner)
  | _ -> None

let cannot_wrap (vb : value_binding) =
  let loc = vb.pvb_loc in
  { vb with
    pvb_attributes =
      vb.pvb_attributes
      @ [ attribute ~loc ~name:{ txt = "ocaml.ppwarning"; loc }
            ~payload:
              (PStr
                 [ pstr_eval ~loc
                     (estring ~loc
                        "[yuka] this make is not a function, so [%yuka.css] cannot add its sheet; call Yuka.use_css Css.stylesheet in the component")
                     [] ]) ] }

let wrap_make ~component sheet (vb : value_binding) =
  match vb.pvb_pat.ppat_desc with
  | Ppat_var { txt = "make"; _ } -> (
      if not (component || constrained_element vb || returns_element vb.pvb_expr) then vb
      else match wrap_function sheet vb.pvb_expr with None -> cannot_wrap vb | Some e -> { vb with pvb_expr = e })
  | _ -> vb

let defines name items =
  List.exists
    (fun i ->
      match i.pstr_desc with
      | Pstr_value (_, vbs) ->
          List.exists (fun vb -> match vb.pvb_pat.ppat_desc with Ppat_var { txt; _ } -> txt = name | _ -> false) vbs
      | _ -> false)
    items

let rec wrap_items ~component sheet items = List.map (wrap_item ~component sheet) items

and wrap_item ?(component = false) sheet item =
  match item.pstr_desc with
  | Pstr_value (r, vbs) -> { item with pstr_desc = Pstr_value (r, List.map (wrap_make ~component sheet) vbs) }
  | Pstr_extension (({ txt = "client"; _ } as name, PStr items), attrs) ->
      { item with pstr_desc = Pstr_extension ((name, PStr (wrap_items ~component:true sheet items)), attrs) }
  | Pstr_include ({ pincl_mod = { pmod_desc = Pmod_structure items; _ } as m; _ } as i) ->
      let component = defines "island" items && defines "register" items in
      { item with
        pstr_desc = Pstr_include { i with pincl_mod = { m with pmod_desc = Pmod_structure (wrap_items ~component sheet items) } } }
  | Pstr_module ({ pmb_expr = { pmod_desc = Pmod_structure items; _ } as m; _ } as mb) ->
      { item with
        pstr_desc = Pstr_module { mb with pmb_expr = { m with pmod_desc = Pmod_structure (wrap_items ~component:false sheet items) } } }
  | _ -> item

let attach (items : structure) =
  let sheet = ref None in
  List.map
    (fun item ->
      match item.pstr_desc with
      | Pstr_module
          ({ pmb_name = { txt = Some name; _ }; pmb_expr = { pmod_desc = Pmod_extension ({ txt = "yuka.css"; _ }, payload); pmod_loc; _ }; _ } as mb) ->
          if !sheet <> None then fail ~loc:item.pstr_loc "only one [%%yuka.css] per file";
          sheet := Some name;
          { item with pstr_desc = Pstr_module { mb with pmb_expr = expand ~loc:pmod_loc payload } }
      | _ -> ( match !sheet with Some s -> wrap_item s item | None -> item))
    items
