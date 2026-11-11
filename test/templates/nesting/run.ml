open Yuka

type node

let () =
  [%mel.raw
    {|(function () {
  const { JSDOM } = require("jsdom");
  const dom = new JSDOM("<!doctype html><html><body></body></html>");
  globalThis.window = dom.window;
  globalThis.document = dom.window.document;
})()|}]

let set_exit_code : int -> unit = [%mel.raw "function (c) { process.exitCode = c }"]

let parse : string -> bool -> node Js.null =
  [%mel.raw
    {|function (markup, svg) {
  const t = document.createElement("template");
  t.innerHTML = svg ? "<svg>" + markup + "</svg>" : markup;
  const only = function (c) { return c && !c.nextSibling ? c : null; };
  const top = only(t.content.firstChild);
  return svg && top ? only(top.firstChild) : top;
}|}]

external node_type : node -> int = "nodeType" [@@mel.get]
external local_name : node -> string = "localName" [@@mel.get]
external data : node -> string = "data" [@@mel.get]
external first_child : node -> node Js.null = "firstChild" [@@mel.get]
external next_sibling : node -> node Js.null = "nextSibling" [@@mel.get]

let failures = ref 0

let fail name =
  incr failures;
  print_endline ("FAIL " ^ name)

type shape = Element of string * (string * string) list * shape list | Text of string | Part

let is_void = function
  | "area" | "base" | "br" | "col" | "embed" | "hr" | "img" | "input" | "link" | "meta" | "source"
  | "track" | "wbr" ->
      true
  | _ -> false

let rec same shape n =
  match shape with
  | Element (tag, attrs, children) ->
      node_type n = 1
      && local_name n = tag
      && (is_void tag
         || (tag = "textarea" && List.mem_assoc "value" attrs)
         || same_children children (first_child n))
  | Text _ | Part -> false

and same_children children cur =
  let rec go after_text cur = function
    | [] -> cur == Js.null
    | (Part | Text "") :: rest -> go after_text cur rest
    | Text t :: rest -> (
        let cur =
          if not after_text then cur
          else
            match Js.Null.toOption cur with
            | Some c when node_type c = 8 -> next_sibling c
            | _ -> Js.null
        in
        match Js.Null.toOption cur with
        | Some c -> node_type c = 3 && data c = t && go true (next_sibling c) rest
        | None -> false)
    | (Element _ as e) :: rest -> (
        match Js.Null.toOption cur with
        | Some c -> same e c && go false (next_sibling c) rest
        | None -> false)
  in
  go false cur children

let to_template shape =
  let parts = ref 0 in
  let rec go = function
    | Element (tag, attrs, children) ->
        Template.element tag
          (List.map (fun (n, v) -> Template.fixed n v) attrs)
          (List.map go children)
    | Text t -> Template.text t
    | Part ->
        incr parts;
        Template.part (!parts - 1)
  in
  go shape

let seed = ref 7

let pick l =
  seed := ((!seed * 1103515245) + 12345) land 0x3fffffff;
  List.nth l ((!seed lsr 8) mod List.length l)

let html_tags =
  [ "div"; "p"; "span"; "a"; "b"; "i"; "font"; "table"; "tbody"; "thead"; "tr"; "td"; "th";
    "caption"; "colgroup"; "col"; "ul"; "ol"; "li"; "dl"; "dd"; "dt"; "h1"; "h2"; "button"; "form";
    "select"; "option"; "optgroup"; "textarea"; "pre"; "title"; "svg"; "ruby"; "rt"; "rb"; "nobr";
    "template"; "img"; "br"; "hr"; "input"; "wbr"; "param"; "keygen"; "basefont"; "bgsound"; "area";
    "source"; "track"; "embed"; "meta"; "link"; "base"; "frame"; "section"; "summary"; "details";
    "label"; "em"; "xmp"; "iframe"; "listing"; "math"; "foreignObject"; "g"; "circle"; "desc";
    "image"; "main"; "object"; "marquee"; "my-el" ]

let svg_roots =
  [ "g"; "circle"; "text"; "foreignObject"; "desc"; "linearGradient"; "clippath"; "a"; "title";
    "span"; "wbr"; "param" ]

let texts = [ "x"; " "; "\nx"; "a&b"; "1 < 2" ]

let attrs_for = function
  | "textarea" -> pick [ []; [ ("value", "\nv") ] ]
  | "select" -> pick [ []; [ ("value", "a") ] ]
  | "font" -> pick [ []; [ ("color", "red") ] ]
  | _ -> []

let rec gen depth tag =
  let n = if depth = 0 then 0 else pick [ 0; 1; 1; 2; 2; 3 ] in
  let attrs = attrs_for tag in
  Element
    ( tag,
      attrs,
      List.init n (fun _ ->
          match pick [ `E; `E; `E; `T; `P ] with
          | `E -> gen (depth - 1) (pick html_tags)
          | `T -> Text (pick texts)
          | `P -> Part) )

let rec select_in_svg ~svg = function
  | Element ("select", _, _) when svg -> true
  | Element (tag, _, children) ->
      let svg = (svg || tag = "svg") && tag <> "foreignObject" in
      List.exists (select_in_svg ~svg) children
  | Text _ | Part -> false

let () =
  let kept = ref 0 and lowered = ref 0 and lowered_same = ref 0 and skipped = ref 0 and total = ref 0 in
  let run count roots =
    for _ = 1 to count do
      let shape = gen 3 (pick roots) in
      let t = to_template shape in
      let html = Private.template_html (Private.template t) in
      List.iter
        (fun svg ->
          if select_in_svg ~svg shape then incr skipped
          else begin
            incr total;
            let same =
              match Js.Null.toOption (parse html svg) with Some n -> same shape n | None -> false
            in
            if Private.parser_changes ~svg t then begin
              incr lowered;
              if same then incr lowered_same
            end
            else begin
              incr kept;
              if not same then fail ((if svg then "svg context: " else "html context: ") ^ html)
            end
          end)
        [ false; true ]
    done
  in
  run 3000 html_tags;
  run 1500 svg_roots;
  print_endline "not generated: search (jsdom does not treat it as a special element, against the standard)";
  Printf.printf
    "skipped %d checks of a select inside svg content (jsdom resets the insertion mode by the tag name of an svg select, against the standard)\n"
    !skipped;
  Printf.printf
    "nesting check: %d checks, %d kept, %d not kept (%d of them would parse as their shape)\n"
    !total !kept !lowered !lowered_same;
  if !failures > 0 then set_exit_code 1 else print_endline "nesting check: ok"
