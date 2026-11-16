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
    (List.map entry_field_name [ `Title; `Count; `Level ]);
  Alcotest.(check string) "Form.name" "tags" (Yuka.Form.name entry_form `Tags)

let render ?form () =
  let session = Yuka.Private.session ~streaming:false ~islands_only:false in
  Option.iter (Yuka.Private.set_form session) form;
  Yuka.Private.print session (fun () -> Yuka.Private.node (Forms_shared.Invalid.view ()))

let attribute_values html name =
  let prefix = " " ^ name ^ "=\"" in
  let n = String.length prefix in
  let rec go i acc =
    if i + n > String.length html then List.rev acc
    else if String.sub html i n = prefix then
      let stop = String.index_from html (i + n) '"' in
      go stop (String.sub html (i + n) (stop - i - n) :: acc)
    else go (i + 1) acc
  in
  go 0 []

let tags html =
  let rec go i acc =
    match String.index_from_opt html i '<' with
    | None -> List.rev acc
    | Some j ->
        let stop = String.index_from html j '>' in
        go stop (String.sub html j (stop - j + 1) :: acc)
  in
  List.filter
    (fun tag -> List.exists (fun p -> String.starts_with ~prefix:p tag) [ "<input"; "<select"; "<textarea"; "<b " ])
    (go 0 [])

let invalid_fields () =
  let html = render ~form:Forms_shared.Invalid.sent () in
  Alcotest.(check (list string))
    "fields and errors"
    [
      {|<input type="hidden" name="_yuka_action" value="save_entry">|};
      {|<input type="hidden" name="_yuka_key" value="k">|};
      {|<input type="hidden" name="ratio" value="1" aria-invalid="true" aria-describedby="save_entry-k-ratio-error">|};
      {|<input name="title" aria-describedby="hint save_entry-k-title-error" aria-invalid="true" autofocus="">|};
      {|<b id="save_entry-k-title-error">|};
      {|<input name="count" value="x3" aria-invalid="true" aria-describedby="save_entry-k-count-error">|};
      {|<b id="save_entry-k-count-error">|};
      {|<select name="level" aria-invalid="true" aria-describedby="save_entry-k-level-error">|};
      {|<b id="save_entry-k-level-error">|};
      {|<textarea name="tags">|};
      {|<input name="urgent" type="checkbox" aria-invalid="true" aria-describedby="save_entry-k-urgent-error">|};
    ]
    (tags html)

let valid_fields () =
  let clean = render () in
  Alcotest.(check (list string)) "no aria-invalid" [] (attribute_values clean "aria-invalid");
  Alcotest.(check (list string)) "only the author's describedby" [ "hint" ] (attribute_values clean "aria-describedby");
  Alcotest.(check (list string)) "no autofocus" [] (attribute_values clean "autofocus");
  let action, _, values, errors = Forms_shared.Invalid.sent in
  let other = render ~form:(action, "other", values, errors) () in
  Alcotest.(check (list string)) "another key: no aria-invalid" [] (attribute_values other "aria-invalid")

let () =
  Alcotest.run "forms"
    [
      ( "deriving form",
        [
          Alcotest.test_case "decode" `Quick decode;
          Alcotest.test_case "round trip" `Quick round_trip;
          Alcotest.test_case "names" `Quick names;
        ] );
      ( "errors",
        [
          Alcotest.test_case "a failed post marks its fields" `Quick invalid_fields;
          Alcotest.test_case "no error, no mark" `Quick valid_fields;
        ] );
    ]
