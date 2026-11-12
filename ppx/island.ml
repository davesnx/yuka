open Ppxlib
open Ast_builder.Default

let fail ~loc fmt = Location.raise_errorf ~loc ("[yuka] " ^^ fmt)
let library = ref None

let () =
  Driver.Cookies.add_simple_handler "library-name"
    Ast_pattern.(estring __)
    ~f:(fun v -> library := v)

type arg = { label : string; optional : bool; codec : expression }

let unit_pattern p =
  match p.ppat_desc with
  | Ppat_construct ({ txt = Lident "()"; _ }, None) -> true
  | _ -> false

let analyse_param (p : function_param) =
  match p.pparam_desc with
  | Pparam_newtype _ -> fail ~loc:p.pparam_loc "type parameters are not supported yet"
  | Pparam_val (Nolabel, _, _) -> `Positional p
  | Pparam_val (Labelled "children", None, { ppat_desc = Ppat_constraint (_, { ptyp_desc = Ptyp_constr ({ txt = Lident "slot" | Ldot (Lident "Yuka", "slot"); _ }, []); _ }); _ }) ->
      `Arg { label = "children"; optional = false; codec = (let loc = p.pparam_loc in [%expr Yuka.Codec.slot]) }
  | Pparam_val ((Labelled "children" | Optional "children"), _, _) ->
      fail ~loc:p.pparam_loc "~children must be written ~(children : Yuka.slot)"
  | Pparam_val ((Labelled "loading" | Optional "loading"), _, _) ->
      fail ~loc:p.pparam_loc "the argument 'loading' is reserved for the start strategy"
  | Pparam_val ((Labelled "make" | Optional "make"), _, _) ->
      fail ~loc:p.pparam_loc "the argument 'make' would hide the component make; give the prop another name"
  | Pparam_val (((Labelled label | Optional label) as l), default, pat) ->
      let loc = p.pparam_loc in
      let ty =
        match pat.ppat_desc with
        | Ppat_constraint (_, ty) -> ty
        | _ -> fail ~loc "the argument '%s' needs a type annotation" label
      in
      let optional = match l with Optional _ -> true | _ -> false in
      let option_ty =
        if optional && default <> None then [%type: [%t ty] option] else ty
      in
      if optional && default = None && not (Codec_gen.is_option ty) then
        fail ~loc "the optional argument '%s' without default must have an option type" label;
      `Arg { label; optional; codec = Codec_gen.codec_of_type ~params:[] option_ty }

let module_path ctxt =
  let path = Code_path.fully_qualified_path (Expansion_context.Extension.code_path ctxt) in
  match !library with
  | Some l -> String.capitalize_ascii l ^ "." ^ path
  | None -> path

let expand ~ctxt (items : structure) =
  let loc = Expansion_context.Extension.extension_point_loc ctxt in
  match items with
  | [ { pstr_desc = Pstr_value (Nonrecursive, [ vb ]); _ } as item ] -> (
      (match vb.pvb_pat.ppat_desc with
       | Ppat_var { txt = "make"; _ } -> ()
       | _ -> fail ~loc "let%%client must define 'make'");
      match vb.pvb_expr.pexp_desc with
      | Pexp_function (params, _, Pfunction_body _) ->
          let rev = List.rev params in
          (match rev with
           | last :: _ -> (
               match last.pparam_desc with
               | Pparam_val (Nolabel, None, p) when unit_pattern p -> ()
               | _ -> fail ~loc:last.pparam_loc "the last parameter must be ()")
           | [] -> fail ~loc "let%%client needs arguments");
          let args =
            List.filter_map
              (fun p ->
                match analyse_param p with
                | `Arg a -> Some a
                | `Positional p -> (
                    match p.pparam_desc with
                    | Pparam_val (_, _, pat) when unit_pattern pat -> None
                    | _ -> fail ~loc:p.pparam_loc "only labelled arguments are supported"))
              params
          in
          let name = estring ~loc (module_path ctxt) in
          let label_of a = if a.optional then Optional a.label else Labelled a.label in
          let call =
            pexp_apply ~loc (evar ~loc "make")
              (List.map (fun a -> (label_of a, evar ~loc a.label)) args
              @ [ (Nolabel, [%expr ()]) ])
          in
          let island_params =
            List.map
              (fun a ->
                { pparam_loc = loc;
                  pparam_desc = Pparam_val (label_of a, None, pvar ~loc a.label) })
              args
            @ [ { pparam_loc = loc; pparam_desc = Pparam_val (Optional "loading", None, pvar ~loc "loading") };
                { pparam_loc = loc; pparam_desc = Pparam_val (Nolabel, None, [%pat? ()]) } ]
          in
          let props =
            [%expr
              `Assoc
                [%e
                  elist ~loc
                    (List.map
                       (fun a ->
                         [%expr
                           ( [%e estring ~loc a.label],
                             [%e Codec_gen.enc_call ~loc a.codec (evar ~loc a.label)] )])
                       args)]]
          in
          let island_body =
            [%expr
              (Yuka.Client.island ?loading ~name:[%e name] ~props:[%e props] (fun () -> [%e call])
                : Yuka.server Yuka.element)]
          in
          let island =
            [%stri
              let island =
                [%e pexp_function ~loc island_params None (Pfunction_body island_body)]]
          in
          let fields =
            List.map (fun a -> (a.label, a.codec, a.optional)) args
          in
          let ok = [%expr Stdlib.Ok (fun () -> [%e call])] in
          let rebind =
            List.mapi
              (fun i a -> value_binding ~loc ~pat:(pvar ~loc a.label) ~expr:(evar ~loc (Codec_gen.var_name "v" i)))
              args
          in
          let ok =
            List.fold_right
              (fun vb acc -> pexp_let ~loc Nonrecursive [ vb ] acc)
              rebind ok
          in
          let register =
            [%stri
              let register =
                Yuka.Client.entry ~name:[%e name] (fun (j : Yuka.Json.t) ->
                    match j with
                    | `Assoc _yuka_fields ->
                        [%e Codec_gen.decode_fields ~loc ~assoc:[%expr _yuka_fields] fields ok]
                    | _ -> Stdlib.Error "expected an object")]
          in
          let name_item = [%stri let name = [%e name]] in
          pstr_include ~loc
            (include_infos ~loc (pmod_structure ~loc [ item; name_item; island; register ]))
      | _ -> fail ~loc "let%%client needs a function")
  | _ -> fail ~loc "let%%client takes one non-recursive let binding"

let extension =
  Extension.V3.declare "yuka.client" Extension.Context.structure_item
    Ast_pattern.(pstr __)
    expand

let check_attributes (attrs : attribute list) =
  List.iter
    (fun (a : attribute) ->
      let n = a.attr_name.txt in
      if String.starts_with ~prefix:"yuka." n then
        fail ~loc:a.attr_loc "unknown attribute [@%s] on a let%%client binding" n)
    attrs

let check_placement (top : structure) =
  let checker =
    object
      inherit Ast_traverse.iter as super

      method! structure_item i =
        (match i.pstr_desc with
         | Pstr_extension (({ txt = "client" | "yuka.client"; _ }, payload), attrs) ->
             let file = i.pstr_loc.loc_start.pos_fname in
             if
               file <> "" && file <> "_none_"
               && not (Filename.check_suffix file ".mlx")
             then
               fail ~loc:i.pstr_loc
                 "let%%client is allowed only in .mlx files: rename %s to %s.mlx"
                 (Filename.basename file)
                 (Filename.remove_extension (Filename.basename file));
             if not (List.memq i top) then
               fail ~loc:i.pstr_loc
                 "let%%client is allowed only at the top level of a file, not inside a module or a function";
             check_attributes attrs;
             (match payload with
              | PStr [ { pstr_desc = Pstr_value (_, vbs); _ } ] ->
                  List.iter
                    (fun (vb : value_binding) ->
                      check_attributes vb.pvb_attributes)
                    vbs
              | _ -> ())
         | _ -> ());
        super#structure_item i
    end
  in
  checker#structure top;
  top
