open Ppxlib

exception Fail of Location.t * string

let fail loc fmt = Printf.ksprintf (fun s -> raise (Fail (loc, s))) fmt
let sprintf = Printf.sprintf

type ty = Int | String | Bool | Custom of { ty : string; param : string }
type seg = Static of string | Param of string * ty | Rest of string
type search_kind = Optional | Default of string | Many
type field = { fname : string; fty : ty; fkind : search_kind }

type kind =
  | Named of { name : string; meth : string; search : field list }
  | Redirect of { permanent : bool; target : string }

type level = {
  props : (string * expression) list;
  scope : seg list;
  layout : int option;
  lloc : Location.t;
}

type node = {
  kind : kind;
  segs : seg list;
  path : string;
  loc : Location.t;
  tag : string;
  levels : level list;
}

type ctx = {
  prefix : seg list;
  text : string;
  search : field list;
  labels : string list;
  levels : level list;
}

let rules = [ "headers"; "cache"; "prerender" ]
let reserved = [ "with_query"; "with_fragment"; "href"; "fragment"; "req"; "children" ]
let generated_values = [ "href"; "find"; "with_query"; "with_fragment" ]

let encode text =
  let b = Buffer.create (String.length text) in
  String.iter
    (function
      | ('A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '-' | '.' | '_' | '~') as c ->
          Buffer.add_char b c
      | c -> Buffer.add_string b (sprintf "%%%02X" (Char.code c)))
    text;
  Buffer.contents b

let is_ident_char = function
  | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '\'' -> true
  | _ -> false

(* OCaml 5.3 made effect a keyword; ppxlib's Keyword list does not hold it. *)
let is_keyword s = Keyword.is_keyword s || s = "effect"

let is_label s =
  s <> "" && s <> "_"
  && (match s.[0] with 'a' .. 'z' | '_' -> true | _ -> false)
  && String.for_all is_ident_char s
  && not (is_keyword s)

let is_module_path s =
  List.for_all
    (fun c ->
      c <> ""
      && (match c.[0] with 'A' .. 'Z' -> true | _ -> false)
      && String.for_all is_ident_char c)
    (String.split_on_char '.' s)

let custom loc ~what ~fix ~types ty =
  match List.rev (String.split_on_char '.' ty) with
  | last :: (_ :: _ as m) when is_module_path (String.concat "." (List.rev m)) && is_label last ->
      let value = if last = "t" then "param" else last ^ "_param" in
      Custom { ty; param = String.concat "." (List.rev (value :: m)) }
  | _ when is_module_path ty ->
      fail loc "%s names the module %s; write its type: %s" what ty (fix (ty ^ ".t"))
  | _ ->
      fail loc "%s has type %S; the types are %s and a type with its module path, such as \
         Model.issue_id"
        what ty types

let line (loc : Location.t) = loc.loc_start.pos_lnum
let has_rest = List.exists (function Rest _ -> true | _ -> false)

let seg_labels =
  List.filter_map (function Static _ -> None | Param (n, _) | Rest n -> Some n)

let segment loc path part =
  if part = "" then fail loc "path %S has an empty segment or a trailing slash" path
  else if part = "." || part = ".." then fail loc "path %S has a %S segment" path part
  else if part.[0] = ':' then
    match String.index_opt part '<' with
    | Some i when part.[String.length part - 1] = '>' -> (
        let name = String.sub part 1 (i - 1) in
        let ty = String.sub part (i + 1) (String.length part - i - 2) in
        if not (is_label name) then
          fail loc "param %S in path %S is not a lowercase OCaml label" name path;
        match ty with
        | "int" -> Param (name, Int)
        | "string" -> Param (name, String)
        | "string..." -> Rest name
        | _ ->
            Param
              ( name,
                custom loc
                  ~what:(sprintf "param :%s in path %S" name path)
                  ~fix:(sprintf ":%s<%s>" name) ~types:"int, string, string..." ty ))
    | _ -> fail loc "param %S in path %S must be written :name<type>" part path
  else if String.exists (fun c -> c = '%' || c = '?' || c = '#') part then
    fail loc "segment %S in path %S holds %% ? or #; write segments decoded" part
      path
  else Static part

let parse_path loc path =
  if path = "/" then []
  else if path = "" || path.[0] <> '/' then fail loc "path %S must start with /" path
  else
    let parts = String.split_on_char '/' (String.sub path 1 (String.length path - 1)) in
    let segs = List.map (segment loc path) parts in
    let n = List.length segs in
    List.iteri
      (fun i s ->
        match s with
        | Rest name when i < n - 1 ->
            fail loc "catch-all :%s in path %S must be the last segment" name path
        | _ -> ())
      segs;
    segs

let join parent child =
  if child = "/" then parent else if parent = "/" then child else parent ^ child

let rec list_items e =
  match e.pexp_desc with
  | Pexp_construct ({ txt = Lident "[]"; _ }, None) -> []
  | Pexp_construct ({ txt = Lident "::"; _ }, Some { pexp_desc = Pexp_tuple [ hd; tl ]; _ })
    ->
      hd :: list_items tl
  | _ ->
      fail e.pexp_loc
        "the child nodes must be a list such as [ Router.route A ~path:\"/a\" ~page:Pages.a ]"

let element e =
  match e.pexp_desc with
  | Pexp_apply ({ pexp_desc = Pexp_ident { txt = Ldot (Lident "Router", tag); _ }; _ }, args) ->
      let props =
        List.filter_map
          (fun (label, v) ->
            match label with
            | Nolabel -> None
            | Labelled l -> Some (l, v)
            | Optional l -> fail v.pexp_loc "?%s: optional arguments are not supported" l)
          args
      in
      let rec no_dups = function
        | [] -> ()
        | (l, _) :: rest ->
            (match List.assoc_opt l rest with
            | Some v -> fail v.pexp_loc "argument ~%s is given twice" l
            | None -> ());
            no_dups rest
      in
      no_dups props;
      let unlabelled = List.filter_map (fun (l, v) -> if l = Nolabel then Some v else None) args in
      (tag, unlabelled, props, e.pexp_loc)
  | _ ->
      fail e.pexp_loc
        "expected a route node such as Router.route Home ~path:\"/\" ~page:Pages.home"

let unlabelled tag loc what = function
  | [ v ] -> v
  | _ -> fail loc "Router.%s takes %s as its one unlabelled argument" tag what

let attachments = [ "page"; "layout"; "handler"; "guard"; "not_found"; "error" ]

let check_props tag loc props ~required ~optional =
  List.iter
    (fun (l, v) ->
      if not (List.mem l required || List.mem l optional) then
        fail v.pexp_loc "Router.%s has no argument ~%s; its labelled arguments are %s" tag l
          (String.concat ", " (List.map (( ^ ) "~") (required @ optional)));
      match v.pexp_desc with
      | Pexp_ident _ -> ()
      | _ when List.mem l attachments ->
          fail v.pexp_loc "~%s must be a value path such as Pages.home" l
      | _ -> ())
    props;
  List.iter
    (fun r ->
      if not (List.mem_assoc r props) then fail loc "Router.%s needs the argument ~%s" tag r)
    required

let string_lit name v =
  match v.pexp_desc with
  | Pexp_constant (Pconst_string (s, _, _)) -> s
  | _ -> fail v.pexp_loc "%s must be a string literal" name

let parse_ty fname kind e =
  match e.pexp_desc with
  | Pexp_ident { txt = Lident "int"; _ } -> Int
  | Pexp_ident { txt = Lident "string"; _ } -> String
  | Pexp_ident { txt = Lident "bool"; _ } -> Bool
  | _ ->
      let ty =
        match e.pexp_desc with
        | Pexp_ident { txt; _ } | Pexp_construct ({ txt; _ }, None) ->
            String.concat "." (Longident.flatten_exn txt)
        | _ -> Pprintast.string_of_expression e
      in
      custom e.pexp_loc
        ~what:(sprintf "search field %s" fname)
        ~fix:(sprintf "%s %s" kind) ~types:"int, string, bool" ty

let check_default ~items d =
  (object
     inherit Ast_traverse.iter as super

     method! expression e =
       (match e.pexp_desc with
       | Pexp_ident { txt = Lident n; loc } when List.mem n items ->
           fail loc
             "%s is defined before the tree; the shared module holds this default and does not \
              see the items before the tree, so write the value with its module path"
             n
       | _ -> ());
       super#expression e
  end)
    #expression d

let parse_search ~items v =
  match v.pexp_desc with
  | Pexp_record (fields, None) ->
      List.map
        (fun ({ txt; loc }, e) ->
          let fname =
            match txt with
            | Lident n when is_label n -> n
            | _ -> fail loc "a search field is a lowercase OCaml label"
          in
          let bad () =
            fail e.pexp_loc "search field %s must be optional T, default T value or many T"
              fname
          in
          match e.pexp_desc with
          | Pexp_apply ({ pexp_desc = Pexp_ident { txt = Lident kind; _ }; _ }, args)
            when List.for_all (fun (l, _) -> l = Nolabel) args -> (
              match (kind, List.map snd args) with
              | "optional", [ t ] -> { fname; fty = parse_ty fname kind t; fkind = Optional }
              | "many", [ t ] -> { fname; fty = parse_ty fname kind t; fkind = Many }
              | "default", [ t; d ] ->
                  check_default ~items d;
                  {
                    fname;
                    fty = parse_ty fname kind t;
                    fkind = Default (Pprintast.string_of_expression d);
                  }
              | _ -> bad ())
          | _ -> bad ())
        fields
  | _ -> fail v.pexp_loc "~search must be a record such as { tag = optional string }"

let loader_label v =
  match v.pexp_desc with
  | Pexp_ident { txt; _ } -> Longident.last_exn txt
  | _ ->
      fail v.pexp_loc
        "~loader must be a value path such as Loaders.issue; its last name labels \
         the result"

let add_labels loc labels names =
  List.fold_left
    (fun labels l ->
      if List.mem l reserved then fail loc "label %s is reserved by the generated code" l;
      if List.mem l labels then
        fail loc
          "label %s is used twice in this branch (params, search fields and loader \
           results share one set of labels)"
          l;
      l :: labels)
    labels names

let parse_name names v =
  match v.pexp_desc with
  | Pexp_construct ({ txt = Lident (("Some" | "None" | "true" | "false" | "()" | "[]" | "::") as n); _ }, None) ->
      fail v.pexp_loc "name %s is a predefined constructor that the generated code uses; choose another name" n
  | Pexp_construct ({ txt = Lident n; _ }, None) ->
      (match Hashtbl.find_opt names n with
      | Some first -> fail v.pexp_loc "name %s is used twice (first at line %d)" n (line first)
      | None -> Hashtbl.add names n v.pexp_loc);
      let helper = String.uncapitalize_ascii n in
      if is_keyword helper then
        fail v.pexp_loc "name %s makes the helper Routes.%s, which is an OCaml keyword; choose another name" n helper;
      if List.mem helper generated_values then
        fail v.pexp_loc "name %s makes the helper Routes.%s, which the generated code already defines; choose another name" n helper;
      n
  | _ -> fail v.pexp_loc "the route name must be a constructor such as Issue"

let parse_method tag v =
  match v.pexp_desc with
  | Pexp_variant ((("GET" | "POST" | "PUT" | "PATCH" | "DELETE") as m), None) ->
      if tag = "action" && m = "GET" then
        fail v.pexp_loc "Router.action cannot use `GET; use `POST, `PUT, `PATCH or `DELETE";
      m
  | _ -> fail v.pexp_loc "~method_ must be one of `GET, `POST, `PUT, `PATCH, `DELETE"

let parse_redirect segs v =
  let permanent, tv =
    match v.pexp_desc with
    | Pexp_construct ({ txt = Lident "Permanent"; _ }, Some t) -> (true, t)
    | Pexp_construct ({ txt = Lident "Temporary"; _ }, Some t) -> (false, t)
    | _ -> fail v.pexp_loc "~to_ must be (Permanent \"/path\") or (Temporary \"/path\")"
  in
  let target = string_lit "a redirect target" tv in
  List.iter
    (fun p ->
      if String.length p > 1 && p.[0] = ':' then
        let name = String.sub p 1 (String.length p - 1) in
        if not (List.mem name (seg_labels segs)) then
          fail tv.pexp_loc "redirect target %S names :%s, which is not a param of the path"
            target name)
    (String.split_on_char '/' target);
  Redirect { permanent; target }

let check_prerender props =
  match List.assoc_opt "prerender" props with
  | Some { pexp_desc = Pexp_construct ({ txt = Lident ("true" | "false"); _ }, None); _ }
  | None ->
      ()
  | Some v -> fail v.pexp_loc "~prerender must be true or false"

let check_cross_origin props =
  match List.assoc_opt "cross_origin" props with
  | Some { pexp_desc = Pexp_construct ({ txt = Lident ("true" | "false"); _ }, None); _ } | None -> ()
  | Some v -> fail v.pexp_loc "~cross_origin must be true or false"

let cross_origin level =
  match List.assoc_opt "cross_origin" level.props with
  | Some { pexp_desc = Pexp_construct ({ txt = Lident "true"; _ }, None); _ } -> true
  | _ -> false

let takes_loader levels =
  List.exists (fun l -> List.mem_assoc "loader" l.props) levels

let check_fallback levels =
  let here = List.nth levels (List.length levels - 1) in
  match List.find_opt (fun (l, _) -> l = "not_found" || l = "error") here.props with
  | None -> ()
  | Some (prop, v) ->
      let rec scan above = function
        | [] -> ()
        | l :: rest ->
            let above = above @ [ l ] in
            if Option.is_some l.layout && takes_loader above then
              fail v.pexp_loc
                "%s here renders inside the layout at line %d, which takes a loader \
                 result; declare %s on a node above the loader"
                prop (line l.lloc) prop
            else scan above rest
      in
      scan [] levels

let read ~server ~items names e =
  let nodes = ref [] in
  let layouts = ref 0 in
  let level props scope loc =
    let layout =
      if List.mem_assoc "layout" props then begin
        let i = !layouts in
        incr layouts;
        Some i
      end
      else None
    in
    { props; scope; layout; lloc = loc }
  in
  let add n = nodes := n :: !nodes in
  let rec walk ctx e =
    let tag, args, props, loc = element e in
    let prop l = List.assoc_opt l props in
    check_prerender props;
    let name () =
      parse_name names (unlabelled tag loc "the route name (such as Issue)" args)
    in
    let own_path () =
      let v = List.assoc "path" props in
      let text = string_lit "path" v in
      (text, v.pexp_loc, parse_path v.pexp_loc text)
    in
    let with_loader labels =
      match prop "loader" with
      | Some v -> add_labels v.pexp_loc labels [ loader_label v ]
      | None -> labels
    in
    let with_search labels =
      match prop "search" with
      | Some v ->
          let fields = parse_search ~items v in
          (fields, add_labels v.pexp_loc labels (List.map (fun f -> f.fname) fields))
      | None -> ([], labels)
    in
    match tag with
    | "group" ->
        check_props tag loc props ~required:[ "path" ]
          ~optional:([ "layout"; "loader"; "guard"; "not_found"; "error"; "search" ] @ rules);
        let children = list_items (unlabelled tag loc "a list of child nodes" args) in
        let text, ploc, segs = own_path () in
        if has_rest segs then fail ploc "a Router.group path cannot hold a catch-all";
        let labels = add_labels ploc ctx.labels (seg_labels segs) |> with_loader in
        let search, labels = with_search labels in
        let levels = ctx.levels @ [ level props (ctx.prefix @ segs) loc ] in
        if server then check_fallback levels;
        let ctx =
          {
            prefix = ctx.prefix @ segs;
            text = join ctx.text text;
            search = ctx.search @ search;
            labels;
            levels;
          }
        in
        List.iter (walk ctx) children
    | "redirect" ->
        (match args with
        | [] -> ()
        | v :: _ -> fail v.pexp_loc "Router.redirect takes no unlabelled argument");
        check_props tag loc props ~required:[ "path"; "to_" ] ~optional:[];
        let text, ploc, segs = own_path () in
        ignore (add_labels ploc ctx.labels (seg_labels segs));
        let segs = ctx.prefix @ segs in
        add
          {
            kind = parse_redirect segs (List.assoc "to_" props);
            segs;
            path = join ctx.text text;
            loc;
            tag;
            levels = ctx.levels;
          }
    | "route" ->
        check_props tag loc props ~required:[ "path"; "page" ]
          ~optional:([ "loader"; "guard"; "search" ] @ rules);
        let name = name () in
        let text, ploc, segs = own_path () in
        let labels = add_labels ploc ctx.labels (seg_labels segs) |> with_loader in
        let search, _ = with_search labels in
        add
          {
            kind = Named { name; meth = "GET"; search = ctx.search @ search };
            segs = ctx.prefix @ segs;
            path = join ctx.text text;
            loc;
            tag;
            levels = ctx.levels @ [ level props (ctx.prefix @ segs) loc ];
          }
    | "endpoint" | "action" ->
        check_props tag loc props ~required:[ "path"; "method_"; "handler" ]
          ~optional:((if tag = "endpoint" then [ "guard"; "cross_origin" ] else [ "guard" ]) @ rules);
        check_cross_origin props;
        let name = name () in
        let meth = parse_method tag (List.assoc "method_" props) in
        let text, ploc, segs = own_path () in
        ignore (add_labels ploc ctx.labels (seg_labels segs));
        add
          {
            kind = Named { name; meth; search = [] };
            segs = ctx.prefix @ segs;
            path = join ctx.text text;
            loc;
            tag;
            levels = ctx.levels @ [ level props (ctx.prefix @ segs) loc ];
          }
    | "make" -> fail loc "Router.make can only be the root"
    | _ ->
        fail loc
          "unknown node Router.%s; the nodes are Router.make, Router.group, Router.route, \
           Router.endpoint, Router.action and Router.redirect (names of the route file syntax, not OCaml values)"
          tag
  in
  let tag, args, props, loc = element e in
  if tag <> "make" then fail loc "the root must be Router.make";
  check_props tag loc props ~required:[]
    ~optional:([ "layout"; "not_found"; "error"; "guard" ] @ rules);
  let children = list_items (unlabelled tag loc "a list of child nodes" args) in
  check_prerender props;
  let root = [ level props [] loc ] in
  if server then check_fallback root;
  List.iter (walk { prefix = []; text = "/"; search = []; labels = []; levels = root }) children;
  (List.rev !nodes, List.hd root)

type shape = S of string | P | R

let shape = List.map (function Static s -> S s | Param _ -> P | Rest _ -> R)
let rank = function S _ -> 0 | P -> 1 | R -> 2

let rec specificity a b =
  match (a, b) with
  | [], [] -> 0
  | [], _ -> -1
  | _, [] -> 1
  | x :: a, y :: b ->
      let c = compare (rank x) (rank y) in
      if c <> 0 then c else specificity a b

let groups nodes =
  let groups =
    List.fold_left
      (fun groups n ->
        let k = shape n.segs in
        match List.assoc_opt k groups with
        | Some g ->
            List.iter
              (fun m ->
                let clash =
                  match (m.kind, n.kind) with
                  | Redirect _, _ | _, Redirect _ -> Some "every method (a redirect)"
                  | Named a, Named b when a.meth = b.meth -> Some ("`" ^ a.meth)
                  | _ -> None
                in
                match clash with
                | Some what ->
                    fail n.loc "path %S has the same shape as %S (line %d); both answer %s"
                      n.path m.path (line m.loc) what
                | None -> ())
              !g;
            g := !g @ [ n ];
            groups
        | None -> groups @ [ (k, ref [ n ]) ])
      [] nodes
  in
  List.stable_sort (fun (a, _) (b, _) -> specificity a b) groups
  |> List.map (fun (_, g) -> !g)

let ty_text = function
  | Int -> "int"
  | String -> "string"
  | Bool -> "bool"
  | Custom { ty; _ } -> ty

let fields segs search =
  List.filter_map
    (function
      | Static _ -> None
      | Param (n, ty) -> Some (n, ty_text ty)
      | Rest n -> Some (n, "string list"))
    segs
  @ List.map
      (fun f ->
        ( f.fname,
          match f.fkind with
          | Optional -> ty_text f.fty ^ " option"
          | Default _ -> ty_text f.fty
          | Many -> ty_text f.fty ^ " list" ))
      search

let named nodes =
  List.filter_map
    (fun n ->
      match n.kind with
      | Named { name; search; _ } -> Some (name, n.segs, search)
      | Redirect _ -> None)
    nodes

let indent n = List.map (fun l -> if l = "" then l else String.make n ' ' ^ l)

let close lines =
  match List.rev lines with [] -> [] | last :: rest -> List.rev ((last ^ ")") :: rest)

let arm head = function
  | [ one ] -> [ sprintf "| %s -> %s" head one ]
  | body -> sprintf "| %s -> (" head :: indent 4 (close body)

let type_t nodes =
  "type t =" :: List.map
    (fun (name, segs, search) ->
      match fields segs search with
      | [] -> "  | " ^ name
      | fs ->
          sprintf "  | %s of { %s }" name
            (String.concat "; " (List.map (fun (f, t) -> f ^ " : " ^ t) fs)))
    (named nodes)

type piece = Lit of string | Code of string

let rec merge = function
  | Lit a :: Lit b :: rest -> merge (Lit (a ^ b) :: rest)
  | p :: rest -> p :: merge rest
  | [] -> []

let concat pieces =
  let text = function Lit s -> sprintf "%S" s | Code c -> c in
  let rec go = function
    | [] -> "\"\""
    | [ p ] -> text p
    | p :: rest ->
        let arg = function Lit _ as l -> text l | Code c -> "(" ^ c ^ ")" in
        let tail = match rest with [ Lit _ as l ] -> text l | _ -> "(" ^ go rest ^ ")" in
        sprintf "Stdlib.( ^ ) %s %s" (arg p) tail
  in
  go (merge pieces)

let custom_encode p v = sprintf "Yuka.Router.Param.encode %s %s" p v
let custom_decode p = sprintf "Yuka.Router.Param.decode %s" p

let to_url ty v =
  match ty with
  | Int -> "Stdlib.string_of_int " ^ v
  | Bool -> "Stdlib.string_of_bool " ^ v
  | String -> "Yuka.Router.encode " ^ v
  | Custom { param = m; _ } -> sprintf "Yuka.Router.encode (%s)" (custom_encode m v)

let path_pieces segs =
  match segs with
  | [] -> [ Lit "/" ]
  | _ ->
      List.concat_map
        (function
          | Static s -> [ Lit ("/" ^ encode s) ]
          | Param (n, Int) -> [ Lit "/"; Code ("Stdlib.string_of_int " ^ n) ]
          | Param (n, String) -> [ Lit "/"; Code ("Yuka.Router.segment " ^ n) ]
          | Param (n, Custom { param = m; _ }) ->
              [ Lit "/"; Code (sprintf "Yuka.Router.segment (%s)" (custom_encode m n)) ]
          | Param (_, Bool) -> assert false
          | Rest n -> [ Code ("Yuka.Router.segments " ^ n) ])
        segs

let search_pairs f =
  let pair v = sprintf "[ (%S, %s) ]" (encode f.fname) (to_url f.fty v) in
  match f.fkind with
  | Optional -> sprintf "(match %s with Some v -> %s | None -> [])" f.fname (pair "v")
  | Default d ->
      let eq =
        match f.fty with
        | Custom { param = m; _ } ->
            sprintf "Stdlib.( = ) (%s) (%s)" (custom_encode m f.fname) (custom_encode m ("(" ^ d ^ ")"))
        | _ -> sprintf "Stdlib.( = ) %s (%s)" f.fname d
      in
      sprintf "(if %s then [] else %s)" eq (pair f.fname)
  | Many ->
      sprintf "Stdlib.List.map (fun v -> (%S, %s)) %s" (encode f.fname) (to_url f.fty "v")
        f.fname

let href nodes =
  let uses_search = List.exists (fun (_, _, s) -> s <> []) (named nodes) in
  let helper =
    if uses_search then
      [
        "let with_query path pairs =";
        "  match pairs with";
        "  | [] -> path";
        "  | _ ->";
        "      Stdlib.String.concat \"\"";
        "        [";
        "          path;";
        "          \"?\";";
        "          Stdlib.String.concat \"&\"";
        "            (Stdlib.List.map (fun (k, v) -> Stdlib.String.concat \"=\" [ k; v ]) pairs);";
        "        ]";
        "";
      ]
    else []
  in
  helper
  @ "let href = function"
    :: List.concat_map
         (fun (name, segs, search) ->
           let head =
             match fields segs search with
             | [] -> name
             | fs -> sprintf "%s { %s }" name (String.concat "; " (List.map fst fs))
           in
           let pieces = path_pieces segs in
           let path = concat pieces in
           match search with
           | [] -> indent 2 (arm head [ path ])
           | fields ->
               let path =
                 match merge pieces with [ Lit _ ] -> path | _ -> "(" ^ path ^ ")"
               in
               let pairs =
                 match fields with
                 | [ f ] -> [ "(" ^ search_pairs f ^ ")" ]
                 | _ ->
                     ("(Stdlib.List.concat" :: "   [" :: List.map (fun f -> "     " ^ search_pairs f ^ ";") fields)
                     @ [ "   ])" ]
               in
               indent 2
                 ((sprintf "| %s ->" head :: indent 4 [ "with_query " ^ path ])
                 @ indent 6 pairs))
         (named nodes)

let helpers nodes =
  [
    "";
    "let with_fragment path fragment =";
    "  Stdlib.( ^ ) path";
    "    (match fragment with None -> \"\" | Some fragment -> Stdlib.( ^ ) \"#\" (Yuka.Router.encode fragment))";
  ]
  @ List.concat_map
    (fun (name, segs, search) ->
      let required = List.map (fun n -> "~" ^ n) (seg_labels segs) in
      let optional =
        List.map
          (fun f ->
            match f.fkind with
            | Optional -> "?" ^ f.fname
            | Default d -> sprintf "?(%s = %s)" f.fname d
            | Many -> sprintf "?(%s = [])" f.fname)
          search
        @ [ "?fragment" ]
      in
      let value =
        match fields segs search with
        | [] -> name
        | fs -> sprintf "(%s { %s })" name (String.concat "; " (List.map fst fs))
      in
      [
        "";
        sprintf "let %s %s() = with_fragment (href %s) fragment" (String.uncapitalize_ascii name)
          (String.concat "" (List.map (fun a -> a ^ " ") (required @ optional)))
          value;
      ])
    (named nodes)

let decode_search f =
  let values = sprintf "Yuka.Router.search query %S" f.fname in
  let dec v =
    match f.fty with
    | String -> "Some " ^ v
    | Int -> "Yuka.Router.int_param " ^ v
    | Bool -> sprintf "(match %s with \"true\" -> Some true | \"false\" -> Some false | _ -> None)" v
    | Custom { param = m; _ } -> sprintf "%s %s" (custom_decode m) v
  in
  match (f.fkind, f.fty) with
  | Optional, _ -> sprintf "(match %s with v :: _ -> %s | [] -> None)" values (dec "v")
  | Default d, String -> sprintf "(match %s with v :: _ -> v | [] -> (%s))" values d
  | Default d, _ ->
      sprintf "(match %s with v :: _ -> (match %s with Some v -> v | None -> (%s)) | [] -> (%s))"
        values (dec "v") d d
  | Many, String -> values
  | Many, _ -> sprintf "Stdlib.List.filter_map (fun v -> %s) (%s)" (dec "v") values

let rec decode_params params k =
  match params with
  | [] -> k
  | (i, ty) :: rest -> (
      let fn = match ty with Int -> Some "Yuka.Router.int_param" | Custom { param = m; _ } -> Some (custom_decode m) | _ -> None in
      match fn with
      | None -> decode_params rest k
      | Some fn ->
          (sprintf "match %s p%d with" fn i
          :: "| None -> Yuka.Router.Missing"
          :: arm (sprintf "Some p%d" i) (decode_params rest k)))

let params segs =
  List.concat
    (List.mapi
       (fun i s -> match s with Param (_, ty) -> [ (i, ty) ] | _ -> [])
       segs)

let var segs name =
  let rec go i = function
    | (Param (n, _) | Rest n) :: _ when n = name -> sprintf "p%d" i
    | _ :: rest -> go (i + 1) rest
    | [] -> assert false
  in
  go 0 segs

let found name segs search =
  let values =
    List.concat
      (List.mapi
         (fun i s ->
           match s with
           | Param (n, _) | Rest n -> [ sprintf "%s = p%d" n i ]
           | Static _ -> [])
         segs)
    @ List.map (fun f -> sprintf "%s = %s" f.fname (decode_search f)) search
  in
  match (values, search) with
  | [], _ -> [ "Yuka.Router.Found " ^ name ]
  | _, [] -> [ sprintf "Yuka.Router.Found (%s { %s })" name (String.concat "; " values) ]
  | _ ->
      sprintf "Yuka.Router.Found (%s {" name
      :: List.map (fun v -> "  " ^ v ^ ";") values
      @ [ "})" ]

let redirect segs permanent target =
  let param p =
    let name = String.sub p 1 (String.length p - 1) in
    let v = var segs name in
    match List.find (function Param (n, _) | Rest n -> n = name | Static _ -> false) segs with
    | Param (_, ty) -> Code (to_url ty v)
    | Rest _ ->
        Code (sprintf "Stdlib.String.concat \"/\" (Stdlib.List.map Yuka.Router.encode %s)" v)
    | Static _ -> assert false
  in
  let pieces =
    String.split_on_char '/' target
    |> List.map (fun p -> if String.length p > 1 && p.[0] = ':' then param p else Lit p)
    |> List.fold_left (fun acc p -> match acc with [] -> [ p ] | _ -> acc @ [ Lit "/"; p ]) []
  in
  [ sprintf "Yuka.Router.Redirect { permanent = %b; location = %s }" permanent (concat pieces) ]

let pattern segs =
  let items =
    List.mapi
      (fun i s ->
        match s with
        | Static t -> sprintf "%S" t
        | Param _ -> sprintf "p%d" i
        | Rest _ -> sprintf "(_ :: _ as p%d)" i)
      segs
  in
  match segs with
  | [] -> "[]"
  | _ when has_rest segs -> String.concat " :: " items
  | _ -> "[ " ^ String.concat "; " items ^ " ]"

let find nodes =
  let groups = groups nodes in
  let uses_query =
    List.exists (fun n -> match n.kind with Named { search; _ } -> search <> [] | _ -> false) nodes
  in
  let arms =
    List.concat_map
      (fun group ->
        let first = List.hd group in
        let body =
          match group with
          | [ { kind = Redirect { permanent; target }; segs; _ } ] ->
              decode_params (params segs) (redirect segs permanent target)
          | _ ->
              let methods =
                List.filter_map
                  (fun n -> match n.kind with Named { meth; _ } -> Some meth | _ -> None)
                  group
              in
              let by_method =
                List.concat_map
                  (fun n ->
                    match n.kind with
                    | Named { name; meth; search } ->
                        let head = if meth = "GET" then "`GET | `HEAD" else "`" ^ meth in
                        arm head (decode_params (params n.segs) (found name n.segs search))
                    | Redirect _ -> [])
                  group
              in
              ("match meth with" :: by_method)
              @ [
                  sprintf "| _ -> Yuka.Router.Wrong_method [ %s ]"
                    (String.concat "; " (List.map (fun m -> "`" ^ m) methods));
                ]
        in
        arm (pattern first.segs) body)
      groups
  in
  "let find (meth : Yuka.Router.meth) (path : string list)"
  :: sprintf "    (%s : (string * string) list) : t Yuka.Router.lookup ="
       (if uses_query then "query" else "_query")
  :: "  match path with"
  :: indent 2
       (arms
       @
       let has segs = List.exists (fun g -> match g with n :: _ -> n.segs = segs | [] -> false) groups in
       let root_rest =
         List.exists (fun g -> match g with { segs = [ Rest _ ]; _ } :: _ -> true | _ -> false) groups
       in
       if has [] && root_rest then [] else [ "| _ -> Yuka.Router.Missing" ])

let generate input nodes =
  if named nodes = [] then fail (Location.in_file input) "the route tree has no named node";
  String.concat "\n" (type_t nodes @ [ "" ] @ href nodes @ helpers nodes @ [ "" ] @ find nodes) ^ "\n"

let expr e = Pprintast.string_of_expression e
let paren e = "(" ^ expr e ^ ")"
let prop l level = List.assoc_opt l level.props
let args labels = String.concat "" (List.map (fun l -> " ~" ^ l) labels)

let key_text level =
  let base = sprintf "%S" ("L" ^ string_of_int (Option.get level.layout)) in
  let params =
    List.filter_map
      (function
        | Param (n, Int) -> Some ("Stdlib.string_of_int " ^ n)
        | Param (n, (String | Bool)) -> Some ("Yuka.Router.encode " ^ n)
        | Param (n, Custom { param = m; _ }) -> Some (sprintf "Yuka.Router.encode (%s)" (custom_encode m n))
        | Rest _ | Static _ -> None)
      level.scope
  in
  match params with
  | [] -> base
  | _ -> sprintf "Stdlib.String.concat \"/\" [ %s ]" (String.concat "; " (base :: params))

let loader_labels levels =
  List.filter_map (fun l -> Option.map loader_label (prop "loader" l)) levels

let layer_text ~loaders level =
  sprintf "{ Yuka.Server.Generated.key = %s; data = %b; wrap = (fun children -> %s%s ~children ()) }"
    (key_text level) (loaders <> [])
    (expr (Option.get (prop "layout" level)))
    (args (seg_labels level.scope @ loaders))

let layer_name level = sprintf "layer_%d" (Option.get level.layout)

let loader_free_layers levels =
  let rec go above = function
    | [] -> []
    | l :: rest ->
        let above = above @ [ l ] in
        (if l.layout <> None && loader_labels above = [] then [ l ] else []) @ go above rest
  in
  go [] levels

let static_key level = not (List.exists (function Param _ -> true | _ -> false) level.scope)

let layer_binding level = layer_text ~loaders:[] level

let layers_lines levels =
  let rec go above = function
    | [] -> []
    | l :: rest ->
        let above = above @ [ l ] in
        (match (l.layout, loader_labels above) with
        | Some _, [] -> [ layer_name l ^ ";" ]
        | Some _, loaders -> [ layer_text ~loaders l ^ ";" ]
        | None, _ -> [])
        @ go above rest
  in
  match go [] levels with [] -> [ "[];" ] | items -> ("[" :: indent 2 items) @ [ "];" ]

let prerendered levels =
  List.fold_left
    (fun acc l ->
      match prop "prerender" l with
      | Some { pexp_desc = Pexp_construct ({ txt = Lident b; _ }, None); _ } -> b = "true"
      | _ -> acc)
    false levels

let seed n =
  match n.kind with
  | Named { meth = "GET"; _ } when prerendered n.levels ->
      let rec statics acc = function
        | [] -> Some (List.rev acc)
        | Static s :: rest -> statics (encode s :: acc) rest
        | (Param _ | Rest _) :: _ -> None
      in
      Option.map (fun parts -> "/" ^ String.concat "/" parts) (statics [] n.segs)
  | _ -> None

let rules_text levels =
  let headers = List.filter_map (fun l -> Option.map expr (prop "headers" l)) levels in
  let last name =
    List.fold_left (fun acc l -> match prop name l with Some v -> Some v | None -> acc) None levels
  in
  sprintf "Yuka.Server.Generated.rules ~headers:[ %s ]%s ~prerender:%s ()"
    (String.concat "; " headers)
    (match last "cache" with Some c -> sprintf " ~cache:(Yuka.Server.%s [@warning \"-33\"])" (paren c) | None -> "")
    (match last "prerender" with Some p -> expr p | None -> "false")

let fallback_levels levels =
  let declares l = List.mem_assoc "not_found" l.props || List.mem_assoc "error" l.props in
  let depth =
    snd (List.fold_left (fun (i, best) l -> (i + 1, if declares l then i else best)) (0, 0) levels)
  in
  List.filteri (fun i _ -> i <= depth) levels

let nearest_fallback name levels =
  List.fold_left
    (fun acc l -> match prop name l with Some v -> Some (v, l) | None -> acc)
    None (fallback_levels levels)

let fallback_uses_params levels =
  List.exists (fun l -> l.layout <> None && seg_labels l.scope <> []) (fallback_levels levels)
  || List.exists
       (fun name ->
         match nearest_fallback name levels with
         | Some (_, l) -> seg_labels l.scope <> []
         | None -> false)
       [ "not_found"; "error" ]

let fallback_text levels =
  let upto = fallback_levels levels in
  let call name label default =
    match (nearest_fallback name levels, label) with
    | Some (f, l), Some label ->
        if List.mem label (seg_labels l.scope) then
          fail f.pexp_loc "%s takes ~%s, so no param of its path can be named %s" name label label;
        sprintf "(fun %s -> %s%s ~%s ())" label (expr f) (args (seg_labels l.scope)) label
    | Some (f, l), None -> sprintf "(fun () -> %s%s ())" (expr f) (args (seg_labels l.scope))
    | None, _ -> default
  in
  String.concat "\n"
    (("{" :: "  Yuka.Server.Generated.layers =" :: indent 4 (layers_lines upto))
    @ [
        sprintf "  not_found = %s;" (call "not_found" (Some "path") "Yuka.Server.Generated.default_not_found");
        sprintf "  error = %s;" (call "error" None "Yuka.Server.Generated.default_error");
        "}";
      ])

let scope_args level = args (seg_labels level.scope)

let guards_text levels =
  let gs =
    List.filter_map
      (fun l ->
        Option.map
          (fun g -> sprintf "(fun () -> %s req%s)" (expr g) (scope_args l))
          (prop "guard" l))
      levels
  in
  match gs with [] -> "[]" | _ -> "[ " ^ String.concat "; " gs ^ " ]"

let uses_req nodes =
  List.exists
    (fun n ->
      match n.kind with
      | Redirect _ -> false
      | Named _ ->
          n.tag <> "route"
          || List.exists
               (fun l -> List.mem_assoc "loader" l.props || List.mem_assoc "guard" l.props)
               n.levels)
    nodes

let interned prefix =
  let table = ref [] in
  let name text =
    match List.assoc_opt text !table with
    | Some n -> n
    | None ->
        let n = sprintf "%s_%d" prefix (List.length !table) in
        table := !table @ [ (text, n) ];
        n
  in
  (name, fun () -> List.map (fun (t, n) -> (n, t)) !table)

let server_arm ~shared ~rule ~fallback n =
  match n.kind with
  | Redirect _ -> []
  | Named { name; search; _ } ->
      let labels = List.map fst (fields n.segs search) in
      let head =
        match labels with
        | [] -> sprintf "%s.%s" shared name
        | _ -> sprintf "%s.%s { %s }" shared name (String.concat "; " labels)
      in
      let leaf = List.nth n.levels (List.length n.levels - 1) in
      let rules = rule (rules_text n.levels) in
      let guards = guards_text n.levels in
      let body =
        if n.tag = "route" then
          let parents = List.filter (fun l -> l != leaf) n.levels in
          let fb =
            if fallback_uses_params parents then
              String.concat "\n          " (String.split_on_char '\n' (fallback_text parents))
            else fallback (fallback_text parents)
          in
          let loaders =
            List.filter_map
              (fun l ->
                Option.map
                  (fun v -> (loader_label v, sprintf "%s req%s" (expr v) (scope_args l)))
                  (prop "loader" l))
              n.levels
          in
          let page =
            sprintf "%s%s ()" (expr (Option.get (prop "page" leaf)))
              (args (labels @ List.map fst loaders))
          in
          let plan =
            [ "Yuka.Async.return"; "  (Stdlib.Ok"; "     {"; "       Yuka.Server.Generated.layers =" ]
            @ indent 9 (layers_lines n.levels)
            @ [
                sprintf "       page = %s;" page;
                sprintf "     })%s);" (String.make (List.length loaders) ')');
              ]
          in
          List.map
            (fun l -> sprintf "let %s = %s in" (layer_name l) (layer_binding l))
            (List.filter (fun l -> not (static_key l)) (loader_free_layers n.levels))
          @ [
            "Yuka.Server.Generated.Page";
            "  {";
            sprintf "    rules = %s;" rules;
            sprintf "    guards = %s;" guards;
            sprintf "    fallback = %s;" fb;
            "    load =";
            "      (fun () ->";
          ]
          @ List.map (fun (l, call) -> sprintf "        let %s = %s in" l call) loaders
          @ List.map (fun (l, _) -> sprintf "        Yuka.Server.Generated.loaded %s (fun %s ->" l l) loaders
          @ indent 8 plan
          @ [ "  }" ]
        else
          [
            "Yuka.Server.Generated.Handler";
            "  {";
            sprintf "    rules = %s;" rules;
            sprintf "    action = %b;" (n.tag = "action");
            sprintf "    cross_origin = %b;" (cross_origin leaf);
            sprintf "    guards = %s;" guards;
            sprintf "    run = (fun () -> %s req%s);"
              (expr (Option.get (prop "handler" leaf)))
              (args (seg_labels n.segs));
            "  }";
          ]
      in
      sprintf "| %s ->" head :: indent 4 body

let generated_name name =
  List.mem name [ "req"; "children"; "path" ]
  || List.exists
       (fun prefix ->
         let n = String.length prefix in
         String.length name > n
         && String.sub name 0 n = prefix
         && String.for_all (function '0' .. '9' -> true | _ -> false) (String.sub name n (String.length name - n)))
       [ "rules_"; "layer_"; "fallback_" ]

let check_hidden nodes =
  List.iter
    (fun n ->
      let route, labels =
        match n.kind with
        | Named { name; search; _ } ->
            (name, List.map fst (fields n.segs search) @ loader_labels n.levels)
        | Redirect _ -> ("", [])
      in
      List.iter
        (fun level ->
          List.iter
            (fun (prop, v) ->
              match v.pexp_desc with
              | Pexp_ident { txt = Lident name; _ } when List.mem prop ("loader" :: attachments) ->
                  if generated_name name then
                    fail v.pexp_loc
                      "~%s:%s is hidden by a name of the generated server code (req, children, path, \
                       rules_N, layer_N, fallback_N); write it with its module path"
                      prop name
                  else if prop <> "loader" && List.mem name labels then
                    fail v.pexp_loc
                      "~%s:%s is hidden by the param, search field or loader result %s of the route \
                       %s; write it with its module path"
                      prop name name route
              | _ -> ())
            level.props)
        n.levels)
    nodes

let generate_server ~shared ~digest (nodes, root) =
  check_hidden nodes;
  let rule, rules = interned "rules" in
  let fallback, fallbacks = interned "fallback" in
  let static_layers =
    List.sort_uniq
      (fun a b -> compare a.layout b.layout)
      (List.filter static_key
         (loader_free_layers [ root ]
         @ List.concat_map
             (fun n ->
               match n.kind with
               | Named _ when n.tag = "route" -> loader_free_layers n.levels
               | _ -> [])
             nodes))
  in
  let missing = fallback (fallback_text [ root ]) in
  let arms = List.concat_map (server_arm ~shared ~rule ~fallback) nodes in
  let req = if uses_req nodes then "req" else "_req" in
  String.concat "\n"
    (List.map (fun (n, t) -> sprintf "let %s =\n  %s\n" n t) (rules ())
    @ List.map
        (fun l -> sprintf "let %s : Yuka.Server.Generated.layer =\n  %s\n" (layer_name l) (layer_binding l))
        static_layers
    @ List.map
        (fun (n, t) ->
          sprintf "let %s : Yuka.Server.Generated.fallback =\n%s\n" n
            (String.concat "\n" (indent 2 (String.split_on_char '\n' t))))
        (fallbacks ())
    @ [ sprintf "let resolve %s (route : %s.t) : Yuka.Server.Generated.target =" req shared;
        "  match route with" ]
    @ indent 2 arms
    @ [
        "";
        sprintf "let app =";
        sprintf "  Yuka.Server.Generated.app ~build:%S" digest;
        sprintf "    ~headers:%s"
          (match prop "headers" root with Some h -> paren h | None -> "[]");
        sprintf "    ~prerender:[ %s ]"
          (String.concat "; " (List.map (sprintf "%S") (List.filter_map seed nodes)));
        sprintf "    ~find:%s.find ~resolve ~missing:%s" shared missing;
      ])
  ^ "\n"

let router_make e =
  match e.pexp_desc with
  | Pexp_ident { txt = Ldot (Lident "Router", "make"); _ } -> true
  | _ -> false

let mentions_router_make si =
  (object
     inherit [bool] Ast_traverse.fold as super

     method! expression e found = found || router_make e || super#expression e found
  end)
    #structure_item si false

let manifest source text structure =
  let tree = "the route tree, Router.make ... or let routes = Router.make ..." in
  let e, before =
    match List.rev structure with
    | [] -> fail (Location.in_file source) "the route file is empty; it must end with %s" tree
    | { pstr_desc = Pstr_eval (e, _); _ } :: before -> (e, before)
    | {
        pstr_desc =
          Pstr_value
            ( Nonrecursive,
              [
                {
                  pvb_pat = { ppat_desc = Ppat_var { txt = "routes"; _ }; ppat_attributes = []; _ };
                  pvb_expr = e;
                  pvb_constraint = None;
                  pvb_attributes = [];
                  _;
                };
              ] );
        _;
      }
      :: before
      when match e.pexp_desc with Pexp_function _ -> false | _ -> true ->
        (e, before)
    | ({ pstr_desc = Pstr_value (_, vbs); _ } as si) :: _ -> (
        let swallowed =
          List.find_map
            (fun vb ->
              match vb.pvb_expr.pexp_desc with
              | Pexp_apply (_, args) ->
                  List.find_map (fun (l, a) -> if l = Nolabel && router_make a then Some a.pexp_loc else None) args
              | _ -> None)
            vbs
        in
        match swallowed with
        | Some loc ->
            fail loc "Router.make is read as an argument of the let before it; write let routes = Router.make ..."
        | None when mentions_router_make si ->
            fail si.pstr_loc
              "write the tree as let routes = Router.make ...: one binding named routes, with no rec, \
               no parameter, no type and no attribute"
        | None ->
            fail si.pstr_loc "the route file must end with %s; open, let, module and type items go before it"
              tree)
    | si :: _ ->
        fail si.pstr_loc "the route file must end with %s; open, let, module and type items go before it" tree
  in
  let items = List.rev before in
  List.iter
    (fun si ->
      match si.pstr_desc with
      | Pstr_eval _ ->
          fail si.pstr_loc "the route file holds one route tree, as its last item; this is another expression"
      | _ -> ())
    items;
  let text = match before with [] -> "" | si :: _ -> String.sub text 0 si.pstr_loc.loc_end.pos_cnum in
  (text, items, e)

let item_values items =
  List.concat_map
    (fun si ->
      match si.pstr_desc with
      | Pstr_value (_, vbs) ->
          List.concat_map
            (fun vb ->
              (object
                 inherit [string list] Ast_traverse.fold as super

                 method! pattern p acc =
                   match p.ppat_desc with
                   | Ppat_var { txt; _ } | Ppat_alias (_, { txt; _ }) -> super#pattern p (txt :: acc)
                   | _ -> super#pattern p acc
              end)
                #pattern vb.pvb_pat [])
            vbs
      | _ -> [])
    items

let report (loc : Location.t) msg =
  let s = loc.loc_start and e = loc.loc_end in
  if s.pos_lnum <= 0 then Printf.eprintf "File %S, line 1:\n" s.pos_fname
  else if s.pos_lnum = e.pos_lnum then
      Printf.eprintf "File %S, line %d, characters %d-%d:\n" s.pos_fname s.pos_lnum
        (s.pos_cnum - s.pos_bol) (e.pos_cnum - s.pos_bol)
    else
      Printf.eprintf "File %S, lines %d-%d, characters %d-%d:\n" s.pos_fname s.pos_lnum
        e.pos_lnum (s.pos_cnum - s.pos_bol) (e.pos_cnum - e.pos_bol);
  Printf.eprintf "Error: %s\n" msg

let run ~server source output =
  match In_channel.with_open_bin source In_channel.input_all with
  | exception Sys_error m ->
      prerr_endline ("yuka routes: " ^ m);
      exit 1
  | text -> (
      let lexbuf = Lexing.from_string text in
      Location.init lexbuf source;
      try
        let text_before, items, e = manifest source text (Parse.implementation lexbuf) in
        print_string
          (output text_before e (read ~server ~items:(item_values items) (Hashtbl.create 16) e))
      with
      | Fail (loc, msg) ->
          report loc msg;
          exit 1
      | exn when Option.is_some (Location.Error.of_exn exn) ->
          Location.report_exception Format.err_formatter exn;
          exit 1)

let shared source = run ~server:false source (fun _ _ (nodes, _) -> generate source nodes)

let server ~shared_module source =
  run ~server:true source (fun before e tree ->
      let server =
        generate_server ~shared:shared_module
          ~digest:(Digest.to_hex (Digest.string (before ^ Pprintast.string_of_expression e)))
          tree
      in
      if before = "" then server else before ^ "\n\n" ^ server)
