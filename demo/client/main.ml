let read_theme : unit -> string =
  [%mel.raw {|function () { return document.documentElement.getAttribute("data-theme") || "dark" }|}]

let write_theme : string -> unit =
  [%mel.raw
    {|function (theme) {
  document.documentElement.setAttribute("data-theme", theme);
  try { localStorage.setItem("yuka-demo-theme", theme) } catch (error) {}
}|}]

let () =
  Demo_shared.Theme.read := read_theme;
  Demo_shared.Theme.write := write_theme;
  Yuka.render ~islands ~transitions:true ()
