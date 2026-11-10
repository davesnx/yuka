open Ppxlib
open Ast_builder.Default

let has_attr name e =
  List.exists (fun (a : attribute) -> a.attr_name.txt = name) e.pexp_attributes

let is_jsx = has_attr "JSX"
let strip_jsx e = { e with pexp_attributes = List.filter (fun (a : attribute) -> a.attr_name.txt <> "JSX") e.pexp_attributes }

let is_state_path = function
  | Lident "State" | Ldot (Lident "Yuka", "State") -> true
  | _ -> false

let reads_state e =
  let found = ref false in
  let finder =
    object
      inherit Ast_traverse.iter as super

      method! expression e =
        match e.pexp_desc with
        | Pexp_function _ -> ()
        | _ when is_jsx e -> ()
        | Pexp_ident { txt = Ldot (p, "get"); _ } when is_state_path p ->
            found := true
        | _ -> super#expression e
    end
  in
  finder#expression e;
  !found

let issues = "reads must be written State.get so that the ppx can find holes (open Yuka is allowed: State.get still works)"

let lint_error ~loc what =
  Location.raise_errorf ~loc "[yuka] %s is not allowed: %s." what issues

let is_yuka_state (m : module_expr) =
  match m.pmod_desc with
  | Pmod_ident { txt = Ldot (Lident "Yuka", "State"); _ } -> true
  | _ -> false

let check_open ~loc (o : open_declaration) what =
  if is_yuka_state o.popen_expr then lint_error ~loc what

let shared =
  Attribute.declare "yuka.shared" Attribute.Context.value_binding
    Ast_pattern.(pstr nil)
    ()

let rec state_constructor e =
  match e.pexp_desc with
  | Pexp_constraint (e, _) | Pexp_coerce (e, _, _) -> state_constructor e
  | Pexp_apply ({ pexp_desc = Pexp_ident { txt = Ldot (p, (("make" | "memo") as f)); _ }; _ }, _)
    when is_state_path p -> Some f
  | _ -> None

let check_module_state (vb : value_binding) =
  match state_constructor vb.pvb_expr with
  | Some f when Attribute.get shared vb = None ->
      Location.raise_errorf ~loc:vb.pvb_loc
        "[yuka] A module-level State.%s is one value for the whole server process: every request would read and write the same State. Create the State inside a function. If only client code paths write it, mark the binding with [@@@@yuka.shared]." f
  | _ -> ()

let list_expr ~loc xs =
  List.fold_right (fun x acc -> [%expr [%e x] :: [%e acc]]) xs [%expr []]

let polyvariant_type ~loc options =
  ptyp_variant ~loc
    (List.map
       (fun (o : Html_attributes.polyvariant) ->
         { prf_desc = Rtag ({ loc; txt = o.type_ }, true, []); prf_loc = loc; prf_attributes = [] })
       options)
    Closed None

let value_type ~loc : Html_attributes.kind -> core_type = function
  | String -> [%type: string]
  | Int -> [%type: int]
  | Bool | BooleanishString -> [%type: bool]
  | Polyvariant options -> polyvariant_type ~loc options

let to_string ~loc (kind : Html_attributes.kind) v =
  match kind with
  | String | Bool -> v
  | Int -> [%expr Stdlib.string_of_int [%e v]]
  | BooleanishString -> [%expr Stdlib.string_of_bool [%e v]]
  | Polyvariant options ->
      let cases =
        List.map
          (fun (o : Html_attributes.polyvariant) ->
            case ~lhs:(ppat_variant ~loc o.type_ None) ~guard:None ~rhs:(estring ~loc o.jsxName))
          options
      in
      pexp_match ~loc v cases

let option_string ~loc ~optional (kind : Html_attributes.kind) value =
  let ty = value_type ~loc kind in
  match (kind, optional) with
  | Bool, false -> [%expr if ([%e value] : bool) then Some "" else None]
  | Bool, true ->
      [%expr match ([%e value] : bool option) with Some true -> Some "" | _ -> None]
  | _, false -> [%expr Some [%e to_string ~loc kind [%expr ([%e value] : [%t ty])]]]
  | _, true ->
      [%expr
        Stdlib.Option.map
          (fun v -> [%e to_string ~loc kind [%expr (v : [%t ty])]])
          ([%e value] : [%t ty] option)]

type prop =
  | Plain of expression
  | Maybe of expression

let attribute_name_of_prop = function
  | Html_attributes.Attribute { name; _ } -> name
  | Rich_attribute { name; _ } -> name
  | Event { jsxName; _ } -> jsxName

let svg_presentation =
  [ "alignment-baseline"; "baseline-shift"; "clip-path"; "clip-rule"; "color-interpolation";
    "color-interpolation-filters"; "dominant-baseline"; "fill-opacity"; "fill-rule";
    "flood-color"; "flood-opacity"; "font-family"; "font-size"; "font-size-adjust";
    "font-stretch"; "font-style"; "font-variant"; "font-weight"; "letter-spacing";
    "lighting-color"; "marker-end"; "marker-mid"; "marker-start"; "mask-type"; "paint-order";
    "pointer-events"; "shape-rendering"; "stop-color"; "stop-opacity"; "stroke-dasharray";
    "stroke-dashoffset"; "stroke-linecap"; "stroke-linejoin"; "stroke-miterlimit";
    "stroke-opacity"; "stroke-width"; "text-anchor"; "text-decoration"; "text-rendering";
    "transform-origin"; "unicode-bidi"; "vector-effect"; "word-spacing"; "writing-mode" ]

let camel_of_kebab k =
  let b = Buffer.create (String.length k) in
  let up = ref false in
  String.iter
    (fun c ->
      if c = '-' then up := true
      else (
        Buffer.add_char b (if !up then Char.uppercase_ascii c else c);
        up := false))
    k;
  Buffer.contents b

let svg_overrides =
  ("xlinkHref", "xlink:href")
  :: List.map (fun k -> (camel_of_kebab k, k)) svg_presentation

let svg_override tag label =
  if not (Html.is_svg_element tag) then None
  else
    match List.assoc_opt label svg_overrides with
    | None -> None
    | Some name -> (
        match Html.findByName tag label with
        | Ok (Html_attributes.Attribute { name = n; _ } as p) when n = name -> Some p
        | _ ->
            Some (Html_attributes.Attribute { name; jsxName = label; type_ = String }))

let find_prop ~loc tag label =
  match svg_override tag label with
  | Some p -> p
  | None ->
  let key =
    if String.length label > 2 && String.sub label 0 2 = "on" then
      String.lowercase_ascii label
    else label
  in
  let generic () =
    let prefixed p = String.starts_with ~prefix:p label in
    if prefixed "aria_" then
      Some
        (Html_attributes.Attribute
           { name = String.map (fun c -> if c = '_' then '-' else c) label;
             jsxName = label; type_ = String })
    else None
  in
  match Html.findByName tag key with
  | Ok (Html_attributes.Event { jsxName; _ })
    when String.ends_with ~suffix:"capture" jsxName ->
      Location.raise_errorf ~loc
        "[yuka] The event '%s' is not supported: capture handlers do not exist." label
  | Ok p -> p
  | Error `ElementNotFound ->
      Location.raise_errorf ~loc "[yuka] HTML tag '%s' does not exist." tag
  | Error (`AttributeNotFound suggestion) -> (
      match generic () with
      | Some p -> p
      | None ->
          let hint =
            match suggestion with
            | Some s -> Printf.sprintf " Maybe you mean '%s'?" s
            | None -> ""
          in
          Location.raise_errorf ~loc
            "[yuka] The attribute '%s' is not valid on a '%s' element.%s" label tag hint)

let event_name jsx = String.sub jsx 2 (String.length jsx - 2)

let rewrite_attribute ~self ~loc tag (label, value) =
  let name, optional =
    match label with
    | Labelled n -> (n, false)
    | Optional n -> (n, true)
    | Nolabel -> Location.raise_errorf ~loc "[yuka] Unexpected positional argument."
  in
  let vloc = value.pexp_loc in
  let prop = find_prop ~loc:vloc tag name in
  match prop with
  | Event { jsxName; _ } ->
      let ev = estring ~loc (event_name jsxName) in
      let value = self#expression value in
      if optional then Maybe [%expr Stdlib.Option.map (Yuka.on [%e ev]) [%e value]]
      else Plain [%expr Yuka.on [%e ev] [%e value]]
  | Attribute { type_ = kind; name = dom; _ } | Rich_attribute { type_ = kind; name = dom; _ } ->
      let dom_e = estring ~loc dom in
      let hole = reads_state value in
      let value = self#expression value in
      if hole then
        Plain
          [%expr
            Yuka.hole_attr [%e dom_e]
              (fun () -> [%e option_string ~loc ~optional kind value])]
      else if optional || kind = Bool then
        Maybe
          [%expr
            Stdlib.Option.map (Yuka.attr [%e dom_e])
              [%e option_string ~loc ~optional kind value]]
      else
        let ty = value_type ~loc kind in
        Plain
          [%expr
            Yuka.attr [%e dom_e]
              [%e to_string ~loc kind [%expr ([%e value] : [%t ty])]]]

let attributes_expr ~loc props =
  if List.for_all (function Plain _ -> true | Maybe _ -> false) props then
    list_expr ~loc (List.map (function Plain e | Maybe e -> e) props)
  else
    let items =
      List.map
        (function Plain e -> [%expr Some [%e e]] | Maybe e -> e)
        props
    in
    [%expr Stdlib.List.filter_map (fun x -> x) [%e list_expr ~loc items]]

let rec list_items e =
  match e.pexp_desc with
  | Pexp_construct ({ txt = Lident "[]"; _ }, None) -> []
  | Pexp_construct
      ({ txt = Lident "::"; _ }, Some { pexp_desc = Pexp_tuple [ x; rest ]; _ }) ->
      x :: list_items rest
  | _ -> Location.raise_errorf ~loc:e.pexp_loc "[yuka] Unexpected children."

let inside_template = ref false

let outside_template f =
  let saved = !inside_template in
  inside_template := false;
  let r = f () in
  inside_template := saved;
  r

let rec is_literal e =
  match e.pexp_desc with
  | Pexp_constant _ -> true
  | Pexp_construct ({ txt = Lident ("true" | "false" | "()"); _ }, None) -> true
  | Pexp_variant (_, None) -> true
  | Pexp_constraint (e, _) -> is_literal e
  | _ -> false

let is_event_label tag label =
  String.length label > 2
  && String.sub label 0 2 = "on"
  && match Html.findByName tag (String.lowercase_ascii label) with
     | Ok (Html_attributes.Event _) -> true
     | _ -> false

let rec fixed_elements e =
  match e.pexp_desc with
  | Pexp_apply ({ pexp_desc = Pexp_ident { txt = Lident tag; _ }; _ }, args)
    when Html.is_html_element tag || Html.is_svg_element tag -> (
      let attrs_ok =
        List.for_all
          (fun (l, v) ->
            match l with
            | Nolabel -> true
            | Labelled "children" -> true
            | Labelled name ->
                is_literal v || reads_state v || is_event_label tag name
            | Optional _ -> false)
          args
      in
      if not attrs_ok then None
      else
        let children =
          List.concat_map (function Labelled "children", c -> [ c ] | _ -> []) args
        in
        match children with
        | [ c ] -> (
            let kids = try list_items c with _ -> [] in
            let counts =
              List.map
                (fun k ->
                  match k.pexp_desc with
                  | Pexp_constant (Pconst_string _) when not (is_jsx k) -> Some 0
                  | _ when is_jsx k -> fixed_elements k
                  | _ -> if reads_state k then Some 0 else None)
                kids
            in
            if List.mem None counts then None
            else Some (1 + List.fold_left (fun a c -> a + Option.value c ~default:0) 0 counts))
        | _ -> None)
  | _ -> None

let template_id (loc : Location.t) =
  let file = Filename.basename loc.loc_start.pos_fname in
  let file = match String.index_opt file '.' with Some i -> String.sub file 0 i | None -> file in
  let lib = match !Island.library with Some l -> l ^ "/" | None -> "" in
  Printf.sprintf "%s%s:%d:%d" lib file loc.loc_start.pos_lnum
    (loc.loc_start.pos_cnum - loc.loc_start.pos_bol)

let rewrite_child ~self child =
  let loc = child.pexp_loc in
  match child.pexp_desc with
  | Pexp_constant (Pconst_string _) when not (is_jsx child) ->
      [%expr Yuka.text [%e child]]
  | _ when is_jsx child -> self#expression child
  | _ ->
      let hole = reads_state child in
      let child = outside_template (fun () -> self#expression child) in
      if hole then [%expr Yuka.hole (fun () -> [%e child])] else child

let split_args args =
  let children = ref [] and props = ref [] in
  List.iter
    (fun (l, e) ->
      match (l, e) with
      | Nolabel, _ -> ()
      | Labelled "children", e -> children := list_items e
      | l, e -> props := !props @ [ (l, e) ])
    args;
  (!props, !children)

let rewrite_jsx self e =
  let loc = e.pexp_loc in
  let fixed = match fixed_elements e with Some n when n >= 2 -> true | _ -> false in
  let e = strip_jsx e in
  match e.pexp_desc with
  | Pexp_apply ({ pexp_desc = Pexp_ident { txt = fn; loc = fnloc }; _ }, args) -> (
      let props, children = split_args args in
      match fn with
      | Lident tag ->
          if not (Html.is_html_element tag || Html.is_svg_element tag) then
            Location.raise_errorf ~loc:fnloc "[yuka] HTML tag '%s' does not exist." tag;
          let wrap = fixed && not !inside_template in
          let attrs =
            outside_template (fun () ->
                List.map (rewrite_attribute ~self ~loc:fnloc tag) props)
          in
          let saved = !inside_template in
          inside_template := saved || wrap;
          let kids = List.map (rewrite_child ~self) children in
          inside_template := saved;
          let r =
            [%expr Yuka.lower [%e estring ~loc tag] [%e attributes_expr ~loc attrs] [%e list_expr ~loc kids]]
          in
          if wrap then [%expr Yuka.template [%e estring ~loc (template_id loc)] [%e r]] else r
      | Ldot (Ldot (Lident "Yuka", "Await"), "createElement") ->
          let find name =
            List.find_opt (fun (l, _) -> l = Labelled name || l = Optional name) props
          in
          List.iter
            (fun (l, _) ->
              match l with
              | Labelled ("async" | "loading" | "failed") | Optional "failed" -> ()
              | _ ->
                  Location.raise_errorf ~loc:fnloc
                    "[yuka] Yuka.Await takes async, loading and failed")
            props;
          let required name =
            match find name with
            | Some (Labelled _, v) -> v
            | _ ->
                Location.raise_errorf ~loc:fnloc "[yuka] Yuka.Await needs the prop '%s'" name
          in
          let async = required "async" and loading = required "loading" in
          let failed =
            match find "failed" with
            | Some (l, v) -> [ (l, self#expression v) ]
            | None -> []
          in
          let body =
            match children with
            | [ ({ pexp_desc = Pexp_function _; _ } as f) ] -> self#expression f
            | _ ->
                Location.raise_errorf ~loc:fnloc
                  "[yuka] Yuka.Await needs exactly one child, a function such as (fun value -> ...)"
          in
          pexp_apply ~loc
            (pexp_ident ~loc:fnloc
               { txt = Ldot (Ldot (Lident "Yuka", "Await"), "make"); loc = fnloc })
            ([ (Labelled "async", self#expression async);
               (Labelled "loading", rewrite_child ~self loading) ]
            @ failed
            @ [ (Labelled "children", body); (Nolabel, [%expr ()]) ])
      | Ldot (Ldot (Lident "Yuka", "Client"), "createElement") ->
          let loading =
            List.map
              (fun (l, v) ->
                match l with
                | Labelled "loading" | Optional "loading" -> (l, self#expression v)
                | _ -> Location.raise_errorf ~loc:fnloc "[yuka] Yuka.Client takes no props except loading")
              props
          in
          (match children with
           | [ ({ pexp_desc = Pexp_apply ({ pexp_desc = Pexp_ident { txt = Ldot (path, "createElement"); loc = cloc }; _ }, cargs); _ } as child) ]
             when is_jsx child ->
               let cprops, ckids = split_args cargs in
               let cprops = List.map (fun (l, v) -> (l, self#expression v)) cprops in
               let kids = List.map (rewrite_child ~self) ckids in
               let slot =
                 match kids with
                 | [] -> []
                 | [ k ] -> [ (Labelled "children", [%expr Yuka.Slot.make [%e k]]) ]
                 | ks ->
                     [ (Labelled "children", [%expr Yuka.Slot.make (Yuka.fragment [%e list_expr ~loc ks])]) ]
               in
               pexp_apply ~loc
                 (pexp_ident ~loc:cloc { txt = Ldot (path, "island"); loc = cloc })
                 (loading @ cprops @ slot @ [ (Nolabel, [%expr ()]) ])
           | _ ->
               Location.raise_errorf ~loc:fnloc
                 "[yuka] Yuka.Client needs exactly one child, a component tag such as <M a=1 />")
      | Ldot (path, "createElement") ->
          let props = List.map (fun (l, v) -> (l, self#expression v)) props in
          let kids = List.map (rewrite_child ~self) children in
          let children_arg =
            match kids with
            | [] -> []
            | [ k ] -> [ (Labelled "children", k) ]
            | ks -> [ (Labelled "children", [%expr Yuka.fragment [%e list_expr ~loc ks]]) ]
          in
          pexp_apply ~loc
            (pexp_ident ~loc:fnloc { txt = Ldot (path, "make"); loc = fnloc })
            (props @ children_arg @ [ (Nolabel, [%expr ()]) ])
      | _ ->
          let props = List.map (fun (l, v) -> (l, self#expression v)) props in
          let kids = List.map (rewrite_child ~self) children in
          pexp_apply ~loc
            (pexp_ident ~loc:fnloc { txt = fn; loc = fnloc })
            (props @ [ (Labelled "children", list_expr ~loc kids); (Nolabel, [%expr ()]) ]))
  | _ -> e

let is_unapplied_mount args =
  match List.rev args with
  | (Nolabel, { pexp_desc = Pexp_construct ({ txt = Lident "()"; _ }, None); _ }) :: rest ->
      not
        (List.exists
           (fun (l, _) -> match l with Labelled "islands" | Optional "islands" -> true | _ -> false)
           rest)
  | _ -> false

let mapper =
  object (self)
    inherit Ast_traverse.map as super

    method! expression e =
      if is_jsx e then rewrite_jsx self e
      else
        match e.pexp_desc with
        | Pexp_open (o, _) ->
            check_open ~loc:e.pexp_loc o "a local open of Yuka.State";
            super#expression e
        | Pexp_apply
            ( ({ pexp_desc = Pexp_ident { txt = Ldot (Lident "Yuka", "mount"); _ }; _ } as f),
              args )
          when is_unapplied_mount args ->
            let loc = e.pexp_loc in
            let args = List.map (fun (l, a) -> (l, self#expression a)) args in
            let rev = List.rev args in
            let unit_arg = List.hd rev in
            let rest = List.rev (List.tl rev) in
            { e with
              pexp_desc =
                Pexp_apply
                  ( f,
                    rest
                    @ [ (Labelled "islands", [%expr Yuka_islands.registry]); unit_arg ] ) }
        | Pexp_letmodule (n, m, _) when n.txt <> Some "State" && is_yuka_state m ->
            lint_error ~loc:e.pexp_loc "a local alias of Yuka.State"
        | _ -> super#expression e

    method! structure_item i =
      (match i.pstr_desc with
       | Pstr_value (_, vbs) -> List.iter check_module_state vbs
       | Pstr_open o -> check_open ~loc:i.pstr_loc o "open Yuka.State"
       | Pstr_include { pincl_mod; _ } when is_yuka_state pincl_mod ->
           lint_error ~loc:i.pstr_loc "include Yuka.State"
       | Pstr_module { pmb_name = { txt = Some n; _ }; pmb_expr; _ }
         when n <> "State" && is_yuka_state pmb_expr ->
           lint_error ~loc:i.pstr_loc "a module alias of Yuka.State"
       | _ -> ());
      super#structure_item i

    method! signature_item i =
      (match i.psig_desc with
       | Psig_open { popen_expr = { txt = Ldot (Lident "Yuka", "State"); _ }; _ } ->
           lint_error ~loc:i.psig_loc "open Yuka.State"
       | _ -> ());
      super#signature_item i
  end

let () =
  Codec_gen.register ();
  Driver.register_transformation "yuka"
    ~preprocess_impl:Island.check_placement
    ~rules:[ Context_free.Rule.extension Island.extension ]
    ~impl:mapper#structure ~intf:mapper#signature
