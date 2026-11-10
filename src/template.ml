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

let make shape ~html ~walk ~kids ~attrs ~values =
  {
    shape;
    markup = html;
    plan = { walk; kids; attrs; values };
    in_html = Empty;
    in_svg = Empty;
  }

let of_shape shape =
  let { Template_build.walk; kids; attrs; values } = Template_build.plan shape in
  make shape ~html:(Template_build.html shape) ~walk ~kids ~attrs ~values

let child n = Child n
let attribute a = Attribute a
let attribute_option = function Some a -> Attribute a | None -> No_attribute
let instance template parts = Template { template; parts }

let expand template parts =
  let rec go = function
    | Fixed_text s -> Text s
    | Part i -> (
        match parts.(i) with Child n -> n | Attribute _ | No_attribute -> Fragment [])
    | Fixed_element { tag; attrs; children } ->
        Element
          {
            tag;
            attrs = go_attrs attrs;
            children = go_list children;
          }
  and go_list = function [] -> [] | n :: rest -> let n = go n in n :: go_list rest
  and go_attrs = function
    | [] -> []
    | Fixed (name, value) :: rest -> Static (name, value) :: go_attrs rest
    | Part_attr i :: rest -> (
        match parts.(i) with
        | Attribute a -> a :: go_attrs rest
        | Child _ | No_attribute -> go_attrs rest)
  in
  go template.shape

let single_element = function Element _ | Template _ -> true | _ -> false
