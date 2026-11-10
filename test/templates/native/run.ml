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
      | Internal.Child _ -> Internal.Child (Internal.Fragment [])
      | Internal.Attribute _ | Internal.No_attribute -> Internal.No_attribute)
    parts

let () =
  List.iter
    (fun (name, tree) ->
      match Internal.node (tree ()) with
      | Internal.Template { template; parts } ->
          check (name ^ ": ppx html is the server html of the tree without parts")
            (Internal.to_html (Internal.expand template (without_parts parts)))
            (Internal.template_html template);
          let again = Internal.recompile template in
          check (name ^ ": ppx html is the run-time html")
            (Internal.template_html again) (Internal.template_html template);
          check (name ^ ": ppx paths are the run-time paths")
            (plan_string (Internal.template_plan again))
            (plan_string (Internal.template_plan template))
      | _ -> check name "a template" "not a template")
    Template_cases.cases;
  check "escaping: server html"
    {|<p title="a &quot;q&quot; &amp; &lt;b> 'x'">x &lt; y &amp; z &gt; w "q" 'a'</p>|}
    (Internal.to_html (Internal.node ((List.assoc "escaping" Template_cases.cases) ())));
  if !failures > 0 then exit 1 else print_endline "templates: ok"
