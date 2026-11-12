open Ppxlib
open Ast_builder.Default

let fail ~loc fmt = Location.raise_errorf ~loc ("[yuka] " ^^ fmt)
let suffixed n s = if n = "t" then s else n ^ "_" ^ s

let rec kind (t : core_type) =
  let loc = t.ptyp_loc in
  match t.ptyp_desc with
  | Ptyp_constr ({ txt = Lident "string" | Ldot (Lident "String", "t"); _ }, []) -> [%expr Yuka.Form.string]
  | Ptyp_constr ({ txt = Lident "int" | Ldot (Lident "Int", "t"); _ }, []) -> [%expr Yuka.Form.int]
  | Ptyp_constr ({ txt = Lident "float" | Ldot (Lident "Float", "t"); _ }, []) -> [%expr Yuka.Form.float]
  | Ptyp_constr ({ txt = Lident "bool" | Ldot (Lident "Bool", "t"); _ }, []) -> [%expr Yuka.Form.bool]
  | Ptyp_constr ({ txt = Lident "option"; _ }, [ a ]) -> [%expr Yuka.Form.option [%e kind a]]
  | Ptyp_constr ({ txt = Lident "list"; _ }, [ a ]) -> [%expr Yuka.Form.list [%e kind a]]
  | Ptyp_constr ({ txt = Ldot (m, "t"); _ }, []) ->
      let of_string = pexp_ident ~loc { loc; txt = Ldot (m, "of_string") }
      and to_string = pexp_ident ~loc { loc; txt = Ldot (m, "to_string") } in
      [%expr Yuka.Form.custom [%e of_string] [%e to_string]]
  | _ ->
      fail ~loc
        "a form field must be string, int, float, bool, an option or list of those, or Email.t with Email.of_string and Email.to_string"

let labels (td : type_declaration) =
  (match td.ptype_params with
  | [] -> ()
  | (p, _) :: _ -> fail ~loc:p.ptyp_loc "[@@@@deriving form] needs a type with no parameter");
  match td.ptype_kind with
  | Ptype_record labels ->
      List.iter
        (fun l ->
          if String.length l.pld_name.txt > 0 && l.pld_name.txt.[0] = '_' then
            fail ~loc:l.pld_name.loc "a form field name cannot start with '_' (the form uses _yuka_ fields)")
        labels;
      labels
  | _ -> fail ~loc:td.ptype_loc "[@@@@deriving form] needs a record type"

let constructor (l : label_declaration) = String.capitalize_ascii l.pld_name.txt

let field_type ~loc (td : type_declaration) =
  type_declaration ~loc
    ~name:{ loc; txt = suffixed td.ptype_name.txt "field" }
    ~params:[] ~cstrs:[] ~private_:Public ~kind:Ptype_abstract
    ~manifest:
      (Some
         (ptyp_variant ~loc
            (List.map (fun l -> rtag ~loc:l.pld_loc { loc = l.pld_loc; txt = constructor l } true []) (labels td))
            Closed None))

let ctor ~loc l = pexp_variant ~loc (constructor l) None

let str_items (td : type_declaration) =
  let loc = td.ptype_loc in
  let n = td.ptype_name.txt in
  let ls = labels td in
  let field_ty = ptyp_constr ~loc { loc; txt = Lident (suffixed n "field") } [] in
  let record_ty = ptyp_constr ~loc { loc; txt = Lident n } [] in
  let names =
    elist ~loc (List.map (fun l -> [%expr [%e ctor ~loc l], [%e estring ~loc l.pld_name.txt]]) ls)
  in
  let var i = Printf.sprintf "_yuka_f%d" i in
  let build =
    pexp_record ~loc
      (List.mapi
         (fun i l -> ({ loc; txt = Lident l.pld_name.txt }, [%expr Yuka.runtime_form_get [%e evar ~loc (var i)]]))
         ls)
      None
  in
  let decode =
    List.fold_right
      (fun (i, l) body ->
        [%expr
          let [%p pvar ~loc (var i)] =
            Yuka.runtime_form_field _yuka_d [%e ctor ~loc l] [%e estring ~loc l.pld_name.txt] [%e kind l.pld_type]
          in
          [%e body]])
      (List.mapi (fun i l -> (i, l)) ls)
      [%expr Yuka.runtime_form_finish _yuka_d (fun () -> [%e build])]
  in
  let encode =
    elist ~loc
      (List.map
         (fun l ->
           [%expr
             Yuka.runtime_form_put [%e estring ~loc l.pld_name.txt] [%e kind l.pld_type]
               [%e pexp_field ~loc [%expr _yuka_v] { loc; txt = Lident l.pld_name.txt }]])
         ls)
  in
  let name_fn =
    pexp_function_cases ~loc
      (List.map (fun l -> case ~lhs:(ppat_variant ~loc (constructor l) None) ~guard:None ~rhs:(estring ~loc l.pld_name.txt)) ls)
  in
  [
    pstr_type ~loc Recursive [ field_type ~loc td ];
    [%stri let [%p pvar ~loc (suffixed n "field_name")] = [%e name_fn]];
    [%stri
      let [%p ppat_constraint ~loc (pvar ~loc (suffixed n "form")) [%type: ([%t record_ty], [%t field_ty]) Yuka.Form.t]] =
        Yuka.runtime_form_fields ~names:[%e names]
          ~decode:(fun _yuka_d -> [%e decode])
          ~encode:(fun (_yuka_v : [%t record_ty]) -> Stdlib.List.concat [%e encode])];
  ]

let sig_items (td : type_declaration) =
  let loc = td.ptype_loc in
  let n = td.ptype_name.txt in
  let field_ty = ptyp_constr ~loc { loc; txt = Lident (suffixed n "field") } [] in
  let record_ty = ptyp_constr ~loc { loc; txt = Lident n } [] in
  [
    psig_type ~loc Recursive [ field_type ~loc td ];
    psig_value ~loc
      (value_description ~loc ~name:{ loc; txt = suffixed n "field_name" } ~type_:[%type: [%t field_ty] -> string] ~prim:[]);
    psig_value ~loc
      (value_description ~loc ~name:{ loc; txt = suffixed n "form" }
         ~type_:[%type: ([%t record_ty], [%t field_ty]) Yuka.Form.t] ~prim:[]);
  ]

let register () =
  ignore
    (Deriving.add "form"
       ~str_type_decl:(Deriving.Generator.V2.make_noarg (fun ~ctxt:_ (_, tds) -> List.concat_map str_items tds))
       ~sig_type_decl:(Deriving.Generator.V2.make_noarg (fun ~ctxt:_ (_, tds) -> List.concat_map sig_items tds)))
