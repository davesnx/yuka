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
  let stylesheet = [%stri let stylesheet = Yuka.stylesheet [%e estring ~loc href]] in
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

let wrap_make sheet (vb : value_binding) =
  match (vb.pvb_pat.ppat_desc, vb.pvb_expr.pexp_desc) with
  | Ppat_var { txt = "make"; _ }, Pexp_function ((_ :: _ as params), c, Pfunction_body body) ->
      { vb with pvb_expr = { vb.pvb_expr with pexp_desc = Pexp_function (params, c, Pfunction_body (use sheet body)) } }
  | _ -> vb

let rec wrap_items sheet items = List.map (wrap_item sheet) items

and wrap_item sheet item =
  match item.pstr_desc with
  | Pstr_value (r, vbs) -> { item with pstr_desc = Pstr_value (r, List.map (wrap_make sheet) vbs) }
  | Pstr_extension (({ txt = "client"; _ } as name, PStr items), attrs) ->
      { item with pstr_desc = Pstr_extension ((name, PStr (wrap_items sheet items)), attrs) }
  | Pstr_include ({ pincl_mod = { pmod_desc = Pmod_structure items; _ } as m; _ } as i) ->
      { item with
        pstr_desc = Pstr_include { i with pincl_mod = { m with pmod_desc = Pmod_structure (wrap_items sheet items) } } }
  | Pstr_module ({ pmb_expr = { pmod_desc = Pmod_structure items; _ } as m; _ } as mb) ->
      { item with
        pstr_desc = Pstr_module { mb with pmb_expr = { m with pmod_desc = Pmod_structure (wrap_items sheet items) } } }
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
