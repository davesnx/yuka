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
  | Pparam_val ((Labelled "start" | Optional "start"), _, _) ->
      fail ~loc:p.pparam_loc "the argument 'start' is reserved for the start strategy"
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

let module_path file =
  let path = Code_path.fully_qualified_path (Code_path.top_level ~file_path:file) in
  match !library with
  | Some l -> String.capitalize_ascii l ^ "." ^ path
  | None -> path

let client =
  Attribute.declare_with_attr_loc "yuka.client" Attribute.Context.value_binding
    Ast_pattern.__
    (fun ~attr_loc payload -> (attr_loc, payload))

let is_client vb = Attribute.get client ~mark_as_seen:false vb <> None

let check_attributes (attrs : attribute list) =
  List.iter
    (fun (a : attribute) ->
      let n = a.attr_name.txt in
      if String.starts_with ~prefix:"yuka." n then
        fail ~loc:a.attr_loc "unknown attribute [@%s] on a let[@client] binding" n)
    attrs

let expand (item : structure_item) =
  let loc = item.pstr_loc in
  let file = loc.loc_start.pos_fname in
  if file <> "" && file <> "_none_" && not (Filename.check_suffix file ".mlx") then
    fail ~loc "let[@client] is allowed only in .mlx files: rename %s to %s.mlx"
      (Filename.basename file)
      (Filename.remove_extension (Filename.basename file));
  match item.pstr_desc with
  | Pstr_value (Nonrecursive, [ vb ]) -> (
      let vb, (attr_loc, payload) = Option.get (Attribute.consume client vb) in
      (match payload with
       | PStr [] -> ()
       | _ -> fail ~loc:attr_loc "[@client] takes no options yet: write let[@client] make");
      check_attributes vb.pvb_attributes;
      let item = { item with pstr_desc = Pstr_value (Nonrecursive, [ vb ]) } in
      (match vb.pvb_pat.ppat_desc with
       | Ppat_var { txt = "make"; _ } -> ()
       | _ -> fail ~loc "let[@client] must define 'make'");
      match vb.pvb_expr.pexp_desc with
      | Pexp_function (params, _, Pfunction_body _) ->
          let rev = List.rev params in
          (match rev with
           | last :: _ -> (
               match last.pparam_desc with
               | Pparam_val (Nolabel, None, p) when unit_pattern p -> ()
               | _ -> fail ~loc:last.pparam_loc "the last parameter must be ()")
           | [] -> fail ~loc "let[@client] needs arguments");
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
          let name = estring ~loc (module_path file) in
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
            @ [ { pparam_loc = loc; pparam_desc = Pparam_val (Optional "start", None, pvar ~loc "start") };
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
              (Yuka.runtime_island ?start ~name:[%e name] ~props:[%e props] (fun () -> [%e call])
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
                Yuka.runtime_entry ~name:[%e name] (fun (j : Yuka.Json.t) ->
                    match j with
                    | `Assoc _yuka_fields ->
                        [%e Codec_gen.decode_fields ~loc ~assoc:[%expr _yuka_fields] fields ok]
                    | _ -> Stdlib.Error "expected an object")]
          in
          let name_item = [%stri let name = [%e name]] in
          pstr_include ~loc
            (include_infos ~loc (pmod_structure ~loc [ item; name_item; island; register ]))
      | _ -> fail ~loc "let[@client] needs a function")
  | _ -> fail ~loc "let[@client] takes one non-recursive let binding"

let check_placement (top : structure) =
  let top =
    List.map
      (fun i ->
        match i.pstr_desc with
        | Pstr_value (_, vbs) when List.exists is_client vbs -> expand i
        | _ -> i)
      top
  in
  let checker =
    object
      inherit Ast_traverse.iter as super

      method! value_binding vb =
        if is_client vb then
          fail ~loc:vb.pvb_loc
            "let[@client] is allowed only at the top level of a file, not inside a module or a function";
        super#value_binding vb

      method! extension (({ txt; loc }, _) as e) =
        if txt = "client" || txt = "yuka.client" then
          fail ~loc "let%%%s is now let[@%s]" txt txt;
        super#extension e
    end
  in
  checker#structure top;
  top
