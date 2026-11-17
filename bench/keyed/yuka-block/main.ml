open Yuka

external random : unit -> float = "random" [@@mel.scope "Math"]
external round : float -> float = "round" [@@mel.scope "Math"]
external get_element_by_id : string -> Yuka__Web.node = "getElementById" [@@mel.scope "document"]

let adjectives = [| "pretty"; "large"; "big"; "small"; "tall"; "short"; "long"; "handsome"; "plain"; "quaint"; "clean"; "elegant"; "easy"; "angry"; "crazy"; "helpful"; "mushy"; "odd"; "unsightly"; "adorable"; "important"; "inexpensive"; "cheap"; "expensive"; "fancy" |]
let colors = [| "red"; "yellow"; "blue"; "green"; "pink"; "brown"; "purple"; "brown"; "white"; "black"; "orange" |]
let nouns = [| "table"; "chair"; "house"; "bbq"; "desk"; "car"; "pony"; "cookie"; "sandwich"; "burger"; "pizza"; "mouse"; "keyboard" |]

let pick words =
  words.(int_of_float (round (random () *. 1000.)) mod Array.length words)

type item = { id : int; label : string }

let next_id = ref 1

let build count =
  Array.init count (fun _ ->
      let id = !next_id in
      incr next_id;
      { id; label = pick adjectives ^ " " ^ pick colors ^ " " ^ pick nouns })

let rows = State.make [||]
let selected = State.make 0
let run () = State.set rows (build 1_000)
let run_lots () = State.set rows (build 10_000)
let add () = State.set rows (Js.Array.concat ~other:(build 1_000) (State.peek rows))

let update () =
  State.set rows
    (Array.mapi
       (fun i item -> if i mod 10 = 0 then { item with label = item.label ^ " !!!" } else item)
       (State.peek rows))

let clear () = State.set rows [||]

let swap_rows () =
  let items = Js.Array.copy (State.peek rows) in
  if Array.length items > 998 then begin
    let item = items.(1) in
    items.(1) <- items.(998);
    items.(998) <- item;
    State.set rows items
  end

let remove item = State.set rows (Js.Array.filter ~f:(fun other -> other != item) (State.peek rows))

type button_props = { id : string; label : string; action : unit -> unit }

let button =
  Block.component
    ~markup:{|<div class="col-sm-6 smallpad"><button class="btn btn-primary btn-block" type="button"> </button></div>|}
    ~walk:[| 0; 0; 2; 0 |] ~targets:[| 1; 2; 1 |]
    ~kinds:[| Block.Attr "id"; Block.Text; Block.Click |]
    ~same:(fun a b -> a.id == b.id && a.label == b.label && a.action == b.action)
    (fun { id; label; action } ->
      [| Block.attr id; Block.text label; Block.on_click (fun _ -> action ()) |])

type row_props = { item : item; selected : bool }

let row =
  Block.component
    ~markup:
      {|<tr><td class="col-md-1"> </td><td class="col-md-4"><a> </a></td><td class="col-md-1"><a><span class="glyphicon glyphicon-remove" aria-hidden="true"></span></a></td><td class="col-md-6"></td></tr>|}
    ~walk:[| 0; 0; 2; 0; 3; 1; 6; 0; 8; 0; 7; 1; 12; 0 |] ~targets:[| 0; 2; 4; 5; 7 |]
    ~kinds:[| Block.Class; Block.Text; Block.Click; Block.Text; Block.Click |]
    ~same:(fun a b -> a.item == b.item && a.selected == b.selected)
    (fun { item; selected = is_selected } ->
      [|
        Block.class_name (if is_selected then "danger" else "");
        Block.text (string_of_int item.id);
        Block.on_click (fun _ -> State.set selected item.id);
        Block.text item.label;
        Block.on_click (fun _ -> remove item);
      |])

let app =
  Block.component
    ~markup:
      {|<div class="container"><div class="jumbotron"><div class="row"><div class="col-md-6"><h1>Yuka block</h1></div><div class="col-md-6"><div class="row"></div></div></div></div><table class="table table-hover table-striped test-data"><tbody></tbody></table><span class="preloadicon glyphicon glyphicon-remove" aria-hidden="true"></span></div>|}
    ~walk:[| 0; 0; 2; 0; 4; 0; 7; 1; 8; 0; 3; 1; 12; 0 |] ~targets:[| 5; 5; 5; 5; 5; 5; 7 |]
    ~kinds:
      [|
        Block.child_kind button;
        Block.child_kind button;
        Block.child_kind button;
        Block.child_kind button;
        Block.child_kind button;
        Block.child_kind button;
        Block.each_kind row;
      |]
    ~same:(fun () () -> true)
    (fun () ->
      let selected_id = State.get selected in
      [|
        Block.child { id = "run"; label = "Create 1,000 rows"; action = run };
        Block.child { id = "runlots"; label = "Create 10,000 rows"; action = run_lots };
        Block.child { id = "add"; label = "Append 1,000 rows"; action = add };
        Block.child { id = "update"; label = "Update every 10th row"; action = update };
        Block.child { id = "clear"; label = "Clear"; action = clear };
        Block.child { id = "swaprows"; label = "Swap Rows"; action = swap_rows };
        Block.each ~key:(fun (item : item) -> string_of_int item.id) (State.get rows) (fun (item : item) ->
            { item; selected = item.id = selected_id });
      |])

let () = Block.mount (get_element_by_id "main") app
