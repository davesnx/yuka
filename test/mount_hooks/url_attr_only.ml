open Dom

let () =
  check_urls "Yuka.attr" (fun tag name value ->
      Yuka.runtime_instance (one_part tag) [| Yuka.runtime_attribute (Yuka.attr name value) |]);
  check_urls "Yuka.runtime_url_attr" (fun tag name value ->
      Yuka.runtime_instance (one_part tag) [| Yuka.runtime_attribute (Yuka.runtime_url_attr tag name value) |]);
  finish "URL check through attr"
