type t = { key : string; name : string; choices : (string * string) list; value : string Yuka.State.t }

let attribute key = "data-" ^ key
let storage_key key = "yuka-demo-" ^ key
let theme = { key = "theme"; name = "Theme"; choices = List.map (fun theme -> (Theme.slug theme, Theme.label theme)) Theme.all; value = Theme.chosen }

let stored =
  [
    { key = "font-size"; name = "Font size"; choices = [ ("small", "Small"); ("", "Default"); ("large", "Large") ]; value = Yuka.State.make "" };
    { key = "density"; name = "Display density"; choices = [ ("", "Comfortable"); ("compact", "Compact") ]; value = Yuka.State.make "" };
    { key = "issue-ids"; name = "Issue IDs in lists"; choices = [ ("", "Show"); ("hidden", "Hide") ]; value = Yuka.State.make "" };
    { key = "motion"; name = "Motion"; choices = [ ("", "Full"); ("reduced", "Reduced") ]; value = Yuka.State.make "" };
  ]

let all = theme :: stored
let current preference = !Theme.read (attribute preference.key)
let apply preference value =
  !Theme.write (attribute preference.key) (storage_key preference.key) value;
  Yuka.State.set preference.value value
