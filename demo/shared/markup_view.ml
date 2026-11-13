let rec node : Markup.node -> _ Yuka.element = function
  | Text text -> Yuka.text text
  | Element { tag; attributes; children } ->
      Yuka.element tag (List.map (fun (name, value) -> Yuka.attr name value) attributes) (List.map node children)

let nodes markup = Yuka.fragment (List.map node markup)
