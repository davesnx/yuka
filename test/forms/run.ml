open Forms_shared.Entry

let decode () =
  List.iter2
    (fun (name, values) expected -> Alcotest.(check string) name expected (show values))
    cases expected

let round_trip () =
  let e = { title = "t"; count = 7; ratio = Some 1.5; urgent = true; level = Level.Low; tags = [ "a"; "b" ] } in
  let values = Yuka.Form.encode entry_form e in
  Alcotest.(check (list (pair string string)))
    "encoded"
    [ ("title", "t"); ("count", "7"); ("ratio", "1.5"); ("urgent", "on"); ("level", "low"); ("tags", "a"); ("tags", "b") ]
    values;
  Alcotest.(check bool) "decodes back" true (Yuka.Form.decode entry_form values = Ok e)

let names () =
  Alcotest.(check (list string)) "field names" [ "title"; "count"; "level" ]
    (List.map entry_field_name [ Title; Count; Level ]);
  Alcotest.(check string) "Form.name" "tags" (Yuka.Form.name entry_form Tags)

let () =
  Alcotest.run "forms"
    [
      ( "deriving form",
        [
          Alcotest.test_case "decode" `Quick decode;
          Alcotest.test_case "round trip" `Quick round_trip;
          Alcotest.test_case "names" `Quick names;
        ] );
    ]
