module Web = Yuka__Web
module Scheduler = Yuka__Scheduler
module Base = Yuka__Base

type slot

external text : string -> slot = "%identity"
external class_name : string -> slot = "%identity"
external attr : string -> slot = "%identity"
external on_click : (Web.event -> unit) -> slot = "%identity"
external insert : Web.node -> Web.node -> Web.node Js.null -> unit = "insertBefore" [@@mel.send]
external set_class : Web.node -> string -> unit = "className" [@@mel.set]
external set_click : Web.node -> (Web.event -> unit) -> unit = "__click" [@@mel.set]
external click_of : Web.node -> (Web.event -> unit) Js.undefined = "__click" [@@mel.get]
external parent_of : Web.node -> Web.node Js.null = "parentNode" [@@mel.get]
external alloc : int -> 'a array = "Array" [@@mel.new]
let get = Array.unsafe_get
let set = Array.unsafe_set
external fill : 'a array -> 'a -> 'a array = "fill" [@@mel.send]

(* Each kind of a component's template fixes the type of the slot at its
   index, as the ppx would generate both from one JSX tree; the casts in
   [patch] read the slot back at that type. *)
type kind =
  | Text
  | Class
  | Attr of string
  | Click
  | Child of Obj.t component
  | Each of Obj.t component

and 'p component = {
  markup : string;
  walk : int array;
  targets : int array;
  kinds : kind array;
  setup : 'p -> 'p -> slot array;
  mutable template : Web.node Js.null;
}

type ('a, 'p) each = { items : 'a array; key : 'a -> string; props : 'a -> 'p }

type instance = {
  component : Obj.t component;
  mutable props : Obj.t;
  view : Obj.t -> slot array;
  owner : Scheduler.owner;
  root : Web.node;
  nodes : Web.node array;
  mutable slots : slot array;
  mounted : mounted array;
  node : Scheduler.node;
}

and mounted = Nothing | One of instance | Rows of rows
and rows = { mutable keys : string array; mutable entries : instance array }

let component ~markup ~walk ~targets ~kinds setup = { markup; walk; targets; kinds; setup; template = Js.null }

let child_kind (component : 'p component) = Child (Obj.magic component)
let each_kind (component : 'p component) = Each (Obj.magic component)
let child (props : 'p) : slot = Obj.magic props
let each ~key items props : slot = Obj.magic { items; key; props }
let unset : slot = Obj.magic (ref ())

let template_of doc component =
  match Js.Null.toOption component.template with
  | Some root -> root
  | None ->
      let holder = Web.create_element doc "template" in
      Web.set_inner_html holder component.markup;
      let root =
        match Web.first_child (Web.content holder) with
        | Some root -> root
        | None -> invalid_arg ("Block: empty template " ^ component.markup)
      in
      component.template <- Js.Null.return root;
      root

(* Melange compiles a tuple to a JS array, and the ppx gives every props
   value a tuple of at least two parts, so props read as an array. *)
let same (old : Obj.t) (next : Obj.t) =
  let old : Obj.t array = Obj.magic old and next : Obj.t array = Obj.magic next in
  let at = ref (Array.length next - 1) in
  while !at >= 0 && get old !at == get next !at do
    decr at
  done;
  !at < 0

let setup owner (component : Obj.t component) props =
  let listener = Scheduler.listener () and current = Base.current_owner () in
  let outer_listener = !listener and outer_owner = !current in
  listener := None;
  current := Some owner;
  match component.setup props with
  | view ->
      listener := outer_listener;
      current := outer_owner;
      view
  | exception error ->
      listener := outer_listener;
      current := outer_owner;
      raise error

let lis order =
  let length = Array.length order in
  let tails = fill (alloc length) 0 and prev = fill (alloc length) (-1) in
  let size = ref 0 in
  for i = 0 to length - 1 do
    if get order i >= 0 then begin
      let low = ref 0 and high = ref !size in
      while !low < !high do
        let mid = (!low + !high) / 2 in
        if get order (get tails mid) < get order i then low := mid + 1 else high := mid
      done;
      if !low > 0 then set prev i (get tails (!low - 1));
      set tails !low i;
      if !low = !size then incr size
    end
  done;
  let keep = fill (alloc length) false in
  let at = ref (if !size > 0 then get tails (!size - 1) else -1) in
  while !at >= 0 do
    set keep !at true;
    at := get prev !at
  done;
  keep

let rec create doc (component : Obj.t component) props parent anchor (above : Scheduler.owner) =
  let owner = { Scheduler.last = None; gen = 0; catch = above.catch; env = above.env; parent = Some above } in
  let view = setup owner component props in
  let root = Web.clone_node (template_of doc component) true in
  let walked = Web.walk root component.walk in
  let count = Array.length component.kinds in
  let instance =
    {
      component;
      props;
      view;
      owner;
      root;
      nodes = Array.map (fun i -> get walked i) component.targets;
      slots = fill (alloc count) unset;
      mounted = fill (alloc count) Nothing;
      node = Scheduler.make (Some (Scheduler.mine Scheduler.queue)) Scheduler.never;
    }
  in
  instance.node.fn <-
    (fun () ->
      render doc instance;
      false);
  Scheduler.run instance.node;
  insert parent root anchor;
  instance

and render doc instance =
  let next = instance.view instance.props and old = instance.slots in
  for i = 0 to Array.length next - 1 do
    let value = get next i in
    if value != get old i then patch doc instance i value
  done;
  instance.slots <- next

and patch doc instance i value =
  let node = get instance.nodes i in
  match get instance.component.kinds i with
  | Text -> Web.set_data node (Obj.magic value)
  | Class -> set_class node (Obj.magic value)
  | Attr name -> Web.set_attribute node name (Obj.magic value)
  | Click -> set_click node (Obj.magic value)
  | Child component -> (
      match get instance.mounted i with
      | One child -> update child (Obj.magic value)
      | Nothing | Rows _ ->
          set instance.mounted i (One (create doc component (Obj.magic value) node Js.null instance.owner)))
  | Each component -> (
      match get instance.mounted i with
      | Rows rows -> reconcile doc component node rows (Obj.magic value) instance.owner
      | Nothing | One _ ->
          let rows = { keys = [||]; entries = [||] } in
          set instance.mounted i (Rows rows);
          reconcile doc component node rows (Obj.magic value) instance.owner)

and update instance props =
  if not (same instance.props props) then begin
    instance.props <- props;
    Scheduler.run instance.node
  end

and dispose instance =
  Scheduler.dispose instance.node;
  Base.dispose_owner instance.owner;
  Array.iter
    (function
      | One child -> dispose child
      | Rows rows -> Array.iter dispose rows.entries
      | Nothing -> ())
    instance.mounted

and reconcile doc component parent rows (each : (Obj.t, Obj.t) each) owner =
  let items = each.items in
  let length = Array.length items in
  let keys = Array.map each.key items in
  let old_keys = rows.keys and old_entries = rows.entries in
  let old_length = Array.length old_entries in
  let entries = alloc length in
  let fresh j anchor = set entries j (create doc component (each.props (get items j)) parent anchor owner) in
  let keep j old =
    let entry = get old_entries old in
    update entry (each.props (get items j));
    set entries j entry
  in
  let start = ref 0 in
  while !start < length && !start < old_length && get keys !start = get old_keys !start do
    keep !start !start;
    incr start
  done;
  let last = ref (length - 1) and old_last = ref (old_length - 1) in
  while !last >= !start && !old_last >= !start && get keys !last = get old_keys !old_last do
    keep !last !old_last;
    decr last;
    decr old_last
  done;
  let after = if !last + 1 < length then Js.Null.return (get entries (!last + 1)).root else Js.null in
  if !start > !old_last then
    for j = !start to !last do
      fresh j after
    done
  else if !start > !last then
    for old = !start to !old_last do
      dispose (get old_entries old);
      Web.remove (get old_entries old).root
    done
  else begin
    let at = Web.table () in
    for old = !start to !old_last do
      Web.table_set at (get old_keys old) old
    done;
    let order = fill (alloc (!last - !start + 1)) (-1) and reused = ref 0 in
    for j = !start to !last do
      match Web.table_get at (get keys j) with
      | Some old ->
          set order (j - !start) old;
          Web.table_delete at (get keys j);
          incr reused
      | None -> ()
    done;
    let anchor = ref after in
    if !reused = 0 && !start = 0 && !old_last = old_length - 1 then begin
      Array.iter dispose old_entries;
      Web.clear parent "";
      anchor := Js.null
    end
    else
      Array.iter
        (fun old ->
          let entry = get old_entries old in
          dispose entry;
          Web.remove entry.root)
        (Web.table_values at);
    let stay = lis order in
    for j = !last downto !start do
      let old = get order (j - !start) in
      if old < 0 then fresh j !anchor
      else begin
        keep j old;
        if not (get stay (j - !start)) then insert parent (get entries j).root !anchor
      end;
      anchor := Js.Null.return (get entries j).root
    done
  end;
  rows.keys <- keys;
  rows.entries <- entries

let rec dispatch event node =
  let handler = click_of node in
  if handler != Js.undefined then Scheduler.batch (fun () -> (Js.Undefined.getExn handler) event)
  else
    let parent = parent_of node in
    if parent != Js.null then dispatch event (Js.Null.getExn parent)

let mount container (component : (unit * unit) component) =
  let doc = Web.owner_document container in
  Web.add_listener doc "click" (fun event -> dispatch event (Web.target event));
  Web.clear container "";
  ignore (Scheduler.batch (fun () -> create doc (Obj.magic component) (Obj.repr ((), ())) container Js.null (Base.new_owner ())))
