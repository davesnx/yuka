type shape =
  | Fixed_text of string
  | Fixed_element of { tag : string; attrs : fixed_attr list; children : shape list }
  | Part of int

and fixed_attr = Fixed of string * string | Part_attr of int

type plan = {
  walk : int array;
  kids : int array;
  attrs : int array;
  values : (int * string) array;
}

let kid_only = 1
let kid_first_of_run = 2
let kid_text_before = 4
let kid_svg_in_html = 8
let kid_svg_in_svg = 16
let attr_svg_in_html = 1
let attr_svg_in_svg = 2

let add_escaped b ~quote s =
  let n = String.length s in
  let start = ref 0 in
  let put i entity =
    Buffer.add_substring b s !start (i - !start);
    Buffer.add_string b entity;
    start := i + 1
  in
  for i = 0 to n - 1 do
    match String.unsafe_get s i with
    | '&' -> put i "&amp;"
    | '<' -> put i "&lt;"
    | '>' when not quote -> put i "&gt;"
    | '"' when quote -> put i "&quot;"
    | _ -> ()
  done;
  Buffer.add_substring b s !start (n - !start)

let escape ~quote s =
  let b = Buffer.create (String.length s) in
  add_escaped b ~quote s;
  Buffer.contents b

let is_void = function
  | "area" | "base" | "br" | "col" | "embed" | "hr" | "img" | "input" | "link" | "meta"
  | "source" | "track" | "wbr" ->
      true
  | _ -> false

let void_or_value tag attrs =
  is_void tag
  || (tag = "textarea"
     && let rec has = function
          | [] -> false
          | Fixed ("value", _) :: _ -> true
          | _ :: rest -> has rest
        in
        has attrs)

let select_value tag attrs =
  if tag = "select" then
    List.find_map (function Fixed ("value", v) -> Some v | _ -> None) attrs
  else None

let html shape =
  let b = Buffer.create 256 in
  let after_text = ref false in
  let select_value = ref None in
  let rec go = function
    | Fixed_text "" -> ()
    | Fixed_text t ->
        if !after_text then Buffer.add_string b "<!---->";
        Buffer.add_string b (escape ~quote:false t);
        after_text := true
    | Part _ -> ()
    | Fixed_element { tag; attrs; children } ->
        let resolved =
          List.filter_map
            (function Fixed (name, value) -> Some (name, value) | Part_attr _ -> None)
            attrs
        in
        let value = List.assoc_opt "value" resolved in
        let resolved =
          if tag = "select" || tag = "textarea" then
            List.filter (fun (name, _) -> name <> "value") resolved
          else if
            tag = "option" && value <> None && !select_value = value
            && not (List.mem_assoc "selected" resolved)
          then resolved @ [ ("selected", "") ]
          else resolved
        in
        Buffer.add_char b '<';
        Buffer.add_string b tag;
        List.iter
          (fun (name, v) ->
            Buffer.add_char b ' ';
            Buffer.add_string b name;
            Buffer.add_string b "=\"";
            Buffer.add_string b (escape ~quote:true v);
            Buffer.add_char b '"')
          resolved;
        Buffer.add_char b '>';
        after_text := false;
        if not (is_void tag) then begin
          (match (tag, value) with
          | "textarea", Some v ->
              if String.length v > 0 && v.[0] = '\n' then Buffer.add_char b '\n';
              Buffer.add_string b (escape ~quote:false v)
          | "select", _ ->
              let outer = !select_value in
              select_value := value;
              List.iter go children;
              select_value := outer
          | _ -> List.iter go children);
          Buffer.add_string b "</";
          Buffer.add_string b tag;
          Buffer.add_char b '>';
          after_text := false
        end
  in
  go shape;
  Buffer.contents b

let rec needs = function
  | Fixed_text _ -> false
  | Part _ -> true
  | Fixed_element { tag; attrs; children } ->
      List.exists (function Part_attr _ -> true | Fixed _ -> false) attrs
      || Option.is_some (select_value tag attrs)
      || ((not (void_or_value tag attrs)) && List.exists needs children)

let plan shape =
  let walk = ref [] and count = ref 1 in
  let add src kind steps =
    walk := steps :: ((src * 2) + kind) :: !walk;
    let i = !count in
    incr count;
    i
  in
  let attrs = ref [] and kids = ref [] and values = ref [] in
  let bit flag set = if set then flag else 0 in
  let kid ~part ~at ~anchor ~flags ~finish =
    kids := finish :: flags :: anchor :: at :: part :: !kids
  in
  let rec element idx svg_h svg_s tag fixed children =
    let here_h = svg_h || tag = "svg" and here_s = svg_s || tag = "svg" in
    let inner_h = here_h && tag <> "foreignObject"
    and inner_s = here_s && tag <> "foreignObject" in
    let svg_bits = bit kid_svg_in_html inner_h lor bit kid_svg_in_svg inner_s in
    Option.iter (fun v -> values := (idx, v) :: !values) (select_value tag fixed);
    List.iter
      (function
        | Part_attr i ->
            attrs :=
              (bit attr_svg_in_html here_h lor bit attr_svg_in_svg here_s)
              :: i :: idx :: !attrs
        | Fixed _ -> ())
      fixed;
    if not (void_or_value tag fixed) then
      match children with
      | [ Part i ] ->
          kid ~part:i ~at:idx ~anchor:(-1)
            ~flags:(kid_only lor kid_first_of_run lor svg_bits)
            ~finish:0
      | _ ->
          let dom = ref 0 and after_text = ref false in
          let prev = ref (-1, -1) in
          let get d =
            match !prev with
            | pd, pi when pd = d -> pi
            | pd, pi ->
                let i = if pi >= 0 then add pi 1 (d - pd) else add idx 0 d in
                prev := (d, i);
                i
          in
          let run = ref [] and run_text = ref false in
          let flush anchor finish =
            let parts = List.rev !run in
            run := [];
            let n = List.length parts in
            if n > 0 then begin
              let anchor = match anchor with Some d -> get d | None -> -1 in
              List.iteri
                (fun k i ->
                  kid ~part:i ~at:idx ~anchor
                    ~flags:
                      (bit kid_first_of_run (k = 0)
                      lor bit kid_text_before !run_text
                      lor svg_bits)
                    ~finish:(if k = n - 1 then finish else 0))
                parts
            end
          in
          List.iter
            (function
              | Part i ->
                  if !run = [] then run_text := !after_text;
                  run := i :: !run
              | Fixed_text "" -> ()
              | Fixed_text _ ->
                  let sep = !after_text in
                  flush (Some !dom) (if sep then 1 else 2);
                  if sep then incr dom;
                  incr dom;
                  after_text := true
              | Fixed_element { tag; attrs; children } as e ->
                  flush (Some !dom) 0;
                  if needs e then element (get !dom) inner_h inner_s tag attrs children;
                  incr dom;
                  after_text := false)
            children;
          flush None 0
  in
  (match shape with
  | Fixed_element { tag; attrs; children } -> element 0 false true tag attrs children
  | Fixed_text _ | Part _ -> ());
  {
    walk = Array.of_list (List.rev !walk);
    kids = Array.of_list (List.rev !kids);
    attrs = Array.of_list (List.rev !attrs);
    values = Array.of_list (List.rev !values);
  }

let encode shape =
  let b = Buffer.create 256 in
  let str s =
    String.iter
      (fun c ->
        if Char.code c < 0x10 then begin
          Buffer.add_char b '\x0f';
          Buffer.add_char b (Char.chr (Char.code c + 0x40))
        end
        else Buffer.add_char b c)
      s
  in
  let rec go = function
    | Fixed_text s ->
        Buffer.add_char b '\x08';
        str s
    | Part _ -> Buffer.add_char b '\x07'
    | Fixed_element { tag; attrs; children } ->
        Buffer.add_char b '\x01';
        str tag;
        List.iter
          (function
            | Fixed (n, v) ->
                Buffer.add_char b '\x03';
                str n;
                Buffer.add_char b '\x04';
                str v
            | Part_attr _ -> Buffer.add_char b '\x05')
          attrs;
        Buffer.add_char b '\x02';
        List.iter go children;
        Buffer.add_char b '\x06'
  in
  go shape;
  Buffer.contents b

type ns = Html | Svg

let svg_tag_names =
  [ "altGlyph"; "altGlyphDef"; "altGlyphItem"; "animateColor"; "animateMotion";
    "animateTransform"; "clipPath"; "feBlend"; "feColorMatrix"; "feComponentTransfer";
    "feComposite"; "feConvolveMatrix"; "feDiffuseLighting"; "feDisplacementMap";
    "feDistantLight"; "feDropShadow"; "feFlood"; "feFuncA"; "feFuncB"; "feFuncG"; "feFuncR";
    "feGaussianBlur"; "feImage"; "feMerge"; "feMergeNode"; "feMorphology"; "feOffset";
    "fePointLight"; "feSpecularLighting"; "feSpotLight"; "feTile"; "feTurbulence";
    "foreignObject"; "glyphRef"; "linearGradient"; "radialGradient"; "textPath" ]

let svg_tag_name lower =
  match List.find_opt (fun t -> String.lowercase_ascii t = lower) svg_tag_names with
  | Some t -> t
  | None -> lower

let breaks_out_of_svg = function
  | "b" | "big" | "blockquote" | "body" | "br" | "center" | "code" | "dd" | "div" | "dl" | "dt"
  | "em" | "embed" | "h1" | "h2" | "h3" | "h4" | "h5" | "h6" | "head" | "hr" | "i" | "img" | "li"
  | "listing" | "menu" | "meta" | "nobr" | "ol" | "p" | "pre" | "ruby" | "s" | "small" | "span"
  | "strong" | "strike" | "sub" | "sup" | "table" | "tt" | "u" | "ul" | "var" | "font" ->
      true
  | _ -> false

let closes_p = function
  | "address" | "article" | "aside" | "blockquote" | "center" | "details" | "dialog" | "dir"
  | "div" | "dl" | "fieldset" | "figcaption" | "figure" | "footer" | "header" | "hgroup"
  | "main" | "menu" | "nav" | "ol" | "p" | "search" | "section" | "summary" | "ul" | "h1" | "h2"
  | "h3" | "h4" | "h5" | "h6" | "pre" | "listing" | "form" | "li" | "dd" | "dt" | "plaintext"
  | "table" | "hr" | "xmp" ->
      true
  | _ -> false

let heading = function "h1" | "h2" | "h3" | "h4" | "h5" | "h6" -> true | _ -> false

let special = function
  | Svg, ("foreignObject" | "desc" | "title") -> true
  | Svg, _ -> false
  | Html, t -> (
      heading t
      ||
      match t with
      | "address" | "applet" | "area" | "article" | "aside" | "base" | "basefont" | "bgsound"
      | "blockquote" | "body" | "br" | "button" | "caption" | "center" | "col" | "colgroup" | "dd"
      | "details" | "dir" | "div" | "dl" | "dt" | "embed" | "fieldset" | "figcaption" | "figure"
      | "footer" | "form" | "frame" | "frameset" | "head" | "header" | "hgroup" | "hr" | "html"
      | "iframe" | "img" | "input" | "keygen" | "li" | "link" | "listing" | "main" | "marquee"
      | "menu" | "meta" | "nav" | "noembed" | "noframes" | "noscript" | "object" | "ol" | "p"
      | "param" | "plaintext" | "pre" | "script" | "search" | "section" | "select" | "source"
      | "style" | "summary" | "table" | "tbody" | "td" | "template" | "textarea" | "tfoot" | "th"
      | "thead" | "title" | "tr" | "track" | "ul" | "wbr" | "xmp" ->
          true
      | _ -> false)

let scope_boundary = function
  | Svg, ("foreignObject" | "desc" | "title") -> true
  | Svg, _ -> false
  | Html, ("applet" | "caption" | "html" | "table" | "td" | "th" | "marquee" | "object" | "template")
    ->
      true
  | Html, _ -> false

let rec in_scope ?(button = false) name = function
  | [] -> false
  | (Html, t) :: _ when t = name -> true
  | ((ns, t) as e) :: rest ->
      if scope_boundary e || (button && ns = Html && t = "button") then false
      else in_scope ~button name rest

let table_parent = function
  | "caption" | "colgroup" | "thead" | "tbody" | "tfoot" -> Some [ "table" ]
  | "col" -> Some [ "colgroup" ]
  | "tr" -> Some [ "thead"; "tbody"; "tfoot" ]
  | "td" | "th" -> Some [ "tr" ]
  | _ -> None

let table_children = function
  | "table" -> Some [ "caption"; "colgroup"; "thead"; "tbody"; "tfoot"; "script"; "style"; "template" ]
  | "thead" | "tbody" | "tfoot" -> Some [ "tr"; "script"; "style"; "template" ]
  | "tr" -> Some [ "td"; "th"; "script"; "style"; "template" ]
  | "colgroup" -> Some [ "col"; "template" ]
  | _ -> None

let ascii_space = function ' ' | '\t' | '\n' | '\012' | '\r' -> true | _ -> false

let parser_changes ~svg shape =
  let texts children =
    List.filter_map (function Fixed_text t when t <> "" -> Some t | _ -> None) children
  in
  let has_element children = List.exists (function Fixed_element _ -> true | _ -> false) children in
  let bad_text t = String.contains t '\r' || String.contains t '\000' in
  let rec first_output = function
    | [] -> None
    | (Part _ | Fixed_text "") :: rest -> first_output rest
    | c :: _ -> Some c
  in
  let rec element stack ns tag attrs children =
    let lower = String.lowercase_ascii tag in
    let parent = match stack with (Html, p) :: _ -> Some p | _ -> None in
    let html_rules () =
      tag <> lower
      || (match lower with
         | "html" | "head" | "body" | "frameset" | "frame" | "image" | "plaintext" | "math" -> true
         | "template" -> children <> []
         | _ -> false)
      || (match (table_parent lower, stack) with
         | Some _, [] -> false
         | Some parents, _ -> not (match parent with Some p -> List.mem p parents | None -> false)
         | None, _ -> false)
      || (match parent with
         | Some p -> (
             (match table_children p with Some allowed -> not (List.mem lower allowed) | None -> false)
             || (match p with
                | "select" -> not (List.mem lower [ "option"; "optgroup"; "hr" ])
                | "optgroup" -> lower <> "option"
                | "option" -> true
                | _ -> false)
             || (heading lower && heading p))
         | None -> false)
      || (match lower with
         | "rb" | "rtc" -> parent <> Some "ruby"
         | "rt" | "rp" -> not (parent = Some "ruby" || parent = Some "rtc")
         | _ -> false)
      || (closes_p lower && in_scope ~button:true "p" stack)
      || (lower = "li" && list_item [ "li" ] stack)
      || ((lower = "dd" || lower = "dt") && list_item [ "dd"; "dt" ] stack)
      || (lower = "a" && open_a stack)
      || ((lower = "nobr" || lower = "button") && in_scope lower stack)
      || (lower = "form" && List.exists (fun e -> e = (Html, "form")) stack)
      || (match (lower, first_output children) with
         | ("pre" | "listing" | "textarea"), Some (Fixed_text t) -> t.[0] = '\n'
         | _ -> false)
      || (match lower with
         | "title" | "textarea" -> has_element children || List.length (texts children) > 1
         | "xmp" | "iframe" | "noembed" | "noframes" | "noscript" | "style" | "script" ->
             has_element children
             || (match texts children with
                | [] -> false
                | [ t ] -> String.exists (fun c -> c = '&' || c = '<' || c = '>') t
                | _ -> true)
         | _ -> false)
      || (match lower with
         | "param" | "keygen" | "basefont" | "bgsound" -> has_element children || texts children <> []
         | _ -> false)
      || (match table_children lower with
         | Some _ -> List.exists (fun t -> not (String.for_all ascii_space t)) (texts children)
         | None -> false)
    in
    match ns with
    | Svg ->
        breaks_out_of_svg lower || is_void lower || lower = "math" || svg_tag_name lower <> tag
        || inside stack (Svg, tag) children
    | Html ->
        html_rules ()
        || (not (void_or_value lower attrs))
           && inside stack (if lower = "svg" then (Svg, tag) else (Html, lower)) children
  and inside stack ((ns, _) as here) children =
    let stack = here :: stack in
    let child_ns =
      match here with
      | Svg, ("foreignObject" | "desc" | "title") -> Html
      | _ -> ns
    in
    List.exists
      (function
        | Fixed_text t -> bad_text t
        | Part _ -> false
        | Fixed_element { tag; attrs; children } -> element stack child_ns tag attrs children)
      children
  and list_item names = function
    | [] -> false
    | (Html, t) :: _ when List.mem t names -> true
    | (Html, ("address" | "div" | "p")) :: rest -> list_item names rest
    | e :: rest -> if special e then false else list_item names rest
  and open_a = function
    | [] -> false
    | (Html, "a") :: _ -> true
    | (Html, ("applet" | "object" | "marquee" | "template" | "td" | "th" | "caption")) :: _ -> false
    | _ :: rest -> open_a rest
  in
  match shape with
  | Fixed_element { tag; attrs; children } ->
      if svg then element [ (Svg, "svg") ] Svg tag attrs children
      else element [] Html tag attrs children
  | Fixed_text _ | Part _ -> true
