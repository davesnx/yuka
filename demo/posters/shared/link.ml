open Pattern

let route ?defaults (s : settings) =
  let keep value default =
    match defaults with Some (d : settings) when value = default d -> None | _ -> Some value
  in
  let base = Option.map (fun d -> start ~defaults:d (kind s.art)) defaults in
  let field get =
    match (get s.art, Option.bind base get) with Some value, Some default when value = default -> None | value, _ -> value
  in
  let color value default = Option.map (fun c -> String.sub c 1 6) (keep value default) in
  Routes.Home
    {
      kind = keep (kind s.art) (fun d -> kind d.art);
      seed = keep s.layout.seed (fun d -> d.layout.seed);
      padding = keep s.layout.padding (fun d -> d.layout.padding);
      lines = field (function Lines a -> Some a.lines | _ -> None);
      amplitude = field (function Lines a -> Some a.amplitude | _ -> None);
      waves = field (function Lines a -> Some a.waves | _ -> None);
      stroke = field (function Lines a -> Some a.stroke | _ -> None);
      blocks = field (function Blocks a -> Some a.blocks | _ -> None);
      gap = field (function Blocks a -> Some a.gap | _ -> None);
      filled = field (function Blocks a -> Some a.filled | _ -> None);
      squareness = field (function Blocks a -> Some a.squareness | _ -> None);
      clouds = field (function Clouds a -> Some a.clouds | _ -> None);
      puffs = field (function Clouds a -> Some a.puffs | _ -> None);
      size = field (function Clouds a -> Some a.size | _ -> None);
      solid = field (function Clouds a -> Some a.solid | _ -> None);
      bolts = field (function Lightning a -> Some a.bolts | _ -> None);
      branches = field (function Lightning a -> Some a.branches | _ -> None);
      jaggedness = field (function Lightning a -> Some a.jaggedness | _ -> None);
      thickness = field (function Lightning a -> Some a.thickness | _ -> None);
      bg = color s.colours.background (fun d -> d.colours.background);
      fg = color s.colours.foreground (fun d -> d.colours.foreground);
      title = keep s.text.title (fun d -> d.text.title);
      subtitle = keep s.text.subtitle (fun d -> d.text.subtitle);
      year = keep s.text.year (fun d -> d.text.year);
      day = keep s.text.day (fun d -> d.text.day);
      weekday = keep s.text.weekday (fun d -> d.text.weekday);
    }

let settings ~(defaults : settings) = function
  | Routes.Home r ->
      let ( |? ) value default = Option.value value ~default in
      let color value default = match value with Some hex -> "#" ^ hex | None -> default in
      let art =
        match start ~defaults (r.kind |? kind defaults.art) with
        | Lines d -> Lines { lines = r.lines |? d.lines; amplitude = r.amplitude |? d.amplitude; waves = r.waves |? d.waves; stroke = r.stroke |? d.stroke }
        | Blocks d ->
            Blocks { blocks = r.blocks |? d.blocks; gap = r.gap |? d.gap; filled = r.filled |? d.filled; squareness = r.squareness |? d.squareness }
        | Clouds d -> Clouds { clouds = r.clouds |? d.clouds; puffs = r.puffs |? d.puffs; size = r.size |? d.size; solid = r.solid |? d.solid }
        | Lightning d ->
            Lightning
              {
                bolts = r.bolts |? d.bolts;
                branches = r.branches |? d.branches;
                jaggedness = r.jaggedness |? d.jaggedness;
                thickness = r.thickness |? d.thickness;
              }
      in
      normalize ~defaults
        {
          layout = { seed = r.seed |? defaults.layout.seed; padding = r.padding |? defaults.layout.padding };
          art;
          colours = { background = color r.bg defaults.colours.background; foreground = color r.fg defaults.colours.foreground };
          text =
            {
              title = r.title |? defaults.text.title;
              subtitle = r.subtitle |? defaults.text.subtitle;
              year = r.year |? defaults.text.year;
              day = r.day |? defaults.text.day;
              weekday = r.weekday |? defaults.text.weekday;
            };
        }
  | _ -> defaults

let query href = match String.index_opt href '?' with Some i -> String.sub href i (String.length href - i) | None -> ""
let svg route = Routes.poster_svg () ^ query (Routes.href route)
let file (s : settings) extension = "poster-" ^ Int.to_string s.layout.seed ^ "." ^ extension
