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

let has_scheme value ~from ~until scheme =
  let n = String.length scheme in
  let rec go i k =
    if k = n then true
    else if i >= until then false
    else
      match String.unsafe_get value i with
      | '\t' | '\n' | '\r' -> go (i + 1) k
      | c ->
          (if c >= 'A' && c <= 'Z' then Char.unsafe_chr (Char.code c + 32) else c) = String.unsafe_get scheme k
          && go (i + 1) (k + 1)
  in
  let rec start i = if i < until && String.unsafe_get value i <= ' ' then start (i + 1) else i in
  go (start from) 0

let unsafe_part ~tag name value ~from ~until =
  has_scheme value ~from ~until "javascript:"
  || has_scheme value ~from ~until "vbscript:"
  || (navigational ~tag name && has_scheme value ~from ~until "data:")

let unsafe ~tag name value =
  checked ~tag name
  &&
  let n = String.length value in
  if animation_name name then
    let rec parts from =
      let rec semi i = if i < n && String.unsafe_get value i <> ';' then semi (i + 1) else i in
      let until = semi from in
      unsafe_part ~tag name value ~from ~until || (until < n && parts (until + 1))
    in
    parts 0
  else unsafe_part ~tag name value ~from:0 ~until:n

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

let valid_name name =
  name <> ""
  && not (String.length name > 1 && Char.lowercase_ascii name.[0] = 'o' && Char.lowercase_ascii name.[1] = 'n')
  && not
       (String.exists
          (fun c -> c <= ' ' || c = '\127' || c = '"' || c = '\'' || c = '>' || c = '/' || c = '=' || c = '<')
          name)

let valid_tag tag =
  tag <> ""
  && (match tag.[0] with 'a' .. 'z' | 'A' .. 'Z' -> true | _ -> false)
  && String.for_all (function 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' -> true | _ -> false) tag
