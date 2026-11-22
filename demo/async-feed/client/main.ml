open Async_feed_shared

let zone : unit -> string = [%mel.raw {|function () { return window.asyncFeed ? window.asyncFeed.zone() : "UTC" }|}]
let set_zone : string -> unit = [%mel.raw {|function (zone) { if (window.asyncFeed) window.asyncFeed.setZone(zone) }|}]
let to_time : string -> int = [%mel.raw {|function (value) { return window.asyncFeed ? window.asyncFeed.toTime(value) : 0 }|}]
let theme : unit -> string = [%mel.raw {|function () { return window.asyncFeed ? window.asyncFeed.theme() : "light" }|}]
let set_theme : string -> unit = [%mel.raw {|function (theme) { if (window.asyncFeed) window.asyncFeed.setTheme(theme) }|}]

let () =
  Prefs.zone := zone;
  Prefs.set_zone := set_zone;
  Prefs.to_time := to_time;
  Prefs.theme := theme;
  Prefs.set_theme := set_theme;
  Yuka.render ~islands ~transitions:true ()
