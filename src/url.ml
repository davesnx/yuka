let blocked = "about:blank#blocked"

let url_name = function
  | "href" | "src" | "action" | "formaction" | "xlink:href" | "xlinkhref" | "poster" | "cite" | "data"
  | "background" | "longdesc" | "manifest" | "codebase" | "icon" ->
      true
  | _ -> false

let animation_name = function "values" | "to" | "from" | "by" -> true | _ -> false
let animation_tag = function "animate" | "set" | "animatemotion" | "animatetransform" -> true | _ -> false
let html_sink ~tag name = (name = "srcdoc" && tag = "iframe") || (name = "href" && tag = "base")

let checked ~tag name =
  url_name name || html_sink ~tag name || (animation_name name && animation_tag tag)

let navigational ~tag name =
  match (name, tag) with
  | ("action" | "formaction" | "xlink:href" | "xlinkhref"), _ -> true
  | "href", ("a" | "area" | "use") -> true
  | "src", ("iframe" | "frame" | "embed" | "object" | "script") -> true
  | "href", "script" -> true
  | "data", "object" -> true
  | _ -> false

let rec scheme_at value i until scheme k =
  k = String.length scheme
  || i < until
     &&
     let c = String.unsafe_get value i in
     if c = '\t' || c = '\n' || c = '\r' then scheme_at value (i + 1) until scheme k
     else
       (if c >= 'A' && c <= 'Z' then Char.unsafe_chr (Char.code c + 32) else c) = String.unsafe_get scheme k
       && scheme_at value (i + 1) until scheme (k + 1)

let rec first_byte value i until = if i < until && String.unsafe_get value i <= ' ' then first_byte value (i + 1) until else i

let has_scheme value ~from ~until scheme = scheme_at value (first_byte value from until) until scheme 0

let unsafe_part ~tag name value ~from ~until =
  let i = first_byte value from until in
  i < until
  &&
  let c = Char.unsafe_chr (Char.code (String.unsafe_get value i) lor 32) in
  (c = 'j' && scheme_at value i until "javascript:" 0)
  || (c = 'v' && scheme_at value i until "vbscript:" 0)
  || (c = 'd' && navigational ~tag name && scheme_at value i until "data:" 0)

let rec semicolon value i = if i < String.length value && String.unsafe_get value i <> ';' then semicolon value (i + 1) else i

let rec unsafe_parts ~tag name value from =
  let until = semicolon value from in
  unsafe_part ~tag name value ~from ~until || (until < String.length value && unsafe_parts ~tag name value (until + 1))

let unsafe ~tag name value =
  checked ~tag name
  && if animation_name name then unsafe_parts ~tag name value 0 else unsafe_part ~tag name value ~from:0 ~until:(String.length value)

let check ~tag ~log name value =
  if html_sink ~tag name then begin
    log name value;
    ""
  end
  else if unsafe ~tag name value then begin
    log name value;
    blocked
  end
  else value

let rec bad_byte name i =
  i < String.length name
  &&
  let c = String.unsafe_get name i in
  c <= ' ' || c = '\127' || c = '"' || c = '\'' || c = '>' || c = '/' || c = '=' || c = '<' || bad_byte name (i + 1)

let valid_name name =
  name <> ""
  && not (String.length name > 1 && Char.lowercase_ascii name.[0] = 'o' && Char.lowercase_ascii name.[1] = 'n')
  && not (bad_byte name 0)

let valid_tag tag =
  tag <> ""
  && (match tag.[0] with 'a' .. 'z' | 'A' .. 'Z' -> true | _ -> false)
  && String.for_all (function 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' -> true | _ -> false) tag
