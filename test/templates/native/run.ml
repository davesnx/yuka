open Yuka

let failures = ref 0

let check name expected got =
  if expected <> got then begin
    incr failures;
    Printf.printf "FAIL %s\n  expected: %s\n  got:      %s\n" name expected got
  end

let plan_string (walk, kids, attrs, values) =
  let ints a = String.concat ";" (Array.to_list (Array.map string_of_int a)) in
  Printf.sprintf "walk [%s] kids [%s] attrs [%s] values [%s]" (ints walk) (ints kids)
    (ints attrs)
    (String.concat ";"
       (Array.to_list (Array.map (fun (i, v) -> Printf.sprintf "%d,%S" i v) values)))

let without_parts parts =
  Array.map
    (function
      | Private.Child _ -> Private.Child (Private.Fragment [])
      | Private.Attribute _ | Private.No_attribute -> Private.No_attribute)
    parts

let () =
  List.iter
    (fun (name, tree) ->
      match Private.node (tree ()) with
      | Private.Template { template; parts } ->
          if List.mem name Template_cases.parser_changes then
            check (name ^ ": lowered by the ppx") "lowered" "a template";
          check (name ^ ": ppx html is the server html of the tree without parts")
            (Private.to_html (Private.expand template (without_parts parts)))
            (Private.template_html template);
          let again = Private.recompile template in
          check (name ^ ": ppx html is the run-time html")
            (Private.template_html again) (Private.template_html template);
          check (name ^ ": ppx paths are the run-time paths")
            (plan_string (Private.template_plan again))
            (plan_string (Private.template_plan template))
      | _ when List.mem name Template_cases.parser_changes -> ()
      | _ -> check name "a template" "not a template")
    Template_cases.cases;
  check "escaping: server html"
    {|<p title="a &quot;q&quot; &amp; &lt;b> 'x'">x &lt; y &amp; z &gt; w "q" 'a'</p>|}
    (Private.to_html (Private.node ((List.assoc "escaping" Template_cases.cases) ())));
  if !failures > 0 then exit 1 else print_endline "templates: ok"
