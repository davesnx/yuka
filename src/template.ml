open Types

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
