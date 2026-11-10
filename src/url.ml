let blocked = "about:blank#blocked"

let url_name = function
  | "href" | "src" | "action" | "formaction" | "xlink:href" | "xlinkhref" | "poster" | "cite" | "data"
  | "background" | "longdesc" | "manifest" | "codebase" | "icon" ->
      true
  | _ -> false

let animation_name = function "values" | "to" | "from" | "by" -> true | _ -> false
let animation_tag = function "animate" | "set" | "animatemotion" | "animatetransform" -> true | _ -> false
let checked ~tag name = url_name name || (animation_name name && (tag = "" || animation_tag tag))

let navigational ~tag name =
  match (name, tag) with
  | ("action" | "formaction" | "xlink:href" | "xlinkhref"), _ -> true
  | "href", ("a" | "area" | "use" | "") -> true
  | "src", ("iframe" | "frame" | "embed" | "object") -> true
  | "data", ("object" | "") -> true
  | _ -> false

let has_scheme value ~from ~until scheme =
  let n = String.length scheme in
  let rec go i k =
    if k = n then true
    else if i >= until then false
    else
      match value.[i] with
      | '\t' | '\n' | '\r' -> go (i + 1) k
      | c -> Char.lowercase_ascii c = scheme.[k] && go (i + 1) (k + 1)
  in
  let rec start i = if i < until && value.[i] <= ' ' then start (i + 1) else i in
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
      let until = match String.index_from_opt value from ';' with Some i -> i | None -> n in
      unsafe_part ~tag name value ~from ~until || (until < n && parts (until + 1))
    in
    parts 0
  else unsafe_part ~tag name value ~from:0 ~until:n

let check ~tag ~log name value =
  if unsafe ~tag name value then begin
    log name value;
    blocked
  end
  else value
