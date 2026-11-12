open Dom

let () =
  check_urls "Yuka.attr" (fun tag name value ->
      Yuka.template_instance (one_part tag) [| Yuka.template_attribute (Yuka.attr name value) |]);
  check_urls "Yuka.url_attr" (fun tag name value ->
      Yuka.template_instance (one_part tag) [| Yuka.template_attribute (Yuka.url_attr tag name value) |]);
  finish "URL check through attr"
