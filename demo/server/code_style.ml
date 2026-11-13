open Demo_shared

let colors = function
  | Theme.Code.Dark_plus -> Ochre.Theme.dark
  | One_dark -> Ochre.Theme.one_dark
  | Nord -> Ochre.Theme.nord
  | Tokyo_night -> Ochre.Theme.tokyonight
  | Gruvbox -> Ochre.Theme.gruvbox
  | Light_plus -> Ochre.Theme.light

let themes = List.map colors Theme.Code.all

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

let declarations index (theme : Ochre.Theme.theme) (token : Ochre.Token.styled_token) =
  let color =
    match token.foreground with
    | Some color when normalize color <> normalize theme.fg ->
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
  match List.map (fun theme -> Ochre.to_tokens highlighter ~theme ~lang:grammar source) themes with
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

let index_of code = Option.value (List.find_index (fun candidate -> candidate = code) Theme.Code.all) ~default:0
let token_style index = Printf.sprintf "color:var(--c%d);font-style:var(--i%d);font-weight:var(--b%d)" index index index

let keyword (theme : Ochre.Theme.theme) =
  match List.concat (Ochre.to_tokens highlighter ~theme ~lang:"ocaml" "let") with
  | { foreground = Some color; _ } :: _ -> normalize color
  | _ -> normalize theme.fg

let style_sheet =
  let auto theme =
    Printf.sprintf "[data-theme=%s]:not([data-code-theme]) .code-block span{%s}" (Theme.slug theme)
      (token_style (index_of (Theme.Code.auto theme)))
  in
  let explicit index code =
    let theme = colors code and slug = Theme.Code.slug code in
    Printf.sprintf "[data-code-theme=%s] .code-block{background:%s;color:%s}[data-code-theme=%s] .code-block span{%s}[data-code=%s]{--swatch-bg:%s;--swatch-key:%s}"
      slug theme.bg theme.fg slug (token_style index) slug theme.bg (keyword theme)
  in
  Printf.sprintf ".code-block{background:var(--bg-sidebar);color:var(--text)}.code-block span{%s}%s%s"
    (token_style (index_of (Theme.Code.auto Theme.Dark)))
    (String.concat "" (List.map auto Theme.all))
    (String.concat "" (List.mapi explicit Theme.Code.all))

let head = "<style>" ^ style_sheet ^ "</style>"
