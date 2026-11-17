open Yuka

external random : unit -> float = "random" [@@mel.scope "Math"]
external round : float -> float = "round" [@@mel.scope "Math"]

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

let button_props ~id ~label ~action () = (id, label, action)

let button =
  Block.component
    ~markup:{|<div class="col-sm-6 smallpad"><button class="btn btn-primary btn-block" type="button"> </button></div>|}
    ~walk:[| 0; 0; 2; 0 |] ~targets:[| 1; 2; 1 |]
    ~kinds:[| Block.Attr "id"; Block.Text; Block.Click |]
    (fun _ ->
      let view ~id ~label ~action () = [| Block.attr id; Block.text label; Block.on_click (fun _ -> action ()) |] in
      fun (id, label, action) -> view ~id ~label ~action ())

let row_markup =
  {|<tr><td class="col-md-1"> </td><td class="col-md-4"><a> </a></td><td class="col-md-1"><a><span class="glyphicon glyphicon-remove" aria-hidden="true"></span></a></td><td class="col-md-6"></td></tr>|}

let row_walk = [| 0; 0; 2; 0; 3; 1; 6; 0; 8; 0; 7; 1; 12; 0 |]
let row_targets = [| 0; 2; 4; 5; 7 |]
let row_kinds = [| Block.Class; Block.Text; Block.Click; Block.Text; Block.Click |]

let app_markup =
  {|<div class="container"><div class="jumbotron"><div class="row"><div class="col-md-6"><h1>Yuka block</h1></div><div class="col-md-6"><div class="row"></div></div></div></div><table class="table table-hover table-striped test-data"><tbody></tbody></table><span class="preloadicon glyphicon glyphicon-remove" aria-hidden="true"></span></div>|}

let app_walk = [| 0; 0; 2; 0; 4; 0; 7; 1; 8; 0; 3; 1; 12; 0 |]
let app_targets = [| 5; 5; 5; 5; 5; 5; 7 |]

let app_kinds row =
  [|
    Block.child_kind button;
    Block.child_kind button;
    Block.child_kind button;
    Block.child_kind button;
    Block.child_kind button;
    Block.child_kind button;
    Block.each_kind row;
  |]

let key (item : item) = string_of_int item.id
