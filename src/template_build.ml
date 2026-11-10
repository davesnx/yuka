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

let escape ~quote s =
  let b = Buffer.create (String.length s) in
  String.iter
    (function
      | '&' -> Buffer.add_string b "&amp;"
      | '<' -> Buffer.add_string b "&lt;"
      | '>' when not quote -> Buffer.add_string b "&gt;"
      | '"' when quote -> Buffer.add_string b "&quot;"
      | c -> Buffer.add_char b c)
    s;
  Buffer.contents b

let is_void = function
  | "area" | "base" | "br" | "col" | "embed" | "hr" | "img" | "input" | "link" | "meta"
  | "source" | "track" | "wbr" ->
      true
  | _ -> false

let void_or_value tag attrs =
  is_void tag
  || (tag = "textarea"
     && List.exists (function Fixed ("value", _) -> true | _ -> false) attrs)

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
