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

let rec same_tree shape n =
  match shape with
  | Fixed_element { tag; attrs; children } ->
      Web.node_type n = 1
      && Web.local_name n = tag
      && (Template_build.void_or_value tag attrs || same_children children (Web.first_child n))
  | Fixed_text _ | Part _ -> false

and same_children children cur =
  let rec go after_text cur = function
    | [] -> cur = None
    | (Part _ | Fixed_text "") :: rest -> go after_text cur rest
    | Fixed_text t :: rest -> (
        let cur =
          if not after_text then cur
          else
            match cur with
            | Some c when Web.node_type c = 8 -> Web.next_sibling c
            | _ -> None
        in
        match cur with
        | Some c -> Web.node_type c = 3 && Web.data c = t && go true (Web.next_sibling c) rest
        | None -> false)
    | (Fixed_element _ as e) :: rest -> (
        match cur with
        | Some c -> same_tree e c && go false (Web.next_sibling c) rest
        | None -> false)
  in
  go false cur children

let check : (t -> Web.node -> bool) ref = ref (fun _ _ -> true)

let expander : (t -> Types.part array -> node) ref =
  ref (fun t _ ->
      failwith ("Yuka: the HTML parser would change this template here; only a hydrating app builds it node by node: " ^ t.markup))

let coded code ~html ~walk ~kids ~attrs ~values ~clones =
  {
    shape = None;
    code;
    fixed_root = true;
    clones;
    markup = html;
    plan = { walk; kids; attrs; values };
    in_html = Empty;
    in_svg = Empty;
    ops = [||];
  }

let decode code =
  let n = String.length code in
  let i = ref 0 and parts = ref 0 in
  let str () =
    let b = Buffer.create 16 in
    while !i < n && (String.unsafe_get code !i >= '\x10' || String.unsafe_get code !i = '\x0f') do
      let c = String.unsafe_get code !i in
      if c = '\x0f' then begin
        Buffer.add_char b (Char.chr (Char.code (String.unsafe_get code (!i + 1)) - 0x40));
        i := !i + 2
      end
      else begin
        Buffer.add_char b c;
        incr i
      end
    done;
    Buffer.contents b
  in
  let next_part () =
    let p = !parts in
    incr parts;
    p
  in
  let rec node () =
    let c = String.unsafe_get code !i in
    incr i;
    match c with
    | '\x08' -> Fixed_text (str ())
    | '\x07' -> Part (next_part ())
    | _ ->
        let tag = str () in
        let rec attrs acc =
          let c = String.unsafe_get code !i in
          incr i;
          match c with
          | '\x03' ->
              let name = str () in
              incr i;
              let value = str () in
              attrs (Fixed (name, value) :: acc)
          | '\x05' -> attrs (Part_attr (next_part ()) :: acc)
          | _ -> List.rev acc
        in
        let attrs = attrs [] in
        let rec children acc =
          if String.unsafe_get code !i = '\x06' then begin
            incr i;
            List.rev acc
          end
          else children (node () :: acc)
        in
        Fixed_element { tag; attrs; children = children [] }
  in
  node ()

let shape t =
  match t.shape with
  | Some s -> s
  | None ->
      let s = decode t.code in
      t.shape <- Some s;
      s

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

let expand template parts = expand_shape parts (shape template)
let same_shape t n = same_tree (shape t) n

let make shape ~html ~walk ~kids ~attrs ~values =
  check := (fun t n -> same_shape t n);
  expander := (fun t p -> expand t p);
  {
    shape = Some shape;
    code = "";
    fixed_root = (match shape with Fixed_element _ -> true | Fixed_text _ | Part _ -> false);
    clones = 3;
    markup = html;
    plan = { walk; kids; attrs; values };
    in_html = Empty;
    in_svg = Empty;
    ops = [||];
  }

let rec checked_shape = function
  | Fixed_element { tag; attrs; children } ->
      if not (Url.valid_tag tag) then invalid_arg ("Yuka: refused tag name " ^ tag);
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

let child n = Child (Kind.to_node n)
let attribute a = Attribute a
let attribute_option = function Some a -> Attribute a | None -> No_attribute
let instance template parts = Kind.of_node (Template { template; parts })

let single_element = function Element _ | Template _ -> true | _ -> false
