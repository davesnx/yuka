open Dom

let () =
  let c, dispose =
    mount (fun () ->
        Yuka.template_instance (one_part "animate") [| Yuka.template_attribute (Yuka.attr_unchecked "class" "x") |])
  in
  check "a non-URL attribute is set with no URL check linked" {|<animate class="x"></animate>|} (html c);
  dispose ();
  let reached name make =
    match
      Yuka.Private.render (as_container (container ())) (fun () ->
          Yuka.template_instance (one_part "animate") [| Yuka.template_attribute (make ()) |])
    with
    | dispose ->
        dispose ();
        incr failures;
        print_endline ("FAIL " ^ name ^ ": the URL attribute was set with no URL check")
    | exception Failure m ->
        check name
          "Yuka: no URL check for to of animate: the attribute was made without Yuka.attr, Yuka.hole_attr or Yuka.lower"
          m
  in
  reached "a static URL attribute with no installer raises" (fun () -> Yuka.attr_unchecked "to" "javascript:alert(1)");
  reached "a dynamic URL attribute with no installer raises" (fun () ->
      Yuka.hole_attr_unchecked "to" (fun () -> Some "javascript:alert(1)"));
  finish "URL check default"
