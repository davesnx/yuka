type element

external root : element = "documentElement" [@@mel.scope "document"]
external get_attribute : element -> string -> string Js.null = "getAttribute" [@@mel.send]
external set_attribute : element -> string -> string -> unit = "setAttribute" [@@mel.send]
external remove_attribute : element -> string -> unit = "removeAttribute" [@@mel.send]
external store : string -> string -> unit = "setItem" [@@mel.scope "localStorage"]
external unstore : string -> unit = "removeItem" [@@mel.scope "localStorage"]

let read_attribute name = match Js.Null.toOption (get_attribute root name) with Some v -> v | None -> ""

let write_attribute name key value =
  if value <> "" then set_attribute root name value else remove_attribute root name;
  try if value <> "" then store key value else unstore key with _ -> ()

let () =
  Demo_shared.Theme.read := read_attribute;
  Demo_shared.Theme.write := write_attribute;
  Yuka.render ~islands ~transitions:true ()
