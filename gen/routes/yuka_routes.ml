open Ppxlib

exception Fail of Location.t * string

let fail loc fmt = Printf.ksprintf (fun s -> raise (Fail (loc, s))) fmt
let sprintf = Printf.sprintf

type ty = Int | String | Bool | Custom of string
type seg = Static of string | Param of string * ty | Rest of string
type search_kind = Optional | Default of string | Many
type field = { fname : string; fty : ty; fkind : search_kind }

type kind =
  | Named of { name : string; meth : string; search : field list }
  | Redirect of { permanent : bool; target : string }

type node = { kind : kind; segs : seg list; path : string; loc : Location.t }

type ctx = {
  prefix : seg list;
  text : string;
  search : field list;
  labels : string list;
}

let rules = [ "headers"; "cache"; "prerender" ]
let reserved = [ "with_query" ]

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

let is_label s =
  s <> "" && s <> "_"
  && (match s.[0] with 'a' .. 'z' | '_' -> true | _ -> false)
  && String.for_all is_ident_char s
  && not (Keyword.is_keyword s)

let is_module_path s =
  List.for_all
    (fun c ->
      c <> ""
      && (match c.[0] with 'A' .. 'Z' -> true | _ -> false)
      && String.for_all is_ident_char c)
    (String.split_on_char '.' s)

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
        | _ when is_module_path ty -> Param (name, Custom ty)
        | _ ->
            fail loc
              "param :%s in path %S has type %S; the types are int, string, \
               string... and a module path"
              name path ty)
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

let is_jsx e = List.exists (fun a -> a.attr_name.txt = "JSX") e.pexp_attributes

let rec list_items e =
  match e.pexp_desc with
  | Pexp_construct ({ txt = Lident "[]"; _ }, None) -> []
  | Pexp_construct ({ txt = Lident "::"; _ }, Some { pexp_desc = Pexp_tuple [ hd; tl ]; _ })
    ->
      hd :: list_items tl
  | _ -> fail e.pexp_loc "children must be route nodes"

let element e =
  match e.pexp_desc with
  | Pexp_apply
      ({ pexp_desc = Pexp_ident { txt = Ldot (Lident tag, "createElement"); _ }; _ }, args)
    when is_jsx e ->
      let props =
        List.filter_map
          (fun (label, v) ->
            match label with
            | Nolabel -> None
            | Labelled l -> Some (l, v)
            | Optional l -> fail v.pexp_loc "?%s: optional props are not supported" l)
          args
      in
      let rec no_dups = function
        | [] -> ()
        | (l, _) :: rest ->
            (match List.assoc_opt l rest with
            | Some v -> fail v.pexp_loc "prop %s is given twice" l
            | None -> ());
            no_dups rest
      in
      no_dups props;
      let children, props = List.partition (fun (l, _) -> l = "children") props in
      let children = match children with [ (_, c) ] -> list_items c | _ -> [] in
      (tag, props, children, e.pexp_loc)
  | _ -> fail e.pexp_loc "expected a route node such as <Route ... />"

let check_props tag loc props ~required ~optional =
  List.iter
    (fun (l, v) ->
      if not (List.mem l required || List.mem l optional) then
        fail v.pexp_loc "<%s> has no prop %s; its props are %s" tag l
          (String.concat ", " (required @ optional)))
    props;
  List.iter
    (fun r -> if not (List.mem_assoc r props) then fail loc "<%s> needs the prop %s" tag r)
    required

let string_lit name v =
  match v.pexp_desc with
  | Pexp_constant (Pconst_string (s, _, _)) -> s
  | _ -> fail v.pexp_loc "%s must be a string literal" name

let parse_ty e =
  match e.pexp_desc with
  | Pexp_ident { txt = Lident "int"; _ } -> Int
  | Pexp_ident { txt = Lident "string"; _ } -> String
  | Pexp_ident { txt = Lident "bool"; _ } -> Bool
  | Pexp_construct ({ txt; _ }, None) -> Custom (String.concat "." (Longident.flatten_exn txt))
  | _ -> fail e.pexp_loc "a search type is int, string, bool or a module path"

let parse_search v =
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
              | "optional", [ t ] -> { fname; fty = parse_ty t; fkind = Optional }
              | "many", [ t ] -> { fname; fty = parse_ty t; fkind = Many }
              | "default", [ t; d ] ->
                  {
                    fname;
                    fty = parse_ty t;
                    fkind = Default (Pprintast.string_of_expression d);
                  }
              | _ -> bad ())
          | _ -> bad ())
        fields
  | _ -> fail v.pexp_loc "search must be a record such as { tag = optional string }"

let loader_label v =
  match v.pexp_desc with
  | Pexp_ident { txt; _ } -> Longident.last_exn txt
  | _ ->
      fail v.pexp_loc
        "loader must be a value name such as Loaders.issue; its last name labels \
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
  | Pexp_construct ({ txt = Lident n; _ }, None) ->
      (match Hashtbl.find_opt names n with
      | Some first -> fail v.pexp_loc "name %s is used twice (first at line %d)" n (line first)
      | None -> Hashtbl.add names n v.pexp_loc);
      n
  | _ -> fail v.pexp_loc "name must be a constructor such as Issue"

let parse_method tag v =
  match v.pexp_desc with
  | Pexp_variant ((("GET" | "POST" | "PUT" | "PATCH" | "DELETE") as m), None) ->
      if tag = "Action" && m = "GET" then
        fail v.pexp_loc "an Action cannot use `GET; use `POST, `PUT, `PATCH or `DELETE";
      m
  | _ -> fail v.pexp_loc "method_ must be one of `GET, `POST, `PUT, `PATCH, `DELETE"

let parse_redirect segs v =
  let permanent, tv =
    match v.pexp_desc with
    | Pexp_construct ({ txt = Lident "Permanent"; _ }, Some t) -> (true, t)
    | Pexp_construct ({ txt = Lident "Temporary"; _ }, Some t) -> (false, t)
    | _ -> fail v.pexp_loc "redirect must be (Permanent \"/path\") or (Temporary \"/path\")"
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
  | Some v -> fail v.pexp_loc "prerender must be true or false"

let read names e =
  let nodes = ref [] in
  let add n = nodes := n :: !nodes in
  let rec walk ctx e =
    let tag, props, children, loc = element e in
    let prop l = List.assoc_opt l props in
    check_prerender props;
    let leaf () = if children <> [] then fail loc "<%s> takes no children" tag in
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
          let fields = parse_search v in
          (fields, add_labels v.pexp_loc labels (List.map (fun f -> f.fname) fields))
      | None -> ([], labels)
    in
    match tag with
    | "Group" ->
        check_props tag loc props ~required:[ "path" ]
          ~optional:([ "layout"; "loader"; "guard"; "not_found"; "error"; "search" ] @ rules);
        let text, ploc, segs = own_path () in
        if has_rest segs then fail ploc "a Group path cannot hold a catch-all";
        let labels = add_labels ploc ctx.labels (seg_labels segs) |> with_loader in
        let search, labels = with_search labels in
        let ctx =
          {
            prefix = ctx.prefix @ segs;
            text = join ctx.text text;
            search = ctx.search @ search;
            labels;
          }
        in
        List.iter (walk ctx) children
    | "Route" when List.mem_assoc "redirect" props ->
        leaf ();
        check_props tag loc props ~required:[ "path"; "redirect" ] ~optional:[];
        let text, ploc, segs = own_path () in
        ignore (add_labels ploc ctx.labels (seg_labels segs));
        let segs = ctx.prefix @ segs in
        add
          {
            kind = parse_redirect segs (List.assoc "redirect" props);
            segs;
            path = join ctx.text text;
            loc;
          }
    | "Route" ->
        leaf ();
        check_props tag loc props ~required:[ "name"; "path"; "page" ]
          ~optional:([ "loader"; "guard"; "search" ] @ rules);
        let name = parse_name names (List.assoc "name" props) in
        let text, ploc, segs = own_path () in
        let labels = add_labels ploc ctx.labels (seg_labels segs) |> with_loader in
        let search, _ = with_search labels in
        add
          {
            kind = Named { name; meth = "GET"; search = ctx.search @ search };
            segs = ctx.prefix @ segs;
            path = join ctx.text text;
            loc;
          }
    | "Endpoint" | "Action" ->
        leaf ();
        check_props tag loc props
          ~required:[ "name"; "path"; "method_"; "handler" ]
          ~optional:("guard" :: rules);
        let name = parse_name names (List.assoc "name" props) in
        let meth = parse_method tag (List.assoc "method_" props) in
        let text, ploc, segs = own_path () in
        ignore (add_labels ploc ctx.labels (seg_labels segs));
        add
          {
            kind = Named { name; meth; search = [] };
            segs = ctx.prefix @ segs;
            path = join ctx.text text;
            loc;
          }
    | "Router" -> fail loc "<Router> can only be the root"
    | _ ->
        fail loc "unknown node <%s>; the nodes are Router, Group, Route, Endpoint and Action"
          tag
  in
  let tag, props, children, loc = element e in
  if tag <> "Router" then fail loc "the root must be <Router>";
  check_props tag loc props ~required:[]
    ~optional:([ "layout"; "not_found"; "error"; "guard" ] @ rules);
  check_prerender props;
  List.iter (walk { prefix = []; text = "/"; search = []; labels = [] }) children;
  List.rev !nodes

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
  | Custom m -> m ^ ".t"

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
  String.concat " ^ "
    (List.map (function Lit s -> sprintf "%S" s | Code c -> c) (merge pieces))

let to_url ty v =
  match ty with
  | Int -> "Stdlib.string_of_int " ^ v
  | Bool -> "Stdlib.string_of_bool " ^ v
  | String -> "Yuka.Router.encode " ^ v
  | Custom m -> sprintf "Yuka.Router.encode (%s.to_string %s)" m v

let path_pieces segs =
  match segs with
  | [] -> [ Lit "/" ]
  | _ ->
      List.concat_map
        (function
          | Static s -> [ Lit ("/" ^ encode s) ]
          | Param (n, ty) -> [ Lit "/"; Code (to_url ty n) ]
          | Rest n ->
              [
                Code
                  (sprintf
                     "String.concat \"\" (List.map (fun s -> \"/\" ^ \
                      Yuka.Router.encode s) %s)"
                     n);
              ])
        segs

let search_pairs f =
  let pair v = sprintf "[ (%S, %s) ]" (encode f.fname) (to_url f.fty v) in
  match f.fkind with
  | Optional -> sprintf "(match %s with Some v -> %s | None -> [])" f.fname (pair "v")
  | Default d ->
      let eq =
        match f.fty with
        | Custom m -> sprintf "%s.to_string %s = %s.to_string (%s)" m f.fname m d
        | _ -> sprintf "%s = (%s)" f.fname d
      in
      sprintf "(if %s then [] else %s)" eq (pair f.fname)
  | Many ->
      sprintf "List.map (fun v -> (%S, %s)) %s" (encode f.fname) (to_url f.fty "v") f.fname

let href nodes =
  let uses_search = List.exists (fun (_, _, s) -> s <> []) (named nodes) in
  let helper =
    if uses_search then
      [
        "let with_query path pairs =";
        "  match pairs with";
        "  | [] -> path";
        "  | _ ->";
        "      path ^ \"?\"";
        "      ^ String.concat \"&\" (List.map (fun (k, v) -> k ^ \"=\" ^ v) pairs)";
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
           | first :: rest ->
               let path =
                 match merge pieces with [ Lit _ ] -> path | _ -> "(" ^ path ^ ")"
               in
               indent 2
                 ((sprintf "| %s ->" head :: indent 4 [ "with_query " ^ path ])
                 @ indent 6
                     (close
                        (("(" ^ search_pairs first)
                        :: List.map (fun f -> "@ " ^ search_pairs f) rest))))
         (named nodes)

let decode_search f =
  let values = sprintf "Yuka.Router.search query %S" f.fname in
  let dec v =
    match f.fty with
    | String -> "Some " ^ v
    | Int -> "Yuka.Router.int_param " ^ v
    | Bool -> sprintf "(match %s with \"true\" -> Some true | \"false\" -> Some false | _ -> None)" v
    | Custom m -> sprintf "%s.of_string %s" m v
  in
  match (f.fkind, f.fty) with
  | Optional, _ -> sprintf "(match %s with v :: _ -> %s | [] -> None)" values (dec "v")
  | Default d, String -> sprintf "(match %s with v :: _ -> v | [] -> (%s))" values d
  | Default d, _ ->
      sprintf "(match %s with v :: _ -> (match %s with Some v -> v | None -> (%s)) | [] -> (%s))"
        values (dec "v") d d
  | Many, String -> values
  | Many, _ -> sprintf "List.filter_map (fun v -> %s) (%s)" (dec "v") values

let rec decode_params params k =
  match params with
  | [] -> k
  | (i, ty) :: rest -> (
      let fn = match ty with Int -> Some "Yuka.Router.int_param" | Custom m -> Some (m ^ ".of_string") | _ -> None in
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
    | Rest _ -> Code (sprintf "String.concat \"/\" (List.map Yuka.Router.encode %s)" v)
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
  :: indent 2 (arms @ [ "| _ -> Yuka.Router.Missing" ])

let generate nodes =
  if named nodes = [] then fail Location.none "Routes.mlx has no named node";
  String.concat "\n" (type_t nodes @ [ "" ] @ href nodes @ [ "" ] @ find nodes) ^ "\n"

let routes_expr input structure =
  let found =
    List.concat_map
      (fun si ->
        match si.pstr_desc with
        | Pstr_value (_, vbs) ->
            List.filter_map
              (fun vb ->
                match vb.pvb_pat.ppat_desc with
                | Ppat_var { txt = "routes"; _ } -> Some vb.pvb_expr
                | _ -> None)
              vbs
        | _ -> [])
      structure
  in
  match found with
  | [ e ] -> e
  | [] -> fail (Location.in_file input) "no let routes = <Router>...</Router>"
  | _ :: e :: _ -> fail e.pexp_loc "let routes is defined twice"

let report (loc : Location.t) msg =
  let s = loc.loc_start and e = loc.loc_end in
  if s.pos_lnum <= 0 then Printf.eprintf "File %S, line 1:\n" s.pos_fname
  else if s.pos_lnum = e.pos_lnum then
      Printf.eprintf "File %S, line %d, characters %d-%d:\n" s.pos_fname s.pos_lnum
        (s.pos_cnum - s.pos_bol) (e.pos_cnum - s.pos_bol)
    else
      Printf.eprintf "File %S, lines %d-%d, characters %d-%d:\n" s.pos_fname s.pos_lnum
        e.pos_lnum (s.pos_cnum - s.pos_bol) (e.pos_cnum - s.pos_bol);
  Printf.eprintf "Error: %s\n" msg

let usage = "usage: yuka-routes --shared FILE.ast"

let () =
  match Array.to_list Sys.argv with
  | [ _; "--shared"; file ] -> (
      match Ast_io.read_binary file with
      | Error e ->
          prerr_endline ("yuka-routes: " ^ e);
          exit 2
      | Ok ast -> (
          match Ast_io.get_ast ast with
          | Intf _ ->
              prerr_endline "yuka-routes: expected an implementation (Routes.mlx)";
              exit 2
          | Impl structure -> (
              let input = Ast_io.get_input_name ast in
              try
                let e = routes_expr input structure in
                print_string (generate (read (Hashtbl.create 16) e))
              with Fail (loc, msg) ->
                report loc msg;
                exit 1)))
  | _ ->
      prerr_endline usage;
      exit 2
