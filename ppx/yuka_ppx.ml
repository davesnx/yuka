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

let snake_of_camel s =
  let b = Buffer.create (String.length s + 4) in
  String.iter
    (fun c ->
      if c >= 'A' && c <= 'Z' then (
        Buffer.add_char b '_';
        Buffer.add_char b (Char.lowercase_ascii c))
      else Buffer.add_char b c)
    s;
  Buffer.contents b

let camel_of_snake s =
  let n = String.length s in
  let b = Buffer.create n in
  let up = ref false in
  String.iteri
    (fun i c ->
      if c = '_' && i > 0 && i < n - 1 then up := true
      else (
        Buffer.add_char b (if !up then Char.uppercase_ascii c else c);
        up := false))
    s;
  Buffer.contents b

let event_name jsx = String.sub jsx 2 (String.length jsx - 2)

let label_of_prop = function
  | Html_attributes.Event { jsxName; _ } -> "on_" ^ event_name jsxName
  | p -> snake_of_camel (Html.getJSXName p)

let has_upper s = String.exists (fun c -> c >= 'A' && c <= 'Z') s

let snake_hint label =
  if String.length label > 2 && String.sub label 0 2 = "on" && label.[2] >= 'A' && label.[2] <= 'Z'
  then "on_" ^ String.lowercase_ascii (String.sub label 2 (String.length label - 2))
  else snake_of_camel label

let table_keys label =
  if String.starts_with ~prefix:"on_" label then [ "on" ^ String.sub label 3 (String.length label - 3) ]
  else [ label; camel_of_snake label ]

let lookup tag label =
  let rec go = function
    | [] -> Error (`AttributeNotFound None)
    | key :: rest -> (
        match Html.findByName tag key with
        | Ok p when label_of_prop p = label -> Ok p
        | Error `ElementNotFound -> Error `ElementNotFound
        | Ok _ | Error (`AttributeNotFound _) -> go rest)
  in
  go (table_keys label)

let suggestion tag label =
  match Hashtbl.find_opt (Lazy.force Html.element_index) tag with
  | Some (element, _) ->
      Html.find_closest_name label (List.map label_of_prop element.Html_attributes.attributes)
  | None -> None

let svg_overrides =
  ("xlink_href", "xlink:href")
  :: List.map (fun k -> (String.map (fun c -> if c = '-' then '_' else c) k, k)) svg_presentation

let svg_override tag label =
  if not (Html.is_svg_element tag) then None
  else
    match List.assoc_opt label svg_overrides with
    | None -> None
    | Some name -> (
        match lookup tag label with
        | Ok (Html_attributes.Attribute { name = n; _ } as p) when n = name -> Some p
        | _ ->
            Some (Html_attributes.Attribute { name; jsxName = label; type_ = String }))

let find_prop ~loc tag label =
  if has_upper label then
    Location.raise_errorf ~loc "[yuka] Write '%s' as '%s'." label (snake_hint label);
  match svg_override tag label with
  | Some p -> p
  | None ->
  let generic () =
    let prefixed p = String.starts_with ~prefix:p label in
    if prefixed "aria_" then
      Some
        (Html_attributes.Attribute
           { name = String.map (fun c -> if c = '_' then '-' else c) label;
             jsxName = label; type_ = String })
    else None
  in
  match lookup tag label with
  | Ok (Html_attributes.Event { jsxName; _ })
    when String.ends_with ~suffix:"capture" jsxName ->
      Location.raise_errorf ~loc
        "[yuka] The event '%s' is not supported: capture handlers do not exist." label
  | Ok p -> p
  | Error `ElementNotFound ->
      Location.raise_errorf ~loc "[yuka] HTML tag '%s' does not exist." tag
  | Error (`AttributeNotFound _) -> (
      match generic () with
      | Some p -> p
      | None ->
          let hint =
            match suggestion tag label with
            | Some s -> Printf.sprintf " Maybe you mean '%s'?" s
            | None -> ""
          in
          Location.raise_errorf ~loc
            "[yuka] The attribute '%s' is not valid on a '%s' element.%s" label tag hint)

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
      (match value.pexp_desc with
      | Pexp_constant (Pconst_string _) ->
          Location.raise_errorf ~loc:vloc "[yuka] %s takes a function, not a string: write %s=(fun event -> ...)." name name
      | _ -> ());
      let ev = estring ~loc (event_name jsxName) in
      let value = self#expression value in
      if optional then Maybe [%expr Stdlib.Option.map (Yuka.on [%e ev]) [%e value]]
      else Plain [%expr Yuka.on [%e ev] [%e value]]
  | Attribute { type_ = kind; name = dom; _ } | Rich_attribute { type_ = kind; name = dom; _ } ->
      if not (Url.valid_name dom) then Location.raise_errorf ~loc:vloc "[yuka] %S is not a valid attribute name." dom;
      let dom_e = estring ~loc dom in
      let hole = reads_state value in
      let value = self#expression value in
      let url = Url.checked ~tag:(String.lowercase_ascii tag) (String.lowercase_ascii dom) in
      let tag_e = estring ~loc tag in
      let attr = if url then [%expr Yuka.url_attr [%e tag_e]] else [%expr Yuka.attr_unchecked] in
      let hole_attr = if url then [%expr Yuka.url_hole_attr [%e tag_e]] else [%expr Yuka.hole_attr_unchecked] in
      if hole then
        Plain
          [%expr
            [%e hole_attr] [%e dom_e]
              (fun () -> [%e option_string ~loc ~optional kind value])]
      else if optional || kind = Bool then
        Maybe
          [%expr
            Stdlib.Option.map ([%e attr] [%e dom_e])
              [%e option_string ~loc ~optional kind value]]
      else
        let ty = value_type ~loc kind in
        Plain
          [%expr
            [%e attr] [%e dom_e]
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

let hoisted : value_binding list ref = ref []
let template_count = ref 0

let literal_value (kind : Html_attributes.kind) e =
  let bool_literal () =
    match e.pexp_desc with
    | Pexp_construct ({ txt = Lident "true"; _ }, None) -> Some true
    | Pexp_construct ({ txt = Lident "false"; _ }, None) -> Some false
    | _ -> None
  in
  match (kind, e.pexp_desc) with
  | String, Pexp_constant (Pconst_string (s, _, _)) -> Some (Some s)
  | Int, Pexp_constant (Pconst_integer (s, None)) -> (
      match int_of_string_opt s with
      | Some n when n >= -0x4000_0000 && n < 0x4000_0000 -> Some (Some (string_of_int n))
      | _ -> None)
  | Bool, _ -> Option.map (fun b -> if b then Some "" else None) (bool_literal ())
  | BooleanishString, _ -> Option.map (fun b -> Some (string_of_bool b)) (bool_literal ())
  | Polyvariant options, Pexp_variant (t, None) ->
      List.find_map
        (fun (o : Html_attributes.polyvariant) ->
          if o.type_ = t then Some (Some o.jsxName) else None)
        options
  | _ -> None

let rewrite_child ~self child =
  let loc = child.pexp_loc in
  match child.pexp_desc with
  | Pexp_constant (Pconst_string _) when not (is_jsx child) ->
      [%expr Yuka.text [%e child]]
  | _ when is_jsx child -> self#expression child
  | _ ->
      let hole = reads_state child in
      let child = self#expression child in
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

let raw_text_element = function "script" | "style" -> true | _ -> false

let lower_element ~self ~loc ~fnloc tag args =
  let props, children = split_args args in
  let attrs = attributes_expr ~loc (List.map (rewrite_attribute ~self ~loc:fnloc tag) props) in
  let text c =
    match c.pexp_desc with
    | Pexp_constant (Pconst_string _) when not (is_jsx c) -> c
    | Pexp_apply ({ pexp_desc = Pexp_ident { txt = Ldot (Lident "Yuka", "text") | Lident "text"; _ }; _ }, [ (Nolabel, e) ])
      when not (is_jsx c) ->
        self#expression e
    | _ ->
        Location.raise_errorf ~loc:c.pexp_loc
          "[yuka] <%s> takes only text: a string or (Yuka.text e), not an element, a component or an island." tag
  in
  let parts = List.map text children in
  let content =
    match parts with
    | [] -> [%expr []]
    | [ p ] when not (List.exists reads_state children) -> [%expr [ Yuka.text [%e p] ]]
    | _ ->
        let joined = [%expr Stdlib.String.concat "" [%e list_expr ~loc parts]] in
        if List.exists reads_state children then [%expr [ Yuka.hole (fun () -> Yuka.text [%e joined]) ]]
        else [%expr [ Yuka.text [%e joined] ]]
  in
  [%expr Yuka.lower [%e estring ~loc tag] [%e attrs] [%e content]]

let rec template_element ~self ~parts ~loc ~fnloc tag args =
  if not (Html.is_html_element tag || Html.is_svg_element tag) then
    Location.raise_errorf ~loc:fnloc "[yuka] HTML tag '%s' does not exist." tag;
  let props, children = split_args args in
  let add_part e =
    let i = List.length !parts in
    parts := e :: !parts;
    i
  in
  let attr ((label, value) as prop) =
    let value_loc = value.pexp_loc in
    let fixed =
      match label with
      | Labelled name when not (reads_state value) -> (
          match find_prop ~loc:value.pexp_loc tag name with
          | Attribute { type_; name = dom; _ } | Rich_attribute { type_; name = dom; _ } ->
              Option.map (Option.map (fun v -> (dom, v))) (literal_value type_ value)
          | Event _ -> None)
      | _ -> None
    in
    match fixed with
    | Some (Some (dom, _)) when not (Url.valid_name dom) ->
        Location.raise_errorf ~loc:value_loc "[yuka] %S is not a valid attribute name." dom
    | Some (Some (dom, v)) when Url.unsafe ~tag:(String.lowercase_ascii tag) (String.lowercase_ascii dom) v ->
        Location.raise_errorf ~loc:value_loc
          "[yuka] %s=%S has a script URL; Yuka would print %s instead. Use an event handler." dom v Url.blocked
    | Some (Some (dom, v)) ->
        Some
          ( [%expr Yuka.Template.fixed [%e estring ~loc dom] [%e estring ~loc v]],
            Template_build.Fixed (dom, v) )
    | Some None -> None
    | None ->
        let part =
          match rewrite_attribute ~self ~loc:fnloc tag prop with
          | Plain e -> [%expr Yuka.Template.attribute [%e e]]
          | Maybe e -> [%expr Yuka.Template.attribute_option [%e e]]
        in
        let i = add_part part in
        Some ([%expr Yuka.Template.part_attr [%e eint ~loc i]], Template_build.Part_attr i)
  in
  let attrs = List.filter_map attr props in
  let child c =
    match c.pexp_desc with
    | Pexp_constant (Pconst_string (s, _, _)) when (not (is_jsx c)) && s <> "" ->
        ([%expr Yuka.Template.text [%e estring ~loc s]], Template_build.Fixed_text s)
    | Pexp_apply ({ pexp_desc = Pexp_ident { txt = Lident tag; loc = fnloc }; _ }, args)
      when is_jsx c && not (raw_text_element tag) ->
        template_element ~self ~parts ~loc:c.pexp_loc ~fnloc tag args
    | Pexp_apply ({ pexp_desc = Pexp_ident { txt = Lident tag; loc = fnloc }; _ }, args) when is_jsx c ->
        let i = add_part [%expr Yuka.Template.child [%e lower_element ~self ~loc:c.pexp_loc ~fnloc tag args]] in
        ([%expr Yuka.Template.part [%e eint ~loc i]], Template_build.Part i)
    | _ ->
        let e = rewrite_child ~self c in
        let i = add_part [%expr Yuka.Template.child [%e e]] in
        ([%expr Yuka.Template.part [%e eint ~loc i]], Template_build.Part i)
  in
  let kids = List.map child children in
  ( [%expr
      Yuka.Template.element [%e estring ~loc tag] [%e list_expr ~loc (List.map fst attrs)]
        [%e list_expr ~loc (List.map fst kids)]],
    Template_build.Fixed_element
      { tag; attrs = List.map snd attrs; children = List.map snd kids } )

let template_prefix (loc : Location.t) =
  let file = Filename.basename loc.loc_start.pos_fname in
  let file = match String.index_opt file '.' with Some i -> String.sub file 0 i | None -> file in
  let lib = match !Island.library with Some l -> l ^ "_" | None -> "" in
  String.map
    (fun c -> match c with 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' -> c | _ -> '_')
    (String.lowercase_ascii (lib ^ file ^ "_"))

let template ~self ~loc ~fnloc tag args =
  let parts = ref [] in
  let shape, built = template_element ~self ~parts ~loc ~fnloc tag args in
  let name = "__yuka_template_" ^ template_prefix loc ^ string_of_int !template_count in
  incr template_count;
  let { Template_build.walk; kids; attrs; values } = Template_build.plan built in
  let ints a = pexp_array ~loc (List.map (eint ~loc) (Array.to_list a)) in
  let values =
    pexp_array ~loc
      (List.map
         (fun (i, v) -> [%expr [%e eint ~loc i], [%e estring ~loc v]])
         (Array.to_list values))
  in
  hoisted :=
    value_binding ~loc ~pat:(pvar ~loc name)
      ~expr:
        [%expr
          Yuka.Template.make [%e shape]
            ~html:[%e estring ~loc (Template_build.html built)]
            ~walk:[%e ints walk] ~kids:[%e ints kids] ~attrs:[%e ints attrs]
            ~values:[%e values]]
    :: !hoisted;
  [%expr Yuka.Template.instance [%e evar ~loc name] [%e pexp_array ~loc (List.rev !parts)]]

let rewrite_jsx self e =
  let loc = e.pexp_loc in
  let e = strip_jsx e in
  match e.pexp_desc with
  | Pexp_apply ({ pexp_desc = Pexp_ident { txt = fn; loc = fnloc }; _ }, args) -> (
      let props, children = split_args args in
      match fn with
      | Lident tag when raw_text_element tag ->
          if not (Html.is_html_element tag) then Location.raise_errorf ~loc:fnloc "[yuka] HTML tag '%s' does not exist." tag;
          lower_element ~self ~loc ~fnloc tag args
      | Lident tag -> template ~self ~loc ~fnloc tag args
      | Ldot (Ldot (Lident "Yuka", ("Await" | "Show" as m)), "createElement") ->
          let first, takes = if m = "Await" then ("async", "async, loading and failed") else ("status", "status, loading and failed") in
          let find name =
            List.find_opt (fun (l, _) -> l = Labelled name || l = Optional name) props
          in
          List.iter
            (fun (l, _) ->
              match l with
              | Labelled ("loading" | "failed") | Optional "failed" -> ()
              | Labelled n when n = first -> ()
              | _ ->
                  Location.raise_errorf ~loc:fnloc "[yuka] Yuka.%s takes %s" m takes)
            props;
          let required name =
            match find name with
            | Some (Labelled _, v) -> v
            | _ ->
                Location.raise_errorf ~loc:fnloc "[yuka] Yuka.%s needs the prop '%s'" m name
          in
          let source = required first and loading = required "loading" in
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
                  "[yuka] Yuka.%s needs exactly one child, a function such as (fun value -> ...)" m
          in
          pexp_apply ~loc
            (pexp_ident ~loc:fnloc
               { txt = Ldot (Ldot (Lident "Yuka", m), "make"); loc = fnloc })
            ([ (Labelled first, self#expression source);
               (Labelled "loading", rewrite_child ~self loading) ]
            @ failed
            @ [ (Labelled "children", body); (Nolabel, [%expr ()]) ])
      | Ldot (Ldot (Lident "Yuka", "Catch"), "createElement") ->
          let fallback =
            match props with
            | [ (Labelled "fallback", v) ] -> self#expression v
            | _ -> Location.raise_errorf ~loc:fnloc "[yuka] Yuka.Catch takes one prop, fallback"
          in
          let kids =
            match List.map (rewrite_child ~self) children with
            | [] -> Location.raise_errorf ~loc:fnloc "[yuka] Yuka.Catch needs children"
            | [ k ] -> k
            | ks -> [%expr Yuka.fragment [%e list_expr ~loc ks]]
          in
          [%expr Yuka.Catch.make ~fallback:[%e fallback] ~children:(fun () -> [%e kids]) ()]
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

    method! structure items =
      List.concat_map
        (fun item ->
          let saved = !hoisted in
          hoisted := [];
          let item = self#structure_item item in
          let found = List.rev !hoisted in
          hoisted := saved;
          match found with
          | [] -> [ item ]
          | _ -> [ pstr_value ~loc:item.pstr_loc Nonrecursive found; item ])
        items

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
  Form_gen.register ();
  Driver.register_transformation "yuka"
    ~preprocess_impl:Island.check_placement
    ~rules:[ Context_free.Rule.extension Island.extension ]
    ~impl:(fun s -> mapper#structure (Css_ppx.attach s)) ~intf:mapper#signature
