open Demo_shared.Model

type theme = { slug : string; label : string; colors : Ochre.Theme.theme }

let themes =
  [
    { slug = "dark"; label = "Dark+"; colors = Ochre.Theme.dark };
    { slug = "one-dark"; label = "One Dark"; colors = Ochre.Theme.one_dark };
    { slug = "nord"; label = "Nord"; colors = Ochre.Theme.nord };
    { slug = "tokyonight"; label = "Tokyo Night"; colors = Ochre.Theme.tokyonight };
    { slug = "gruvbox"; label = "Gruvbox"; colors = Ochre.Theme.gruvbox };
    { slug = "light"; label = "Light+"; colors = Ochre.Theme.light };
  ]

let grammars =
  [
    ("ocaml", Tm_grammar_ocaml.json);
    ("javascript", Tm_grammar_javascript.json);
    ("typescript", Tm_grammar_typescript.json);
    ("shellscript", Tm_grammar_shellscript.json);
    ("json", Tm_grammar_json.json);
    ("less", Tm_grammar_less.json);
  ]

let highlighter = Ochre.load_exn grammars

let grammar_of_language language =
  match String.lowercase_ascii language with
  | "ocaml" | "ml" | "mli" -> Some "ocaml"
  | "javascript" | "js" | "jsx" | "mjs" -> Some "javascript"
  | "typescript" | "ts" | "tsx" -> Some "typescript"
  | "shellscript" | "shell" | "sh" | "bash" | "zsh" | "console" -> Some "shellscript"
  | "json" -> Some "json"
  | "css" | "less" -> Some "less"
  | _ -> None

let normalize color =
  let color = String.lowercase_ascii color in
  if String.length color = 9 && String.ends_with ~suffix:"ff" color then String.sub color 0 7 else color

let declarations index (theme : theme) (token : Ochre.Token.styled_token) =
  let color =
    match token.foreground with
    | Some color when normalize color <> normalize theme.colors.fg ->
        [ Printf.sprintf "--c%d:%s" index (normalize color) ]
    | _ -> []
  in
  let italic = if List.mem Ochre.Token.Italic token.font_style then [ Printf.sprintf "--i%d:italic" index ] else [] in
  let bold = if List.mem Ochre.Token.Bold token.font_style then [ Printf.sprintf "--b%d:bold" index ] else [] in
  color @ italic @ bold

let token_node (variants : Ochre.Token.styled_token list) =
  let text = (List.hd variants).text in
  match if String.trim text = "" then [] else List.concat (List.mapi (fun index (theme, token) -> declarations index theme token) (List.combine themes variants)) with
  | [] -> Markup.Text text
  | styles -> Markup.Element { tag = "span"; attributes = [ ("style", String.concat ";" styles) ]; children = [ Text text ] }

let rec merge_spans = function
  | Markup.Element { tag = "span"; attributes; children = [ Text first ] }
    :: Markup.Element { tag = "span"; attributes = next_attributes; children = [ Text second ] }
    :: rest
    when attributes = next_attributes ->
      merge_spans (Markup.Element { tag = "span"; attributes; children = [ Text (first ^ second) ] } :: rest)
  | node :: rest -> node :: merge_spans rest
  | [] -> []

let rec transpose = function [] | [] :: _ -> [] | rows -> List.map List.hd rows :: transpose (List.map List.tl rows)

let highlight grammar source =
  match List.map (fun theme -> Ochre.to_tokens highlighter ~theme:theme.colors ~lang:grammar source) themes with
  | lines_per_theme ->
      Some (merge_spans (List.concat_map (fun lines -> List.map token_node (transpose lines)) (transpose lines_per_theme)))
  | exception (Failure _ | Invalid_argument _ | Not_found) -> None

let cache : (string * string, Markup.node) Hashtbl.t = Hashtbl.create 64

let block ~language source =
  let key = (language, source) in
  match Hashtbl.find_opt cache key with
  | Some node -> node
  | None ->
      let grammar = grammar_of_language language in
      let children = match Option.bind grammar (fun grammar -> highlight grammar source) with Some nodes -> nodes | None -> [ Markup.Text source ] in
      let attributes = ("class", "code-block") :: ("tabindex", "0") :: (if language = "" then [] else [ ("data-language", language) ]) in
      let node = Markup.Element { tag = "pre"; attributes; children = [ Element { tag = "code"; attributes = []; children } ] } in
      Hashtbl.replace cache key node;
      node

let style_sheet =
  let first = List.hd themes in
  let rule index theme =
    Printf.sprintf
      "[data-code-theme=%s] .code-block{background:%s;color:%s}[data-code-theme=%s] .code-block span{color:var(--c%d);font-style:var(--i%d);font-weight:var(--b%d)}"
      theme.slug theme.colors.bg theme.colors.fg theme.slug index index index
  in
  Printf.sprintf ".code-block{background:%s;color:%s}.code-block span{color:var(--c0);font-style:var(--i0);font-weight:var(--b0)}%s"
    first.colors.bg first.colors.fg
    (String.concat "" (List.mapi rule themes))

let script =
  Printf.sprintf
    {|(function(){var root=document.documentElement,key="yuka-demo-code-theme",themes=[%s];try{var saved=localStorage.getItem(key);if(themes.indexOf(saved)>=0)root.setAttribute("data-code-theme",saved)}catch(error){}customElements.define("code-style-picker",class extends HTMLElement{connectedCallback(){var picker=this;var bind=function(){var select=picker.querySelector("select");if(!select)return false;if(!select.onchange)select.onchange=function(){root.setAttribute("data-code-theme",select.value);try{localStorage.setItem(key,select.value)}catch(error){}};var wanted=root.getAttribute("data-code-theme");if(wanted)select.value=wanted;return !wanted||select.value===wanted};if(!bind()){var observer=new MutationObserver(function(){if(bind())observer.disconnect()});observer.observe(picker,{childList:true,subtree:true})}}})})()|}
    (String.concat "," (List.map (fun theme -> "\"" ^ theme.slug ^ "\"") themes))

let head = "<style>" ^ style_sheet ^ "</style><script data-code-style>" ^ script ^ "</script>"

let picker () : Yuka.server Yuka.element =
  Yuka.element "code-style-picker" [ Yuka.attr "class" "code-style" ]
    [
      Yuka.element "select" [ Yuka.attr "class" "code-style-select"; Yuka.attr "aria-label" "Code style"; Yuka.attr "title" "Code style" ]
        (List.map (fun theme -> Yuka.element "option" [ Yuka.attr "value" theme.slug ] [ Yuka.text theme.label ]) themes);
    ]
