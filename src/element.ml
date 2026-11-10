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
let fragment children = Fragment children
let lower tag attrs children = Element { tag; attrs; children }
let attr name value = Static (name, value)
let hole f = Hole f
let slot s = Slot s

module Slot = struct
  let make content = { content = Some content; dom = ref [] }
end

module Template = struct
  type t = template
  type nonrec shape = shape
  type attr = fixed_attr
  type 'kind part = Types.part

  let text s = Fixed_text s
  let element tag attrs children = Fixed_element { tag; attrs; children }
  let part i = Part i
  let fixed name value = Fixed (name, value)
  let part_attr i = Part_attr i
  let make shape = { shape; html = Empty; svg = Empty }
  let child n = Child n
  let attribute a = Attribute a
  let attribute_option = function Some a -> Attribute a | None -> No_attribute
  let instance template parts = Template { template; parts }
end

let hole_attr name f = Dynamic (name, f)
let on name handler = Handler (name, handler)

let each ?(equal = ( = )) ~key items render =
  Each { items; key; equal; render }

module Await = struct
  let make ~async ~loading ?(failed = fun _ -> Fragment []) ~children () =
    Await { async; loading; failed; render = children }
end
