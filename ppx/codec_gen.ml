open Ppxlib
open Ast_builder.Default

let fail ~loc fmt = Location.raise_errorf ~loc ("[yuka] " ^^ fmt)
let codec_name n = if n = "t" then "codec" else n ^ "_codec"
let lid ~loc s = { loc; txt = Lident s }
let var_name prefix i = Printf.sprintf "_yuka_%s%d" prefix i

let mk_codec ~loc enc dec = [%expr Yuka.Codec.make ~encode:[%e enc] ~decode:[%e dec]]
let delayed : string list ref = ref []
let delayed_name n = "_yuka_" ^ codec_name n

let enc_call ~loc c v = [%expr Yuka.Codec.encode [%e c] [%e v]]
let dec_call ~loc c v = [%expr Yuka.Codec.decode [%e c] [%e v]]

let rec chain ~loc steps final =
  match steps with
  | [] -> final
  | (var, codec, json, label) :: rest ->
      let err =
        match label with
        | None -> [%expr Stdlib.Error e]
        | Some l -> [%expr Stdlib.Error ([%e estring ~loc l] ^ ": " ^ e)]
      in
      [%expr
        match [%e dec_call ~loc codec json] with
        | Stdlib.Ok [%p pvar ~loc var] -> [%e chain ~loc rest final]
        | Stdlib.Error e -> [%e err]]

let decode_fields ~loc ~assoc fields final =
  List.fold_right
    (fun (i, (key, codec, optional)) rest ->
      let j = var_name "j" i and v = var_name "v" i in
      let lookup = [%expr _yuka_field [%e estring ~loc key]] in
      let decode = chain ~loc [ (v, codec, evar ~loc j, Some key) ] rest in
      if optional then
        [%expr
          let [%p pvar ~loc j] =
            match [%e lookup] with Some j -> j | None -> `Null
          in
          [%e decode]]
      else
        [%expr
          match [%e lookup] with
          | Some [%p pvar ~loc j] -> [%e decode]
          | None -> Stdlib.Error [%e estring ~loc ("missing field " ^ key)]])
    (List.mapi (fun i f -> (i, f)) fields)
    final
  |> fun body ->
  [%expr
    let _yuka_field _yuka_key =
      Stdlib.List.find_map
        (fun (_yuka_k, _yuka_v) -> if Stdlib.String.equal _yuka_k _yuka_key then Some _yuka_v else None)
        [%e assoc]
    in
    [%e body]]

let is_option (t : core_type) =
  match t.ptyp_desc with
  | Ptyp_constr ({ txt = Lident "option"; _ }, [ _ ]) -> true
  | _ -> false

let param_var a = "_yuka_p_" ^ a

let apply ~loc f = function
  | [] -> f
  | args -> pexp_apply ~loc f (List.map (fun a -> (Nolabel, a)) args)

let rec codec_of_type ~params (t : core_type) =
  let loc = t.ptyp_loc in
  let recur = codec_of_type ~params in
  match t.ptyp_desc with
  | Ptyp_constr ({ txt = Lident (("int" | "string" | "bool" | "float" | "unit") as n); _ }, []) ->
      pexp_ident ~loc { loc; txt = Ldot (Ldot (Lident "Yuka", "Codec"), n) }
  | Ptyp_constr ({ txt = Lident (("list" | "option" | "array") as n); _ }, [ a ]) ->
      let f = pexp_ident ~loc { loc; txt = Ldot (Ldot (Lident "Yuka", "Codec"), n) } in
      [%expr [%e f] [%e recur a]]
  | Ptyp_constr
      ({ txt = Ldot ((Lident "Async" | Ldot (Lident "Yuka", "Async")), "t"); _ }, [ a ]) ->
      [%expr Yuka.Codec.async [%e recur a]]
  | Ptyp_constr
      ( { txt =
            ( Lident "result" | Ldot (Lident "Result", "t") | Ldot (Lident "Stdlib", "result")
            | Ldot (Ldot (Lident "Stdlib", "Result"), "t") );
          _ },
        [ a; e ] ) ->
      [%expr Yuka.Codec.result [%e recur a] [%e recur e]]
  | Ptyp_constr ({ txt = Lident n; _ }, []) when List.mem n !delayed ->
      [%expr [%e evar ~loc (delayed_name n)] ()]
  | Ptyp_constr ({ txt = Lident n; _ }, args) ->
      apply ~loc (evar ~loc (codec_name n)) (List.map recur args)
  | Ptyp_constr ({ txt = Ldot (p, n); _ }, args) ->
      apply ~loc (pexp_ident ~loc { loc; txt = Ldot (p, codec_name n) }) (List.map recur args)
  | Ptyp_var a ->
      if not (List.mem a params) then
        fail ~loc "type variables are not supported here";
      evar ~loc (param_var a)
  | Ptyp_variant _ -> fail ~loc "polymorphic variants are not supported"
  | Ptyp_tuple ts ->
      let n = List.length ts in
      let xs = List.init n (var_name "x") in
      let cs = List.map recur ts in
      let enc =
        [%expr
          fun [%p ppat_tuple ~loc (List.map (pvar ~loc) xs)] ->
            `List
              [%e
                elist ~loc
                  (List.map2 (fun c x -> enc_call ~loc c (evar ~loc x)) cs xs)]]
      in
      let js = List.init n (var_name "j") and vs = List.init n (var_name "v") in
      let final = [%expr Stdlib.Ok [%e pexp_tuple ~loc (List.map (evar ~loc) vs)]] in
      let steps = List.mapi (fun i c -> (List.nth vs i, c, evar ~loc (List.nth js i), None)) cs in
      let dec =
        [%expr
          fun (j : Yuka.Json.t) ->
            match j with
            | `List [%p plist ~loc (List.map (pvar ~loc) js)] -> [%e chain ~loc steps final]
            | _ -> Stdlib.Error [%e estring ~loc (Printf.sprintf "expected a list of %d items" n)]]
      in
      mk_codec ~loc enc dec
  | _ -> fail ~loc "cannot derive a codec for this type"

and plist ~loc ps =
  List.fold_right
    (fun p acc -> ppat_construct ~loc (lid ~loc "::") (Some (ppat_tuple ~loc [ p; acc ])))
    ps
    (ppat_construct ~loc (lid ~loc "[]") None)

let record_codec_parts ~params (labels : label_declaration list) =
  List.map
    (fun (l : label_declaration) ->
      (l.pld_name.txt, codec_of_type ~params l.pld_type, is_option l.pld_type))
    labels

let record_encode ~loc parts record =
  [%expr
    `Assoc
      [%e
        elist ~loc
          (List.map
             (fun (k, c, _) ->
               let field = pexp_field ~loc record (lid ~loc k) in
               [%expr ([%e estring ~loc k], [%e enc_call ~loc c field])])
             parts)]]

let record_decode ~loc ~assoc parts build =
  let names = List.mapi (fun i (k, _, _) -> (k, evar ~loc (var_name "v" i))) parts in
  decode_fields ~loc ~assoc (List.map (fun (k, c, o) -> (k, c, o)) parts)
    [%expr
      Stdlib.Ok
        [%e
          build
            (pexp_record ~loc (List.map (fun (k, e) -> (lid ~loc k, e)) names) None)]]

let variant_codec ~loc ~params tname (cds : constructor_declaration list) =
  let enc_cases, dec_cases =
    List.split
      (List.map
         (fun (cd : constructor_declaration) ->
           let cloc = cd.pcd_loc in
           let cname = cd.pcd_name.txt in
           let clid = lid ~loc:cloc cname in
           let tag = [%expr `String [%e estring ~loc cname]] in
           let tag_pat = ppat_variant ~loc "String" (Some (pstring ~loc cname)) in
           if cd.pcd_res <> None then fail ~loc:cloc "GADT constructors are not supported";
           match cd.pcd_args with
           | Pcstr_tuple [] ->
               ( case ~lhs:(ppat_construct ~loc clid None) ~guard:None ~rhs:tag,
                 case ~lhs:tag_pat ~guard:None
                   ~rhs:[%expr Stdlib.Ok [%e pexp_construct ~loc clid None]] )
           | Pcstr_tuple args ->
               let n = List.length args in
               let xs = List.init n (var_name "x") in
               let js = List.init n (var_name "j") and vs = List.init n (var_name "v") in
               let cs = List.map (fun (a : core_type) -> codec_of_type ~params a) args in
               let pat l =
                 match l with
                 | [ x ] -> x
                 | l -> ppat_tuple ~loc l
               in
               let ex l = match l with [ x ] -> x | l -> pexp_tuple ~loc l in
               let steps = List.mapi (fun i c -> (List.nth vs i, c, evar ~loc (List.nth js i), None)) cs in
               ( case
                   ~lhs:(ppat_construct ~loc clid (Some (pat (List.map (pvar ~loc) xs))))
                   ~guard:None
                   ~rhs:
                     [%expr
                       `List
                         ([%e tag]
                          :: [%e
                               elist ~loc
                                 (List.map2 (fun c x -> enc_call ~loc c (evar ~loc x)) cs xs)])],
                 case
                   ~lhs:(ppat_variant ~loc "List" (Some (plist ~loc (tag_pat :: List.map (pvar ~loc) js))))
                   ~guard:None
                   ~rhs:
                     (chain ~loc steps
                        [%expr
                          Stdlib.Ok
                            [%e
                              pexp_construct ~loc clid
                                (Some (ex (List.map (evar ~loc) vs)))]]) )
           | Pcstr_record labels ->
               let parts = record_codec_parts ~params labels in
               ( case
                   ~lhs:(ppat_construct ~loc clid (Some (pvar ~loc "_yuka_r")))
                   ~guard:None
                   ~rhs:
                     [%expr
                       `List [ [%e tag]; [%e record_encode ~loc parts (evar ~loc "_yuka_r")] ]],
                 case
                   ~lhs:
                     (ppat_variant ~loc "List"
                        (Some
                           (plist ~loc
                              [ tag_pat; ppat_variant ~loc "Assoc" (Some (pvar ~loc "_yuka_fields")) ])))
                   ~guard:None
                   ~rhs:
                     (record_decode ~loc ~assoc:(evar ~loc "_yuka_fields") parts (fun r ->
                          pexp_construct ~loc clid (Some r))) ))
         cds)
  in
  let enc = pexp_function_cases ~loc enc_cases in
  let fallback =
    case ~lhs:(ppat_any ~loc) ~guard:None
      ~rhs:[%expr Stdlib.Error [%e estring ~loc ("invalid " ^ tname)]]
  in
  let dec =
    [%expr
      fun (j : Yuka.Json.t) ->
        [%e pexp_match ~loc [%expr j] (dec_cases @ [ fallback ])]]
  in
  mk_codec ~loc enc dec

let param_names (td : type_declaration) =
  List.map
    (fun ((t : core_type), _) ->
      match t.ptyp_desc with
      | Ptyp_var a -> a
      | _ -> fail ~loc:t.ptyp_loc "type parameters must be named")
    td.ptype_params

let codec_of_decl ~recursive (td : type_declaration) =
  let loc = td.ptype_loc in
  let params = param_names td in
  let tname = td.ptype_name.txt in
  let tconstr =
    ptyp_constr ~loc (lid ~loc tname) (List.map (fun _ -> ptyp_any ~loc) params)
  in
  let body =
    match (td.ptype_kind, td.ptype_manifest) with
    | Ptype_record labels, _ ->
        let parts = record_codec_parts ~params labels in
        let x = evar ~loc "_yuka_x" in
        let enc = [%expr fun (_yuka_x : [%t tconstr]) -> [%e record_encode ~loc parts x]] in
        let dec =
          [%expr
            fun (j : Yuka.Json.t) ->
              match j with
              | `Assoc _yuka_fields ->
                  [%e record_decode ~loc ~assoc:(evar ~loc "_yuka_fields") parts (fun r -> r)]
              | _ -> Stdlib.Error [%e estring ~loc ("expected an object for " ^ tname)]]
        in
        mk_codec ~loc enc dec
    | Ptype_variant cds, _ -> variant_codec ~loc ~params tname cds
    | Ptype_abstract, Some m ->
        let e = codec_of_type ~params m in
        if recursive then
          mk_codec ~loc
            [%expr fun x -> Yuka.Codec.encode [%e e] x]
            [%expr fun j -> Yuka.Codec.decode [%e e] j]
        else e
    | Ptype_abstract, None -> fail ~loc "cannot derive a codec for an abstract type"
    | Ptype_open, _ -> fail ~loc "cannot derive a codec for an extensible type"
  in
  List.fold_right
    (fun a acc -> [%expr fun [%p pvar ~loc (param_var a)] -> [%e acc]])
    params body

let codec_type ~loc (td : type_declaration) =
  let params = param_names td in
  let result =
    [%type:
      [%t
        ptyp_constr ~loc (lid ~loc td.ptype_name.txt)
          (List.map (fun a -> ptyp_var ~loc a) params)]
      Yuka.Codec.t]
  in
  let ty =
    List.fold_right
      (fun a acc -> [%type: [%t ptyp_var ~loc a] Yuka.Codec.t -> [%t acc]])
      params result
  in
  if params = [] then ty else ptyp_poly ~loc (List.map (fun a -> { loc; txt = a }) params) ty

let mentions names (td : type_declaration) =
  let found = ref false in
  let finder =
    object
      inherit Ast_traverse.iter as super

      method! core_type t =
        (match t.ptyp_desc with
         | Ptyp_constr ({ txt = Lident n; _ }, _) when List.mem n names -> found := true
         | _ -> ());
        super#core_type t
    end
  in
  finder#type_declaration td;
  !found

let str_gen ~ctxt:_ (rec_flag, tds) =
  let names = List.map (fun (td : type_declaration) -> td.ptype_name.txt) tds in
  let recursive = rec_flag = Recursive && List.exists (mentions names) tds in
  let binding (td : type_declaration) =
    let loc = td.ptype_loc in
    let name = td.ptype_name.txt in
    if List.mem name !delayed then
      let pat = ppat_constraint ~loc (pvar ~loc (delayed_name name)) [%type: unit -> [%t codec_type ~loc td]] in
      value_binding ~loc ~pat ~expr:[%expr fun () -> [%e codec_of_decl ~recursive td]]
    else
      let pat = ppat_constraint ~loc (pvar ~loc (codec_name name)) (codec_type ~loc td) in
      value_binding ~loc ~pat ~expr:(codec_of_decl ~recursive td)
  in
  if recursive then begin
    delayed := List.filter_map (fun (td : type_declaration) -> if td.ptype_params = [] then Some td.ptype_name.txt else None) tds;
    let group = Fun.protect ~finally:(fun () -> delayed := []) (fun () -> List.map binding tds) in
    let forced =
      List.filter_map
        (fun (td : type_declaration) ->
          let loc = td.ptype_loc and name = td.ptype_name.txt in
          if td.ptype_params = [] then
            Some
              (pstr_value ~loc Nonrecursive
                 [ value_binding ~loc ~pat:(pvar ~loc (codec_name name)) ~expr:[%expr [%e evar ~loc (delayed_name name)] ()] ])
          else None)
        tds
    in
    pstr_value ~loc:(List.hd tds).ptype_loc Recursive group :: forced
  end
  else
    List.map (fun (td : type_declaration) -> pstr_value ~loc:td.ptype_loc Nonrecursive [ binding td ]) tds

let sig_gen ~ctxt:_ (_, tds) =
  List.map
    (fun (td : type_declaration) ->
      let loc = td.ptype_loc in
      let ty =
        match codec_type ~loc td with
        | { ptyp_desc = Ptyp_poly (_, t); _ } -> t
        | t -> t
      in
      psig_value ~loc
        (value_description ~loc ~name:{ loc; txt = codec_name td.ptype_name.txt } ~type_:ty ~prim:[]))
    tds

let register () =
  ignore
    (Deriving.add "codec"
       ~str_type_decl:(Deriving.Generator.V2.make_noarg str_gen)
       ~sig_type_decl:(Deriving.Generator.V2.make_noarg sig_gen))
