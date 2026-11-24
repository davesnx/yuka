let on : bool = [%mel.raw {|typeof __YUKA_DEV__ === "undefined" || __YUKA_DEV__|}]

external truthy : 'a -> bool = "Boolean"
external stringify : string -> string = "stringify" [@@mel.scope "JSON"]
external warn : string -> unit = "warn" [@@mel.scope "console"]
external error_with : string -> Js.Exn.t -> unit = "error" [@@mel.scope "console"]
external make_error : string -> Js.Exn.t = "Error" [@@mel.new]
external node_type : Web.node -> int = "nodeType" [@@mel.get]
external local_name : Web.node -> string = "localName" [@@mel.get]
external node_name : Web.node -> string = "nodeName" [@@mel.get]
external data : Web.node -> string = "data" [@@mel.get]
external slice : string -> int -> int -> string = "slice" [@@mel.send]
external get_attribute : Web.node -> string -> string Js.null = "getAttribute" [@@mel.send]
external parent_node : Web.node -> Web.node Js.null = "parentNode" [@@mel.get]
external previous_element_sibling : Web.node -> Web.node Js.null = "previousElementSibling" [@@mel.get]
external marked : Web.node -> bool Js.undefined = "__yuka_mismatch" [@@mel.get]
external mark : Web.node -> bool -> unit = "__yuka_mismatch" [@@mel.set]
external unshift : string array -> string -> unit = "unshift" [@@mel.send]
external join : string array -> string -> string = "join" [@@mel.send]

(* Melange represents [Some n] of a DOM node as [n] itself and [None] as [undefined]. *)
external nullable_of_option : Web.node option -> Web.node Js.nullable = "%identity"

let describe n =
  match Js.Nullable.toOption n with
  | None -> "nothing"
  | Some n -> (
      match node_type n with
      | 1 -> "<" ^ local_name n ^ ">"
      | 3 ->
          let d = data n in
          stringify (if String.length d > 30 then slice d 0 30 ^ "..." else d)
      | 8 -> "<!--" ^ data n ^ "-->"
      | _ -> node_name n)

let rec count name i s =
  match Js.Null.toOption (previous_element_sibling s) with
  | Some p -> count name (if local_name p = name then i + 1 else i) p
  | None -> i

let mismatch parent expected found =
  if on then
    let found = nullable_of_option found in
    let seen =
      match Js.Nullable.toOption found with
      | Some f ->
          truthy (marked f) && expected = "nothing"
          ||
          (mark f true;
           false)
      | None -> false
    in
    if not seen then (
      let path = [||] and island = ref "" in
      let rec up n =
        match Js.Null.toOption n with
        | Some e when node_type e = 1 && local_name e <> "body" ->
            let name = local_name e in
            if name = "yuka-island" then
              island := match Js.Null.toOption (get_attribute e "data-name") with Some s -> s | None -> ""
            else
              let i = count name 1 e in
              unshift path (if i > 1 then name ^ ":" ^ string_of_int i else name);
              up (parent_node e)
        | _ -> ()
      in
      up (Js.Null.return parent);
      let where = join path " > " in
      warn
        ("yuka: hydration mismatch in island "
        ^ (if !island <> "" then !island else "?")
        ^ " at "
        ^ (if where <> "" then where else "root")
        ^ ": expected " ^ expected ^ ", found " ^ describe found))

let untracked_get () =
  if on then
    error_with
      "[yuka] State.get with nothing tracking it, during the render of a component.\n\
      \  It reads one time and never updates. Read it in markup, a memo or an effect,\n\
      \  or use State.peek for one read."
      (make_error "State.get")
