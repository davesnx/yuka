let call action input =
  match Yuka.Async.status (Yuka.Action.call action input) with
  | Yuka.Async.Done (Ok v) -> v
  | Done (Error e) -> "error: " ^ Yuka.Status.error_to_string e
  | Pending -> "pending"
  | Failed m -> "failed: " ^ m

let () =
  print_endline (Yuka.Action.name Action_shared.Calc.double);
  print_endline (Yuka.Action.name Action_shared.Calc.Inner.shout);
  print_endline (call Action_shared.Calc.double 21);
  print_endline (call Action_shared.Calc.Inner.shout "hi");
  print_endline Action_shared.Calc.label
