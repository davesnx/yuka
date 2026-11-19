let failures = ref 0

let check name expected got =
  if expected <> got then begin
    incr failures;
    Printf.printf "FAIL %s\n  expected: %s\n  got:      %s\n" name expected got
  end

let server view = Yuka.Private.render_html (fun () -> Yuka.Private.node (view ()))

let () =
  check "static expression" "<p>a<!---->hi<i></i></p>" (server Holes_cases.static_view);
  check "constant expressions" "<p title=\"hi!\"><b class=\"n2\">many</b><i>x</i><i>y</i></p>" (server Holes_cases.constant_view);
  check "explicit hole" "<p>a<!--[-->hi<!--]--><i></i></p>" (server Holes_cases.explicit_static_view);
  check "a module-level State read is a hole" "<p>a<!--[-->a<!--]--><i></i></p>" (server Holes_cases.dynamic_view);
  check "conditional read, not read" "<p>a<!--[-->none<!--]--><i></i></p>" (server (Holes_cases.conditional_view ~read:false));
  check "conditional read, read" "<p>a<!--[-->a<!--]--><i></i></p>" (server (Holes_cases.conditional_view ~read:true));
  check "a hole that returns a hole that reads" "<p>a<!--[--><!--[-->a<!--]--><!--]--><i></i></p>" (server Holes_cases.nested_view);
  check "a hole that returns an element with an attribute that reads" "<p><i title=\"a\">x</i></p>" (server Holes_cases.closure_attr_view);
  check "static list" "<ul><li>x</li><li>y</li></ul>" (server Holes_cases.static_list_view);
  check "a record prop of a component tag takes the type of make" "<p><i>a!</i></p>" (server Holes_cases.styled_view);
  if !failures > 0 then exit 1
