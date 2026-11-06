open Types

type 'kind element = node
type 'kind attribute = attr

let text s = Text s
let int n = Text (string_of_int n)
let float f =
  Text
    (if Float.is_nan f then "NaN"
     else if f = Float.infinity then "Infinity"
     else if f = Float.neg_infinity then "-Infinity"
     else Json.to_string (`Float f))
let empty = Fragment []
let list children = Fragment children
let array children = Fragment (Array.to_list children)
let format fmt = Printf.ksprintf text fmt
let fragment children = Fragment children
let lower tag attrs children = Element { tag; attrs; children }
let attr name value = Static (name, value)
let hole f = Hole f
let slot s = Slot s
let template id node = Template { id; node }

module Slot = struct
  let make content = { content = Some content; dom = ref [] }
end

let hole_attr name f = Dynamic (name, f)
let on name handler = Handler (name, handler)

let each ?(equal = ( = )) ~key items render =
  Each { items; key; equal; render }

module Await = struct
  let make ~async ~loading ?(failed = fun _ -> Fragment []) ~children () =
    Await { async; loading; failed; render = children }
end
