open Ppxlib
open Ast_builder.Default

let has_attr name e =
  List.exists (fun (a : attribute) -> a.attr_name.txt = name) e.pexp_attributes

let is_jsx = has_attr "JSX"
let strip_jsx e = { e with pexp_attributes = List.filter (fun (a : attribute) -> a.attr_name.txt <> "JSX") e.pexp_attributes }

type scope = { modules : string list; opens_yuka : bool; state_alias : bool }

let empty_scope = { modules = []; opens_yuka = false; state_alias = false }
let scope = ref empty_scope
let depth = ref 0
let bound : (string * int) list ref = ref []
let in_hole = ref false
let submodules : string loc list ref = ref []
let in_expression = ref false
let in_functor = ref false
let in_anonymous = ref false

type reader = Body | Row | Prop

type lint = Off | Reads of reader | Enter of reader

let lint = ref Off

let with_lint mode f =
  let saved = !lint in
  lint := mode;
  Fun.protect ~finally:(fun () -> lint := saved) f

let hole_scope f =
  let saved = !in_hole in
  in_hole := true;
  Fun.protect ~finally:(fun () -> in_hole := saved) (fun () -> with_lint Off f)

let prop_scope f = with_lint (Reads Prop) f

let read_error ~loc = function
  | Body ->
      Location.raise_errorf ~loc
        "Yuka: this State.get runs one time and never updates. Read it in markup, a memo or an effect, or use State.peek."
  | Row ->
      Location.raise_errorf ~loc
        "Yuka: this State.get runs one time and never updates. Read it in the row markup, a memo or an effect, or use State.peek."
  | Prop ->
      Location.raise_errorf ~loc
        "Yuka: a prop reads one time; pass the State (<Label text=name />), or use State.peek."

let hidden = ""
let yuka_modules = [ "Await"; "Catch"; "Client"; "Context"; "Form"; "Show"; "Status" ]

let scoped f =
  let saved_bound = !bound and saved_scope = !scope in
  Fun.protect
    ~finally:(fun () ->
      bound := saved_bound;
      scope := saved_scope)
    f

let add_modules names = scope := { !scope with modules = names @ !scope.modules }

let hide () =
  add_modules [ hidden ];
  bound := (hidden, 0) :: !bound

let hiding f =
  scoped (fun () ->
      hide ();
      f ())

let rec root = function Lident m -> m | Ldot (l, _) | Lapply (l, _) -> root l

let open_module (m : module_expr) =
  match m.pmod_desc with
  | Pmod_ident { txt; _ } when not (List.mem (root txt) !scope.modules || List.mem hidden !scope.modules) ->
      if txt = Lident "Yuka" then
        scope := { !scope with modules = List.filter (fun n -> not (List.mem n yuka_modules)) !scope.modules };
      bound := List.map (fun (n, _) -> (n, 0)) !bound
  | _ -> hide ()

let module_names (mb : module_binding) =
  match (mb.pmb_name.txt, mb.pmb_expr.pmod_desc) with
  | Some n, Pmod_ident { txt = Ldot (Lident "Yuka", n'); _ } when n = n' -> []
  | Some n, _ -> [ n ]
  | None, _ -> []

let structure_exit = ref ([], [])

let after_item ~top (i : structure_item) =
  match i.pstr_desc with
  | Pstr_include { pincl_mod = { pmod_desc = Pmod_structure _; _ }; _ } ->
      let inner_bound, inner_modules = !structure_exit in
      bound := inner_bound;
      add_modules inner_modules
  | Pstr_open { popen_expr; _ } ->
      open_module popen_expr;
      if top then
        scope :=
          {
            !scope with
            opens_yuka = (match popen_expr.pmod_desc with Pmod_ident { txt = Lident "Yuka"; _ } -> true | _ -> false);
            state_alias = false;
          }
  | Pstr_include { pincl_mod; _ } -> open_module pincl_mod
  | Pstr_primitive { pval_name = { txt; _ }; _ } -> bound := (txt, 0) :: !bound
  | Pstr_module { pmb_name = { txt = Some "State"; _ }; pmb_expr = { pmod_desc = Pmod_ident { txt = Ldot (Lident "Yuka", "State"); _ }; _ }; _ }
    when top ->
      scope := { !scope with state_alias = true }
  | Pstr_module mb -> add_modules (module_names mb)
  | _ -> ()

let pattern_names p =
  let names = ref [] and modules = ref [] in
  let finder =
    object
      inherit Ast_traverse.iter as super

      method! pattern p =
        (match p.ppat_desc with
         | Ppat_var { txt; _ } | Ppat_alias (_, { txt; _ }) -> names := txt :: !names
         | Ppat_unpack { txt = Some m; _ } -> modules := m :: !modules
         | _ -> ());
        super#pattern p
    end
  in
  finder#pattern p;
  (!names, !modules)

let pattern_vars p = fst (pattern_names p)
let pattern_modules p = snd (pattern_names p)

let binding_vars vbs = List.concat_map (fun (vb : value_binding) -> pattern_vars vb.pvb_pat) vbs

let bind env f =
  let saved = !bound in
  bound := env @ saved;
  Fun.protect ~finally:(fun () -> bound := saved) f

let within names f = bind (List.map (fun n -> (n, 0)) names) f

let within_patterns pats f =
  scoped (fun () ->
      add_modules (List.concat_map pattern_modules pats);
      within (List.concat_map pattern_vars pats) f)

let param_patterns params =
  List.filter_map (fun (p : function_param) -> match p.pparam_desc with Pparam_val (_, _, pat) -> Some pat | Pparam_newtype _ -> None) params

let free n = not (List.mem_assoc n !bound)

let rec arity_of n = function
  | [] -> None
  | (m, a) :: rest -> if m = n then Some a else if m = hidden then Some 0 else arity_of n rest

let own_module name = List.mem name !scope.modules
let known_module name = not (own_module name || own_module hidden)

let yuka_state () = (!scope.opens_yuka || !scope.state_alias) && not (own_module "State")

let state_get = function
  | Ldot (Ldot (Lident "Yuka", "State"), "get") -> true
  | Ldot (Lident "State", "get") -> yuka_state ()
  | _ -> false

let applied_read e =
  match e.pexp_desc with
  | Pexp_apply ({ pexp_desc = Pexp_ident { txt; _ }; _ }, _) when state_get txt -> true
  | Pexp_apply
      ( { pexp_desc = Pexp_ident { txt = Lident ("|>" | "@@" as op); _ }; _ },
        [ (Nolabel, a); (Nolabel, b) ] ) -> (
      match (if op = "|>" then b else a).pexp_desc with Pexp_ident { txt; _ } -> state_get txt | _ -> false)
  | _ -> false

let alias_error ~loc subject through =
  Location.raise_errorf ~loc
    "Yuka: %s hides State.get from the ppx. The ppx optimizes and checks reads by the exact names Yuka.State.get and \
     State.get, so a read through %s is not seen, and a read that runs one time is not reported. Write Yuka.State.get \
     or State.get."
    subject through

let yuka_state_path (m : module_expr) =
  match m.pmod_desc with
  | Pmod_ident { txt = Ldot (Lident "Yuka", "State"); _ } -> Some "Yuka.State"
  | Pmod_ident { txt = Lident "State"; _ } when yuka_state () -> Some "State"
  | _ -> None

let check_open ~loc kind (o : open_declaration) =
  Option.iter (fun path -> alias_error ~loc (kind ^ path) "the open") (yuka_state_path o.popen_expr)

let special_form = function
  | Ldot (Lident (("Await" | "Show" | "Catch" | "Client") as m), "createElement")
    when !scope.opens_yuka && not (own_module m) ->
      Ldot (Ldot (Lident "Yuka", m), "createElement")
  | Ldot (Ldot (Lident "Context", "Provide"), "createElement") when !scope.opens_yuka && not (own_module "Context") ->
      Ldot (Ldot (Ldot (Lident "Yuka", "Context"), "Provide"), "createElement")
  | path -> path

let is_action_module = function
  | Ldot (Lident "Yuka", "Action") -> true
  | Lident "Action" -> !scope.opens_yuka && not (own_module "Action")
  | _ -> false

let is_action_extension name = name = "action" || name = "yuka.action"

let expand_action item =
  match item.pstr_desc with
  | Pstr_extension (({ txt; loc = name_loc }, payload), _) when is_action_extension txt ->
      let loc = item.pstr_loc in
      if !in_expression then
        Location.raise_errorf ~loc "[yuka] let%%action must be in a module, not in an expression."
      else if !in_functor then
        Location.raise_errorf ~loc
          "[yuka] let%%action cannot be in a functor: each application would register the same action name."
      else if !in_anonymous then
        Location.raise_errorf ~loc
          "[yuka] let%%action cannot be in an anonymous module: its name would be the same as an action outside it."
      else
        Action_gen.expand ~is_action_module ~submodules:(List.rev !submodules) ~library:!Island.library ~loc
          ~name_loc payload
  | _ -> [ item ]

let with_ref r v f =
  let saved = !r in
  r := v;
  Fun.protect ~finally:(fun () -> r := saved) f

let yuka_render = function
  | Ldot (Lident "Yuka", "render") -> true
  | Lident "render" -> !scope.opens_yuka && free "render"
  | _ -> false

let yuka_value name = function
  | Ldot (Lident "Yuka", n) -> n = name
  | Lident n -> n = name && !scope.opens_yuka && arity_of n !bound = None
  | _ -> false

let pure_stdlib = function
  | "^" | "+" | "-" | "*" | "/" | "mod" | "land" | "lor" | "lxor" | "lsl" | "lsr" | "asr" | "+." | "-." | "*." | "/."
  | "**" | "=" | "<>" | "==" | "!=" | "<" | ">" | "<=" | ">=" | "&&" | "||" | "min" | "max" ->
      2
  | "~-" | "~-." | "not" | "abs" | "succ" | "pred" | "string_of_int" | "string_of_float" | "string_of_bool"
  | "float_of_int" | "int_of_float" ->
      1
  | _ -> 0

let pure_module m f =
  if not (known_module m) then 0
  else
    match (m, f) with
    | ("Int" | "Float" | "Bool"), ("to_string" | "abs" | "of_int" | "to_int") -> 1
    | ("Int" | "Float" | "Bool"), ("equal" | "compare" | "max" | "min") -> 2
    | "List", "length" | "Option", ("is_some" | "is_none") -> 1
    | "List", "mem" | "Option", "value" -> 2
    | "String", ("length" | "trim" | "uppercase_ascii" | "lowercase_ascii" | "capitalize_ascii") -> 1
    | "String", ("concat" | "equal" | "make") -> 2
    | "String", "sub" -> 3
    | _ -> 0

let higher_order = function
  | Ldot (Lident m, f) | Ldot (Ldot (Lident "Stdlib", m), f) when known_module m && known_module "Stdlib" -> (
      match (m, f) with
      | ("List" | "Array"), ("map" | "filter" | "filter_map" | "concat_map" | "exists" | "for_all" | "find_opt") -> Some (0, 1)
      | ("List" | "Array"), ("mapi" | "filteri") -> Some (0, 2)
      | ("List" | "Array"), "init" -> Some (1, 1)
      | _ -> None)
  | _ -> None

let yuka_pure = function
  | "Form", "field_error_view" -> 3
  | "Form", ("value" | "field_error" | "form_errors_view") -> 2
  | "Form", "form_errors" -> 1
  | "Status", "error_to_string" -> 1
  | _ -> 0

let yuka_pure_path = function
  | Ldot (Ldot (Lident "Yuka", m), f) -> yuka_pure (m, f)
  | Ldot (Lident m, f) when !scope.opens_yuka && known_module m -> yuka_pure (m, f)
  | _ -> 0

let pure_arity = function
  | path when yuka_pure_path path > 0 -> yuka_pure_path path
  | Lident n -> ( match arity_of n !bound with Some arity -> arity | None -> pure_stdlib n)
  | Ldot (Lident "Stdlib", n) -> if known_module "Stdlib" then pure_stdlib n else 0
  | Ldot (Lident m, f) -> pure_module m f
  | Ldot (Ldot (Lident "Stdlib", m), f) -> if known_module "Stdlib" then pure_module m f else 0
  | _ -> 0

let value_default (p : function_param) =
  match p.pparam_desc with Pparam_val (_, default, _) -> Some default | Pparam_newtype _ -> None

let required (p : function_param) =
  match p.pparam_desc with Pparam_val (Optional _, _, _) | Pparam_newtype _ -> false | Pparam_val _ -> true

let rec jsx_items e =
  match e.pexp_desc with
  | Pexp_construct ({ txt = Lident "::"; _ }, Some { pexp_desc = Pexp_tuple [ x; rest ]; _ }) -> x :: jsx_items rest
  | _ -> []

let rec constant e =
  if is_jsx e then jsx_constant e
  else
    match e.pexp_desc with
    | Pexp_constant _ | Pexp_ident _ | Pexp_function _ | Pexp_construct (_, None) | Pexp_variant (_, None) -> true
    | Pexp_construct (_, Some e) | Pexp_variant (_, Some e) | Pexp_field (e, _) | Pexp_constraint (e, _) -> constant e
    | Pexp_tuple es | Pexp_array es -> List.for_all constant es
    | Pexp_record (fields, base) ->
        List.for_all (fun (_, e) -> constant e) fields && Option.fold ~none:true ~some:constant base
    | Pexp_ifthenelse (c, a, b) -> constant c && constant a && Option.fold ~none:true ~some:constant b
    | Pexp_match (e, cases) -> constant e && List.for_all constant_case cases
    | Pexp_let (Nonrecursive, vbs, body) ->
        List.for_all (fun (vb : value_binding) -> constant vb.pvb_expr) vbs
        && scoped (fun () ->
               add_modules (List.concat_map (fun (vb : value_binding) -> pattern_modules vb.pvb_pat) vbs);
               bind (binding_env vbs) (fun () -> constant body))
    | Pexp_apply ({ pexp_desc = Pexp_ident { txt; _ }; _ }, args) -> (
        match higher_order txt with
        | Some (at, arity) ->
            List.length args <= 2
            && List.for_all2
                 (fun i (l, arg) -> l = Nolabel && if i = at then pure_fun arg >= arity else constant arg)
                 (List.init (List.length args) Fun.id)
                 args
        | None ->
            (List.length args <= pure_arity txt
            || List.exists (fun name -> yuka_value name txt)
                 [ "text"; "int"; "float"; "hole"; "each"; "fragment"; "with_unique_id" ])
            && List.for_all (fun (_, arg) -> constant arg) args)
    | _ -> false

and jsx_constant e =
  match e.pexp_desc with
  | Pexp_apply ({ pexp_desc = Pexp_ident { txt = Lident _; _ }; _ }, _) -> true
  | Pexp_apply ({ pexp_desc = Pexp_ident { txt; _ }; _ }, _)
    when special_form txt = Ldot (Ldot (Lident "Yuka", "Client"), "createElement") ->
      true
  | Pexp_apply (_, args) ->
      List.for_all
        (fun (l, a) ->
          match l with
          | Nolabel -> true
          | Labelled "children" -> List.for_all (fun c -> (not (is_jsx c)) || constant c) (jsx_items a)
          | _ -> constant a)
        args
  | _ -> true

and constant_case c =
  within_patterns [ c.pc_lhs ] (fun () -> Option.fold ~none:true ~some:constant c.pc_guard && constant c.pc_rhs)

and pure_fun e =
  match e.pexp_desc with
  | Pexp_function (params, _, body) ->
      let defaults = List.filter_map value_default params in
      let values = List.length (List.filter required params) in
      if List.for_all (function Some d -> constant d | None -> true) defaults then
        within_patterns (param_patterns params) (fun () ->
            match body with
            | Pfunction_body ({ pexp_desc = Pexp_function _; _ } as inner) -> values + pure_fun inner
            | Pfunction_body b -> if constant b then values else 0
            | Pfunction_cases (cases, _, _) -> if List.for_all constant_case cases then values + 1 else 0)
      else 0
  | Pexp_constraint (e, _) -> pure_fun e
  | Pexp_ident { txt; _ } -> pure_arity txt
  | _ -> 0

and binding_env vbs =
  List.concat_map
    (fun (vb : value_binding) ->
      match vb.pvb_pat.ppat_desc with
      | Ppat_var { txt; _ } | Ppat_constraint ({ ppat_desc = Ppat_var { txt; _ }; _ }, _) -> [ (txt, pure_fun vb.pvb_expr) ]
      | _ -> List.map (fun n -> (n, 0)) (pattern_vars vb.pvb_pat))
    vbs

let call e =
  match e.pexp_desc with
  | Pexp_apply ({ pexp_desc = Pexp_ident { txt; _ }; _ }, _) when state_get txt -> None
  | Pexp_apply (({ pexp_desc = Pexp_ident _; _ } as f), [ (Nolabel, x) ]) when constant x -> Some (f, x)
  | _ -> None

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
      let hole = not (constant value) in
      let url = Url.checked ~tag:(String.lowercase_ascii tag) (String.lowercase_ascii dom) in
      let tag_e = estring ~loc tag in
      let attr = if url then [%expr Yuka.runtime_url_attr [%e tag_e]] else [%expr Yuka.runtime_attr] in
      let hole_attr = if url then [%expr Yuka.runtime_url_hole_attr [%e tag_e]] else [%expr Yuka.runtime_hole_attr] in
      match (hole, call value) with
      | true, Some (f, x) when (not url) && (not optional) && kind = String ->
          Plain [%expr Yuka.runtime_call_attr [%e dom_e] [%e self#expression f] [%e self#expression x]]
      | true, _ ->
          let value = hole_scope (fun () -> self#expression value) in
          Plain [%expr [%e hole_attr] [%e dom_e] (fun () -> [%e option_string ~loc ~optional kind value])]
      | false, _ when optional || kind = Bool ->
          Maybe
            [%expr
              Stdlib.Option.map ([%e attr] [%e dom_e])
                [%e option_string ~loc ~optional kind (self#expression value)]]
      | false, _ ->
          let ty = value_type ~loc kind in
          Plain
            [%expr
              [%e attr] [%e dom_e]
                [%e to_string ~loc kind [%expr ([%e self#expression value] : [%t ty])]]]

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
  | Bool, _ -> ( match bool_literal () with Some b -> Some (if b then Some "" else None) | None -> None)
  | BooleanishString, _ -> ( match bool_literal () with Some b -> Some (Some (string_of_bool b)) | None -> None)
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
  | _ when constant child -> self#expression child
  | _ -> (
      match child.pexp_desc with
      | Pexp_apply ({ pexp_desc = Pexp_ident { txt; _ }; _ }, [ (Nolabel, arg) ]) when yuka_value "text" txt -> (
          match call arg with
          | Some (f, x) -> [%expr Yuka.runtime_text_call [%e self#expression f] [%e self#expression x]]
          | None -> [%expr Yuka.runtime_hole (fun () -> [%e hole_scope (fun () -> self#expression child)])])
      | _ -> [%expr Yuka.runtime_hole (fun () -> [%e hole_scope (fun () -> self#expression child)])])

let children_arg ~loc kids =
  match kids with
  | [] -> []
  | [ k ] -> [ (Labelled "children", k) ]
  | ks -> [ (Labelled "children", [%expr Yuka.fragment [%e list_expr ~loc ks]]) ]

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
  let fixed = List.for_all constant children in
  let parts = List.map (fun c -> if fixed then text c else hole_scope (fun () -> text c)) children in
  let content =
    match parts with
    | [] -> [%expr []]
    | [ p ] when fixed -> [%expr [ Yuka.text [%e p] ]]
    | _ ->
        let joined = [%expr Stdlib.String.concat "" [%e list_expr ~loc parts]] in
        if fixed then [%expr [ Yuka.text [%e joined] ]]
        else [%expr [ Yuka.runtime_hole (fun () -> Yuka.text [%e joined]) ]]
  in
  [%expr Yuka.element [%e estring ~loc tag] [%e attrs] [%e content]]

type part = Child_part of expression | Attribute_part of prop

let rec template_element ~self ~parts ~fnloc tag args =
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
      | Labelled name when constant value -> (
          match find_prop ~loc:value.pexp_loc tag name with
          | Attribute { type_; name = dom; _ } | Rich_attribute { type_; name = dom; _ } -> (
              match literal_value type_ value with
              | Some (Some v) -> Some (Some (dom, v))
              | Some None -> Some None
              | None -> None)
          | Event _ -> None)
      | _ -> None
    in
    match fixed with
    | Some (Some (dom, _)) when not (Url.valid_name dom) ->
        Location.raise_errorf ~loc:value_loc "[yuka] %S is not a valid attribute name." dom
    | Some (Some (dom, v)) when Url.unsafe ~tag:(String.lowercase_ascii tag) (String.lowercase_ascii dom) v ->
        Location.raise_errorf ~loc:value_loc
          "[yuka] %s=%S has a script URL; Yuka would print %s instead. Use an event handler." dom v Url.blocked
    | Some (Some (dom, v)) -> Some (Template_build.Fixed (dom, v))
    | Some None -> None
    | None ->
        let i = add_part (Attribute_part (rewrite_attribute ~self ~loc:fnloc tag prop)) in
        Some (Template_build.Part_attr i)
  in
  let attrs = List.filter_map attr props in
  let child c =
    match c.pexp_desc with
    | Pexp_constant (Pconst_string (s, _, _)) when (not (is_jsx c)) && s <> "" ->
        Template_build.Fixed_text s
    | Pexp_apply ({ pexp_desc = Pexp_ident { txt = Lident tag; loc = fnloc }; _ }, args)
      when is_jsx c && not (raw_text_element tag) ->
        template_element ~self ~parts ~fnloc tag args
    | Pexp_apply ({ pexp_desc = Pexp_ident { txt = Lident tag; loc = fnloc }; _ }, args) when is_jsx c ->
        Template_build.Part (add_part (Child_part (lower_element ~self ~loc:c.pexp_loc ~fnloc tag args)))
    | _ -> Template_build.Part (add_part (Child_part (rewrite_child ~self c)))
  in
  let children = List.map child children in
  Template_build.Fixed_element { tag; attrs; children }

let template_prefix (loc : Location.t) =
  let file = Filename.basename loc.loc_start.pos_fname in
  let file = match String.index_opt file '.' with Some i -> String.sub file 0 i | None -> file in
  let lib = match !Island.library with Some l -> l ^ "_" | None -> "" in
  String.map
    (fun c -> match c with 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' -> c | _ -> '_')
    (String.lowercase_ascii (lib ^ file ^ "_"))

let clones built =
  let tag = match built with Template_build.Fixed_element { tag; _ } -> tag | _ -> "" in
  let html = not (Template_build.parser_changes ~svg:false built)
  and svg = not (Template_build.parser_changes ~svg:true built) in
  let primary = if Html.is_svg_element tag && not (Html.is_html_element tag) then svg else html in
  if primary then Some ((if html then 1 else 0) lor if svg then 2 else 0) else None

let renumber built (parts : part array) =
  let taken = ref [] in
  let take i =
    taken := parts.(i) :: !taken;
    List.length !taken - 1
  in
  let rec go = function
    | Template_build.Fixed_text _ as t -> t
    | Part i -> Template_build.Part (take i)
    | Fixed_element { tag; attrs; children } ->
        let attrs =
          List.map
            (function
              | Template_build.Fixed _ as a -> a
              | Part_attr i -> Template_build.Part_attr (take i))
            attrs
        in
        let children = List.map go children in
        Template_build.Fixed_element { tag; attrs; children }
  in
  let built = go built in
  (built, Array.of_list (List.rev !taken))

let emit_template ~loc built parts clones =
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
          Yuka.runtime_template [%e estring ~loc (Template_build.encode built)]
            ~html:[%e estring ~loc (Template_build.html built)]
            ~walk:[%e ints walk] ~kids:[%e ints kids] ~attrs:[%e ints attrs]
            ~values:[%e values] ~clones:[%e eint ~loc clones]]
    :: !hoisted;
  let part = function
    | Child_part e -> [%expr Yuka.runtime_child [%e e]]
    | Attribute_part (Plain e) -> [%expr Yuka.runtime_attribute [%e e]]
    | Attribute_part (Maybe e) -> [%expr Yuka.runtime_attribute_option [%e e]]
  in
  [%expr Yuka.runtime_instance [%e evar ~loc name] [%e pexp_array ~loc (List.map part (Array.to_list parts))]]

let has_literal_sink = function
  | Template_build.Fixed_element { tag; attrs; _ } ->
      List.exists
        (function
          | Template_build.Fixed (dom, _) ->
              Url.html_sink ~tag:(String.lowercase_ascii tag) (String.lowercase_ascii dom)
          | Part_attr _ -> false)
        attrs
  | Fixed_text _ | Part _ -> false

let rec lower_shape ~loc parts shape =
  match (shape, if has_literal_sink shape then clones shape else None) with
  | _, Some clones ->
      let built, parts = renumber shape parts in
      emit_template ~loc built parts clones
  | Template_build.Fixed_text s, _ -> [%expr Yuka.text [%e estring ~loc s]]
  | Part i, _ -> (
      match parts.(i) with
      | Child_part e -> e
      | Attribute_part _ -> assert false)
  | Fixed_element { tag; attrs; children }, None ->
      let attr = function
        | Template_build.Fixed (dom, v) ->
            if Url.checked ~tag:(String.lowercase_ascii tag) (String.lowercase_ascii dom) then
              Plain [%expr Yuka.runtime_url_attr [%e estring ~loc tag] [%e estring ~loc dom] [%e estring ~loc v]]
            else Plain [%expr Yuka.runtime_attr [%e estring ~loc dom] [%e estring ~loc v]]
        | Part_attr i -> (
            match parts.(i) with
            | Attribute_part p -> p
            | Child_part _ -> assert false)
      in
      [%expr
        Yuka.element [%e estring ~loc tag]
          [%e attributes_expr ~loc (List.map attr attrs)]
          [%e list_expr ~loc (List.map (lower_shape ~loc parts) children)]]

let template ~self ~loc ~fnloc tag args =
  let parts = ref [] in
  let built = template_element ~self ~parts ~fnloc tag args in
  let parts = Array.of_list (List.rev !parts) in
  match clones built with
  | Some clones -> emit_template ~loc built parts clones
  | None -> lower_shape ~loc parts built

let rewrite_jsx self e =
  let loc = e.pexp_loc in
  let e = strip_jsx e in
  match e.pexp_desc with
  | Pexp_apply ({ pexp_desc = Pexp_ident { txt = fn; loc = fnloc }; _ }, args) -> (
      let props, children = split_args args in
      match special_form fn with
      | Lident tag when raw_text_element tag ->
          if not (Html.is_html_element tag) then Location.raise_errorf ~loc:fnloc "[yuka] HTML tag '%s' does not exist." tag;
          lower_element ~self ~loc ~fnloc tag args
      | Lident tag -> template ~self ~loc ~fnloc tag args
      | Ldot (Ldot (Lident "Yuka", ("Await" | "Show" as m)), "createElement") ->
          let first, takes = if m = "Await" then ("async", "async, loading, failed and blocking") else ("status", "status, loading and failed") in
          let find name =
            List.find_opt (fun (l, _) -> l = Labelled name || l = Optional name) props
          in
          List.iter
            (fun (l, _) ->
              match l with
              | Labelled ("loading" | "failed") | Optional "failed" -> ()
              | Labelled "blocking" | Optional "blocking" when m = "Await" -> ()
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
            | Some (l, v) -> [ (l, hole_scope (fun () -> self#expression v)) ]
            | None -> []
          in
          let blocking =
            match find "blocking" with
            | Some (l, v) -> [ (l, prop_scope (fun () -> self#expression v)) ]
            | None -> []
          in
          let body =
            match children with
            | [ ({ pexp_desc = Pexp_function _; _ } as f) ] -> hole_scope (fun () -> self#expression f)
            | _ ->
                Location.raise_errorf ~loc:fnloc
                  "[yuka] Yuka.%s needs exactly one child, a function such as (fun value -> ...)" m
          in
          pexp_apply ~loc
            (pexp_ident ~loc:fnloc
               { txt = Ldot (Ldot (Lident "Yuka", m), "make"); loc = fnloc })
            ([ (Labelled first, prop_scope (fun () -> self#expression source));
               (Labelled "loading", rewrite_child ~self loading) ]
            @ failed @ blocking
            @ [ (Labelled "children", body); (Nolabel, [%expr ()]) ])
      | Ldot (Ldot (Lident "Yuka", "Catch"), "createElement") ->
          let fallback =
            match props with
            | [ (Labelled "fallback", v) ] -> hole_scope (fun () -> self#expression v)
            | _ -> Location.raise_errorf ~loc:fnloc "[yuka] Yuka.Catch takes one prop, fallback"
          in
          let kids =
            match List.map (rewrite_child ~self) children with
            | [] -> Location.raise_errorf ~loc:fnloc "[yuka] Yuka.Catch needs children"
            | [ k ] -> k
            | ks -> [%expr Yuka.fragment [%e list_expr ~loc ks]]
          in
          [%expr Yuka.Catch.make ~fallback:[%e fallback] ~children:(fun () -> [%e kids]) ()]
      | Ldot (Ldot (Ldot (Lident "Yuka", "Context"), "Provide"), "createElement") ->
          ignore
            (List.fold_left
               (fun seen (l, v) ->
                 match l with
                 | Labelled (("context" | "value") as n) ->
                     if List.mem n seen then
                       Location.raise_errorf ~loc:v.pexp_loc "[yuka] Yuka.Context.Provide takes the prop '%s' once" n;
                     n :: seen
                 | _ -> Location.raise_errorf ~loc:fnloc "[yuka] Yuka.Context.Provide takes context and value")
               [] props);
          let required name =
            match List.assoc_opt (Labelled name) props with
            | Some v -> prop_scope (fun () -> self#expression v)
            | None -> Location.raise_errorf ~loc:fnloc "[yuka] Yuka.Context.Provide needs the prop '%s'" name
          in
          let context = required "context" and value = required "value" in
          let kids =
            match List.map (rewrite_child ~self) children with
            | [] -> Location.raise_errorf ~loc:fnloc "[yuka] Yuka.Context.Provide needs children"
            | [ k ] -> k
            | ks -> [%expr Yuka.fragment [%e list_expr ~loc ks]]
          in
          [%expr Yuka.Context.provide [%e context] [%e value] (fun () -> [%e kids])]
      | Ldot (Ldot (Lident "Yuka", "Client"), "createElement") ->
          let start =
            List.map
              (fun (l, v) ->
                match l with
                | Labelled "start" | Optional "start" -> (l, prop_scope (fun () -> self#expression v))
                | _ -> Location.raise_errorf ~loc:fnloc "[yuka] Yuka.Client takes no props except start")
              props
          in
          (match children with
           | [ ({ pexp_desc = Pexp_apply ({ pexp_desc = Pexp_ident { txt = Ldot (path, "createElement"); loc = cloc }; _ }, cargs); _ } as child) ]
             when is_jsx child ->
               let cprops, ckids = split_args cargs in
               let cprops = List.map (fun (l, v) -> (l, prop_scope (fun () -> self#expression v))) cprops in
               let kids = List.map (rewrite_child ~self) ckids in
               pexp_apply ~loc
                 (pexp_ident ~loc:cloc { txt = Ldot (path, "island"); loc = cloc })
                 (start @ cprops @ children_arg ~loc kids @ [ (Nolabel, [%expr ()]) ])
           | _ ->
               Location.raise_errorf ~loc:fnloc
                 "[yuka] Yuka.Client needs exactly one child, a component tag such as <Counter a=1 />")
      | Ldot (path, "createElement") ->
          let props = List.map (fun (l, v) -> (l, prop_scope (fun () -> self#expression v))) props in
          let kids = List.map (rewrite_child ~self) children in
          let make = pexp_ident ~loc:fnloc { txt = Ldot (path, "make"); loc = fnloc } in
          let args = props @ children_arg ~loc kids in
          if !in_hole then
            [%expr Yuka.State.runtime_untrack [%e match args with [] -> make | args -> pexp_apply ~loc make args]]
          else pexp_apply ~loc make (args @ [ (Nolabel, [%expr ()]) ])
      | _ ->
          let props = List.map (fun (l, v) -> (l, prop_scope (fun () -> self#expression v))) props in
          let kids = List.map (rewrite_child ~self) children in
          pexp_apply ~loc
            (pexp_ident ~loc:fnloc { txt = fn; loc = fnloc })
            (props @ [ (Labelled "children", list_expr ~loc kids); (Nolabel, [%expr ()]) ]))
  | _ -> e

let has_jsx e =
  let found = ref false in
  let finder =
    object
      inherit Ast_traverse.iter as super

      method! expression e = if is_jsx e then found := true else super#expression e
    end
  in
  finder#expression e;
  !found

let rec result e =
  match e.pexp_desc with
  | Pexp_function (_, _, Pfunction_body b) -> result b
  | Pexp_let (_, _, e) | Pexp_letmodule (_, _, e) | Pexp_letexception (_, e) | Pexp_open (_, e)
  | Pexp_sequence (_, e) | Pexp_constraint (e, _) | Pexp_newtype (_, e) ->
      result e
  | _ -> e

let component (vb : value_binding) =
  match vb.pvb_pat.ppat_desc with
  | Ppat_var { txt = "make"; _ } | Ppat_constraint ({ ppat_desc = Ppat_var { txt = "make"; _ }; _ }, _) ->
      has_jsx (result vb.pvb_expr)
  | _ -> false

let registry_arg = function
  | Labelled "islands", { pexp_desc = Pexp_ident { txt = Lident "islands"; _ }; pexp_loc = loc; _ }
    when free "islands" ->
      (Labelled "islands", [%expr Yuka_islands.registry])
  | arg -> arg

let mapper =
  object (self)
    inherit Ast_traverse.map as super

    method! expression e =
      with_ref in_expression true @@ fun () ->
      match (!lint, e.pexp_desc) with
      | Enter reader, Pexp_function (_, _, Pfunction_body { pexp_desc = Pexp_function _; _ }) ->
          with_lint (Enter reader) (fun () -> self#rewrite e)
      | Enter reader, Pexp_function _ -> with_lint (Reads reader) (fun () -> self#rewrite e)
      | Enter _, Pexp_constraint _ -> self#rewrite e
      | Enter _, _ | Reads _, (Pexp_function _ | Pexp_lazy _) -> with_lint Off (fun () -> self#rewrite e)
      | Reads reader, _ when applied_read e -> read_error ~loc:e.pexp_loc reader
      | _ -> self#rewrite e

    method rewrite e =
      if is_jsx e then rewrite_jsx self e
      else (
        (match e.pexp_desc with
         | Pexp_open (o, _) -> check_open ~loc:e.pexp_loc "a local open of " o
         | Pexp_letmodule ({ txt = Some n; _ }, m, _) when n <> "State" ->
             Option.iter
               (fun path -> alias_error ~loc:e.pexp_loc (Printf.sprintf "let module %s = %s" n path) n)
               (yuka_state_path m)
         | _ -> ());
        match e.pexp_desc with
        | Pexp_extension ({ txt; loc }, _) when is_action_extension txt ->
            Location.raise_errorf ~loc "[yuka] let%%action must be in a module, not in an expression."
        | Pexp_apply
            (({ pexp_desc = Pexp_ident { txt = render; _ }; _ } as f), args)
          when yuka_render render ->
            let args =
              List.map
                (fun arg ->
                  let l, a = registry_arg arg in
                  (l, self#expression a))
                args
            in
            { e with pexp_desc = Pexp_apply (f, args) }
        | Pexp_apply ({ pexp_desc = Pexp_ident { txt; _ }; _ }, _) when yuka_value "hole" txt -> hole_scope (fun () -> super#expression e)
        | Pexp_apply (({ pexp_desc = Pexp_ident { txt; _ }; _ } as f), args) when yuka_value "each" txt ->
            let row =
              Option.fold ~none:(-1) ~some:(fun j -> List.length args - 1 - j)
                (List.find_index (fun (l, _) -> l = Nolabel) (List.rev args))
            in
            let args =
              List.mapi
                (fun i (l, a) -> (l, if i = row then with_lint (Enter Row) (fun () -> self#expression a) else self#expression a))
                args
            in
            { e with pexp_desc = Pexp_apply (self#expression f, args) }
        | Pexp_apply (({ pexp_desc = Pexp_ident { txt; _ }; _ } as f), [ (Nolabel, render) ])
          when yuka_value "with_unique_id" txt && pure_fun render < 1 ->
            let loc = render.pexp_loc in
            let render =
              match render.pexp_desc with
              | Pexp_function ([ ({ pparam_desc = Pparam_val (Nolabel, None, _); _ } as id) ], c, Pfunction_body body) ->
                  { render with pexp_desc = Pexp_function ([ id ], c, Pfunction_body [%expr Yuka.runtime_hole (fun () -> [%e body])]) }
              | _ -> [%expr fun __yuka_id -> Yuka.runtime_hole (fun () -> [%e render] __yuka_id)]
            in
            { e with pexp_desc = Pexp_apply (f, [ (Nolabel, hole_scope (fun () -> self#expression render)) ]) }
        | Pexp_let (rf, vbs, body) ->
            let names = binding_vars vbs in
            let env = if rf = Recursive then List.map (fun n -> (n, 0)) names else binding_env vbs in
            let vbs = within (if rf = Recursive then names else []) (fun () -> List.map self#value_binding vbs) in
            let body =
              scoped (fun () ->
                  add_modules (List.concat_map (fun (vb : value_binding) -> pattern_modules vb.pvb_pat) vbs);
                  bind env (fun () -> self#expression body))
            in
            { e with pexp_desc = Pexp_let (rf, vbs, body) }
        | Pexp_function (params, _, _) -> within_patterns (param_patterns params) (fun () -> super#expression e)
        | Pexp_open (od, body) ->
            let od = self#open_declaration od in
            let body =
              scoped (fun () ->
                  open_module od.popen_expr;
                  self#expression body)
            in
            { e with pexp_desc = Pexp_open (od, body) }
        | Pexp_letmodule (name, m, body) ->
            let m = self#module_expr m in
            let body =
              scoped (fun () ->
                  add_modules (Option.to_list name.txt);
                  self#expression body)
            in
            { e with pexp_desc = Pexp_letmodule (name, m, body) }
        | Pexp_letop { let_; ands; body } ->
            let let_ = self#binding_op let_ and ands = List.map self#binding_op ands in
            let body =
              within_patterns (List.map (fun (b : binding_op) -> b.pbop_pat) (let_ :: ands)) (fun () -> self#expression body)
            in
            { e with pexp_desc = Pexp_letop { let_; ands; body } }
        | _ -> super#expression e)

    method! case c = within_patterns [ c.pc_lhs ] (fun () -> super#case c)

    method! module_expr m =
      match m.pmod_desc with
      | Pmod_functor (Named ({ txt = Some n; _ }, _), _) ->
          with_ref in_functor true (fun () ->
              scoped (fun () ->
                  add_modules [ n ];
                  super#module_expr m))
      | Pmod_functor _ -> with_ref in_functor true (fun () -> super#module_expr m)
      | _ -> super#module_expr m

    method! class_expr c = hiding (fun () -> super#class_expr c)
    method! class_structure c = hiding (fun () -> super#class_structure c)

    method! structure_item i =
      (match i.pstr_desc with
       | Pstr_open o -> check_open ~loc:i.pstr_loc "open " o
       | Pstr_include { pincl_mod; _ } ->
           Option.iter (fun path -> alias_error ~loc:i.pstr_loc ("include " ^ path) "the include") (yuka_state_path pincl_mod)
       | Pstr_module { pmb_name = { txt = Some n; _ }; pmb_expr; _ } when n <> "State" ->
           Option.iter
             (fun path -> alias_error ~loc:i.pstr_loc (Printf.sprintf "module %s = %s" n path) n)
             (yuka_state_path pmb_expr)
       | _ -> ());
      super#structure_item i

    method! module_binding mb =
      match mb.pmb_name with
      | { txt = Some name; loc } -> with_ref submodules ({ txt = name; loc } :: !submodules) (fun () -> super#module_binding mb)
      | { txt = None; _ } -> with_ref in_anonymous true (fun () -> super#module_binding mb)

    method! structure items =
      let top = !depth = 0 in
      let saved_bound = !bound and saved_scope = !scope in
      incr depth;
      Fun.protect
        ~finally:(fun () ->
          decr depth;
          structure_exit := (!bound, !scope.modules);
          bound := saved_bound;
          scope := saved_scope)
        (fun () ->
          List.concat_map
            (fun item ->
              List.concat_map
                (fun item ->
                  (match item.pstr_desc with
                   | Pstr_value (Recursive, vbs) -> bound := List.map (fun n -> (n, 0)) (binding_vars vbs) @ !bound
                   | Pstr_recmodule mbs -> add_modules (List.concat_map module_names mbs)
                   | _ -> ());
                  let saved = !hoisted in
                  hoisted := [];
                  let mapped =
                    with_lint Off (fun () ->
                        match item.pstr_desc with
                        | Pstr_value (rf, vbs) when List.exists component vbs ->
                            let vb b = with_lint (if component b then Enter Body else Off) (fun () -> self#value_binding b) in
                            { item with pstr_desc = Pstr_value (rf, List.map vb vbs) }
                        | _ -> self#structure_item item)
                  in
                  let found = List.rev !hoisted in
                  hoisted := saved;
                  (match item.pstr_desc with
                   | Pstr_value (Nonrecursive, vbs) -> bound := binding_env vbs @ !bound
                   | _ -> ());
                  after_item ~top item;
                  match found with
                  | [] -> [ mapped ]
                  | _ ->
                      let loc = mapped.pstr_loc in
                      [ pstr_open ~loc
                          (open_infos ~loc ~override:Fresh ~expr:(pmod_structure ~loc [ pstr_value ~loc Nonrecursive found ]));
                        mapped ])
                (expand_action item))
            items)
  end

let () =
  Codec_gen.register ();
  Form_gen.register ();
  Driver.register_transformation "yuka"
    ~preprocess_impl:Island.check_placement
    ~impl:(fun s ->
      scope := empty_scope;
      depth := 0;
      bound := [];
      in_hole := false;
      lint := Off;
      mapper#structure (Css_ppx.attach s))
