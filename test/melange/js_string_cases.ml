open Yuka

let check = Cases.check
let wide = {js|é€😀|js}

let json_wide_strings () =
  let s = Json.to_string (`String (wide ^ "<\"")) in
  check "printed" ("\"" ^ wide ^ "\\u003c\\\"\"") s;
  check "read back" (wide ^ "<\"") (match Json.of_string s with Ok (`String x) -> x | _ -> "bad")

let codec_cuts_wide_strings () =
  let tens = wide ^ wide ^ wide in
  check "cut at 40"
    ("expected int, got \"ab" ^ tens ^ tens ^ tens ^ {js|é|js} ^ "...")
    (match Codec.decode Codec.int (`String ("ab" ^ tens ^ tens ^ tens ^ tens)) with
    | Ok _ -> "ok"
    | Error m -> m)

let template_wide_strings () =
  check "escaped"
    ("<p title=\"" ^ wide ^ "&quot;&amp;\">&amp;" ^ wide ^ "&lt;</p>")
    (Cases.shape_html
       Private.Template.(element "p" [ fixed "title" (wide ^ "\"&") ] [ text ("&" ^ wide ^ "<") ]))

let all =
  [
    ("json: UTF-16 strings", json_wide_strings);
    ("codec: error cut in UTF-16 strings", codec_cuts_wide_strings);
    ("template: UTF-16 strings", template_wide_strings);
  ]
