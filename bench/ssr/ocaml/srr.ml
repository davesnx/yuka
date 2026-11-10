open Ssr_data.Data

let el tag cls children = React.createElement tag [ React.JSX.String ("class", "className", cls) ] children
let text = React.string

let row i =
  React.Upper_case_component
    ( "Row",
      fun () ->
        React.createElement "li"
          [ React.JSX.String ("class", "className", "issue") ]
          [
            React.createElement "a"
              [ React.JSX.String ("class", "className", "row"); React.JSX.String ("href", "href", "/issue/" ^ i.id) ]
              [
                el "span" "id" [ text i.id ];
                el "span" "title" [ text i.title ];
                el "span" ("status status-" ^ slug i.status) [ text i.status ];
                el "span" "priority" [ text i.priority ];
                el "span" "assignee" [ text (Option.value i.assignee ~default:"Unassigned") ];
                el "span" "labels" (List.map (fun l -> el "span" "label" [ text l ]) i.labels);
              ];
          ] )

let page issues =
  React.createElement "html" []
    [
      React.createElement "head" []
        [
          React.createElement "meta" [ React.JSX.String ("charset", "charSet", "utf-8") ] [];
          React.createElement "title" [] [ text "Issues" ];
          React.createElement "link"
            [ React.JSX.String ("rel", "rel", "stylesheet"); React.JSX.String ("href", "href", "/static/style.css") ]
            [];
        ];
      React.createElement "body" []
        [
          React.createElement "main" []
            [ React.createElement "h1" [] [ text "All issues" ]; el "ul" "issues" (List.map row issues) ];
        ];
    ]

let () =
  let port, issues = args () in
  Dream.run ~interface:"127.0.0.1" ~port
  @@ Dream.router
       [ Dream.get "/" (fun _ -> Dream.html (ReactDOM.renderToString (page issues))) ]
