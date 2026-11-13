open Cmarkit
open Demo_shared.Model

let element ?(attributes = []) tag children = Markup.Element { tag; attributes; children }

let rec join_texts = function
  | Markup.Text "" :: rest -> join_texts rest
  | Markup.Text first :: Markup.Text second :: rest -> join_texts (Markup.Text (first ^ second) :: rest)
  | Markup.Element node :: rest -> Markup.Element { node with children = join_texts node.children } :: join_texts rest
  | node :: rest -> node :: join_texts rest
  | [] -> []

let safe_destination destination =
  let destination = String.trim destination in
  let scheme_end =
    String.to_seq destination
    |> Seq.take_while (fun character -> not (List.mem character [ '/'; '?'; '#' ]))
    |> String.of_seq |> String.index_opt
  in
  match scheme_end ':' with
  | None -> Some destination
  | Some colon -> (
      match String.lowercase_ascii (String.sub destination 0 colon) with
      | "http" | "https" | "mailto" -> Some destination
      | _ -> None)

let link destination children =
  match safe_destination destination with
  | Some href -> [ element "a" ~attributes:[ ("href", href); ("rel", "nofollow noopener") ] children ]
  | None -> children

let plain_text inline = String.concat "\n" (List.map (String.concat "") (Inline.to_plain_text ~break_on_soft:false inline))

let rec inline defs (node : Inline.t) : Markup.node list =
  match node with
  | Inline.Text (text, _) -> [ Text text ]
  | Inline.Inlines (inlines, _) -> List.concat_map (inline defs) inlines
  | Inline.Emphasis (emphasis, _) -> [ element "em" (inline defs (Inline.Emphasis.inline emphasis)) ]
  | Inline.Strong_emphasis (emphasis, _) -> [ element "strong" (inline defs (Inline.Emphasis.inline emphasis)) ]
  | Inline.Ext_strikethrough (strikethrough, _) -> [ element "del" (inline defs (Inline.Strikethrough.inline strikethrough)) ]
  | Inline.Code_span (span, _) -> [ element "code" [ Text (Inline.Code_span.code span) ] ]
  | Inline.Break (break, _) -> ( match Inline.Break.type' break with `Hard -> [ element "br" [] ] | `Soft -> [ Text "\n" ])
  | Inline.Autolink (autolink, _) ->
      let text, _ = Inline.Autolink.link autolink in
      link (if Inline.Autolink.is_email autolink then "mailto:" ^ text else text) [ Text text ]
  | Inline.Link (target, _) | Inline.Image (target, _) -> (
      let children =
        match node with Inline.Image _ -> [ Markup.Text (plain_text (Inline.Link.text target)) ] | _ -> inline defs (Inline.Link.text target)
      in
      match Inline.Link.reference_definition defs target with
      | Some (Link_definition.Def (definition, _)) -> (
          match Link_definition.dest definition with Some (destination, _) -> link destination children | None -> children)
      | _ -> children)
  | Inline.Raw_html (lines, _) -> [ Text (String.concat "\n" (List.map Block_line.tight_to_string lines)) ]
  | Inline.Ext_math_span (math, _) -> [ element "code" [ Text (Inline.Math_span.tex math) ] ]
  | _ -> []

let alignment = function
  | Some `Left -> [ ("style", "text-align:left") ]
  | Some `Center -> [ ("style", "text-align:center") ]
  | Some `Right -> [ ("style", "text-align:right") ]
  | None -> []

let table defs table =
  let columns = Block.Table.col_count table in
  let cells tag aligns cells =
    List.init columns (fun index ->
        let content = match List.nth_opt cells index with Some (cell, _) -> inline defs cell | None -> [] in
        let align = match List.nth_opt aligns index with Some ((align, _), _) -> align | None -> None in
        element tag ~attributes:(alignment align) content)
  in
  let rec rows aligns header body = function
    | [] -> (List.rev header, List.rev body)
    | ((`Header row, _), _) :: rest ->
        let aligns = match rest with ((`Sep aligns, _), _) :: _ -> aligns | _ -> aligns in
        rows aligns (element "tr" (cells "th" aligns row) :: header) body rest
    | ((`Sep aligns, _), _) :: rest -> rows aligns header body rest
    | ((`Data row, _), _) :: rest -> rows aligns header (element "tr" (cells "td" aligns row) :: body) rest
  in
  let header, body = rows [] [] [] (Block.Table.rows table) in
  let sections = (if header = [] then [] else [ element "thead" header ]) @ [ element "tbody" body ] in
  element "div" ~attributes:[ ("class", "table-scroll") ] [ element "table" sections ]

let rec block defs ~tight (node : Block.t) : Markup.node list =
  match node with
  | Block.Blocks (blocks, _) -> List.concat_map (block defs ~tight) blocks
  | Block.Paragraph (paragraph, _) ->
      let content = inline defs (Block.Paragraph.inline paragraph) in
      if tight then content else [ element "p" content ]
  | Block.Heading (heading, _) ->
      let level = min 6 (Block.Heading.level heading + 1) in
      [ element ("h" ^ Int.to_string level) (inline defs (Block.Heading.inline heading)) ]
  | Block.Block_quote (quote, _) -> [ element "blockquote" (block defs ~tight:false (Block.Block_quote.block quote)) ]
  | Block.List (list, _) ->
      let tight = Block.List'.tight list in
      let item (item, _) =
        let content = block defs ~tight (Block.List_item.block item) in
        match Block.List_item.ext_task_marker item with
        | None -> element "li" content
        | Some (marker, _) ->
            let checked = Block.List_item.task_status_of_task_marker marker <> `Unchecked in
            let box =
              element "input" ~attributes:([ ("type", "checkbox"); ("disabled", "") ] @ if checked then [ ("checked", "") ] else []) []
            in
            element "li" ~attributes:[ ("class", "task") ] (box :: Text " " :: content)
      in
      let items = List.map item (Block.List'.items list) in
      [
        (match Block.List'.type' list with
        | `Unordered _ -> element "ul" items
        | `Ordered (1, _) -> element "ol" items
        | `Ordered (start, _) -> element "ol" ~attributes:[ ("start", Int.to_string start) ] items);
      ]
  | Block.Code_block (code, _) | Block.Ext_math_block (code, _) ->
      let language =
        match Option.bind (Block.Code_block.info_string code) (fun (info, _) -> Block.Code_block.language_of_info_string info) with
        | Some (language, _) -> language
        | None -> ""
      in
      [ Code_style.block ~language (String.concat "\n" (List.map Block_line.to_string (Block.Code_block.code code))) ]
  | Block.Html_block (lines, _) -> [ element "p" [ Text (String.concat "\n" (List.map Block_line.to_string lines)) ] ]
  | Block.Thematic_break _ -> [ element "hr" [] ]
  | Block.Ext_table (table_node, _) -> [ table defs table_node ]
  | _ -> []

let render source =
  let document = Doc.of_string ~strict:false source in
  join_texts (block (Doc.defs document) ~tight:false (Doc.block document))
