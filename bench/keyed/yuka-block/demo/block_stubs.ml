module Web = Yuka__Web

type kind =
  | Text
  | Class
  | Attr of string
  | Click
  | Child of Obj.t Block.component
  | Each of Obj.t Block.component
  | Event of string
  | Child_at of Obj.t Block.component
  | Node
  | Rows

type template = { markup : string; walk : int array; targets : int array; kinds : kind array }

type block =
  | Empty
  | Block of template * Block.slot array
  | Instance of Obj.t Block.component * Obj.t
  | Many of block list

type 'a rows = { key : 'a -> string; items : 'a array; row : 'a -> block }

let runtime_kind = function
  | Text -> Block.Text
  | Class -> Block.Class
  | Attr name -> Block.Attr name
  | Click -> Block.Click
  | Child component -> Block.Child component
  | Each component -> Block.Each component
  | Event name -> Block.Attr ("data-stub-on" ^ name)
  | Child_at _ -> Block.Attr "data-stub-child-at"
  | Node -> Block.Attr "data-stub-node"
  | Rows -> Block.Attr "data-stub-rows"

let component ~markup ~walk ~targets ~kinds setup =
  Block.component ~markup ~walk ~targets ~kinds:(Array.map runtime_kind kinds) setup

let child_kind (component : 'p Block.component) = Child (Obj.magic component)
let child_at_kind (component : 'p Block.component) = Child_at (Obj.magic component)
let template ~markup ~walk ~targets ~kinds = { markup; walk; targets; kinds }
let block template slots = Block (template, slots)
let instance (component : 'p Block.component) (props : 'p) = Instance (Obj.magic component, Obj.repr props)
let many blocks = Many blocks
let empty = Empty

external on_event : (Web.event -> unit) -> Block.slot = "%identity"
external node : block -> Block.slot = "%identity"
external rows_slot : 'a rows -> Block.slot = "%identity"

let rows ~key items row = rows_slot { key; items; row }
let bool_attr value = Block.attr (if value then "true" else "false")
let int_text value = Block.text (Int.to_string value)
