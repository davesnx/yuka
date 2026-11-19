let () =
  print_endline (Yuka.Action.name Action_shared.Calc.double);
  print_endline (Yuka.Action.name Action_shared.Calc.Inner.shout);
  print_endline Action_shared.Calc.label
