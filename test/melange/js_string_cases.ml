open Yuka

let check = Cases.check
let wide = {js|é€😀|js}

let json_wide_strings () =
  let s = Json.to_string (`String (wide ^ "<\"")) in
  check "printed" ("\"" ^ wide ^ "\\u003c\\\"\"") s;
  check "read back" (wide ^ "<\"") (match Json.of_string s with Ok (`String x) -> x | _ -> "bad")

let template_wide_strings () =
  check "escaped"
    ("<p title=\"" ^ wide ^ "&quot;&amp;\">&amp;" ^ wide ^ "&lt;</p>")
    (Cases.shape_html
       Private.Template.(element "p" [ fixed "title" (wide ^ "\"&") ] [ text ("&" ^ wide ^ "<") ]))

let all = [ ("json: UTF-16 strings", json_wide_strings); ("template: UTF-16 strings", template_wide_strings) ]
