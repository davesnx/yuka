open Yuka
open Store

external get_element_by_id : string -> Yuka__Web.node = "getElementById" [@@mel.scope "document"]

let row_props ~item ~selected () = (item, selected)

let row =
  Block.component ~markup:row_markup ~walk:row_walk ~targets:row_targets ~kinds:row_kinds (fun _ ->
      let view ~item ~selected:is_selected () =
        [|
          Block.class_name (if is_selected then "danger" else "");
          Block.text (string_of_int item.id);
          Block.on_click (fun _ -> State.set selected item.id);
          Block.text item.label;
          Block.on_click (fun _ -> remove item);
        |]
      in
      fun (item, is_selected) -> view ~item ~selected:is_selected ())

let app =
  Block.component ~markup:app_markup ~walk:app_walk ~targets:app_targets ~kinds:(app_kinds row) (fun ((), ()) ->
      let view () =
        let selected_id = State.get selected in
        [|
          Block.child (button_props ~id:"run" ~label:"Create 1,000 rows" ~action:run ());
          Block.child (button_props ~id:"runlots" ~label:"Create 10,000 rows" ~action:run_lots ());
          Block.child (button_props ~id:"add" ~label:"Append 1,000 rows" ~action:add ());
          Block.child (button_props ~id:"update" ~label:"Update every 10th row" ~action:update ());
          Block.child (button_props ~id:"clear" ~label:"Clear" ~action:clear ());
          Block.child (button_props ~id:"swaprows" ~label:"Swap Rows" ~action:swap_rows ());
          Block.each ~key (State.get rows) (fun (item : item) -> row_props ~item ~selected:(item.id = selected_id) ());
        |]
      in
      fun ((), ()) -> view ())

let () = Block.mount (get_element_by_id "main") app
