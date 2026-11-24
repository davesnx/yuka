let on_visible : string -> (unit -> unit) -> unit -> unit =
  [%mel.raw
    {|function (id, callback) {
  var element = document.getElementById(id);
  if (!element || !("IntersectionObserver" in window)) return function () {};
  var observer = new IntersectionObserver(function (entries) {
    if (entries.some(function (entry) { return entry.isIntersecting })) { observer.disconnect(); callback() }
  });
  observer.observe(element);
  return function () { observer.disconnect() };
}|}]

let () =
  Infinite_shared.Browser.on_visible := on_visible;
  Yuka.render ~islands ()
