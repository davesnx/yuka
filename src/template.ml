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
    ops = [||];
  }

let rec checked_shape = function
  | Fixed_element { tag; attrs; children } ->
      let lt = String.lowercase_ascii tag in
      let attr = function
        | Fixed (n, v) ->
            if not (Url.valid_name n) then invalid_arg ("Yuka: refused attribute name " ^ n);
            Fixed (n, Url.check ~tag:lt ~log:(fun _ _ -> ()) (String.lowercase_ascii n) v)
        | a -> a
      in
      Fixed_element { tag; attrs = List.map attr attrs; children = List.map checked_shape children }
  | s -> s

let of_shape shape =
  let shape = checked_shape shape in
  let { Template_build.walk; kids; attrs; values } = Template_build.plan shape in
  make shape ~html:(Template_build.html shape) ~walk ~kids ~attrs ~values

let child n = Child n
let attribute a = Attribute a
let attribute_option = function Some a -> Attribute a | None -> No_attribute
let instance template parts = Template { template; parts }

let rec expand_shape parts = function
  | Fixed_text s -> Text s
  | Part i -> ( match parts.(i) with Child n -> n | Attribute _ | No_attribute -> Fragment [])
  | Fixed_element { tag; attrs; children } ->
      Element { tag; attrs = expand_attrs parts attrs; children = expand_list parts children }

and expand_list parts = function
  | [] -> []
  | n :: rest ->
      let n = expand_shape parts n in
      n :: expand_list parts rest

and expand_attrs parts = function
  | [] -> []
  | Fixed (name, value) :: rest -> Static (name, value) :: expand_attrs parts rest
  | Part_attr i :: rest -> (
      match parts.(i) with
      | Attribute a -> a :: expand_attrs parts rest
      | Child _ | No_attribute -> expand_attrs parts rest)

let expand template parts = expand_shape parts template.shape

let single_element = function Element _ | Template _ -> true | _ -> false
