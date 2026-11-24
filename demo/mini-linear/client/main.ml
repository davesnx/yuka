open Web

let root = DOM.(Document.documentElement document)
let read_attribute name = Option.value (DOM.Element.getAttribute name root) ~default:""

let write_attribute name key value =
  if value <> "" then DOM.Element.setAttribute ~name ~value root else DOM.Element.removeAttribute name root;
  try
    if value <> "" then Storage.setItem ~key ~value Storage.localStorage
    else Storage.removeItem key Storage.localStorage
  with _ -> ()

let () =
  Demo_shared.Theme.read := read_attribute;
  Demo_shared.Theme.write := write_attribute;
  Yuka.render ~islands ~transitions:true ()
