type source = New_relic | Vercel | Figma | Reddit | Github [@@deriving codec]

type event = {
  id : int;
  time : int;
  source : source;
  author : string;
  title : string;
  description : string;
  project : string;
  team : string;
  assignee : string;
}
[@@deriving codec]

type theme = Light | Dark [@@deriving codec]
type settings = { theme : theme option; zone : string option }

let theme_cookie = "async-feed-theme"
let theme_of_string = function "light" -> Some Light | "dark" -> Some Dark | _ -> None
let theme_to_string = function Light -> "light" | Dark -> "dark"

type filter = { projects : string list; teams : string list; assignees : string list } [@@deriving codec]

let projects = [ "Checkout"; "Dashboard"; "Mobile app"; "Marketing site"; "Search"; "Billing" ]
let teams = [ "Platform"; "Growth"; "Design"; "Infra"; "Mobile" ]

let people =
  [ "Ana Ruiz"; "Ben Okafor"; "Chen Wei"; "Dana Levi"; "Eli Novak"; "Fatima Zahra"; "Gus Moreau"; "Hana Sato" ]

let matches filter event =
  let fits chosen value = chosen = [] || List.mem value chosen in
  fits filter.projects event.project && fits filter.teams event.team && fits filter.assignees event.assignee

let source_label = function
  | New_relic -> "New Relic"
  | Vercel -> "Vercel"
  | Figma -> "Figma"
  | Reddit -> "Reddit"
  | Github -> "GitHub"

let source_slug = function
  | New_relic -> "newrelic"
  | Vercel -> "vercel"
  | Figma -> "figma"
  | Reddit -> "reddit"
  | Github -> "github"
