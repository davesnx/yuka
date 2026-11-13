let read_attribute : string -> string =
  [%mel.raw {|function (name) { return document.documentElement.getAttribute(name) || "" }|}]

let write_attribute : string -> string -> string -> unit =
  [%mel.raw
    {|function (name, key, value) {
  if (value) document.documentElement.setAttribute(name, value);
  else document.documentElement.removeAttribute(name);
  try { if (value) localStorage.setItem(key, value); else localStorage.removeItem(key) } catch (error) {}
}|}]

let () =
  Demo_shared.Theme.read := read_attribute;
  Demo_shared.Theme.write := write_attribute;
  Yuka.render ~islands ~transitions:true ()
