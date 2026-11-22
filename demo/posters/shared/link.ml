open Pattern

let route ?defaults (s : settings) =
  let keep value default =
    match defaults with Some (d : settings) when value = default d -> None | _ -> Some value
  in
  let color value default = Option.map (fun c -> String.sub c 1 6) (keep value default) in
  Routes.Home
    {
      seed = keep s.grid.seed (fun d -> d.grid.seed);
      columns = keep s.grid.columns (fun d -> d.grid.columns);
      rows = keep s.grid.rows (fun d -> d.grid.rows);
      half = keep s.mix.half (fun d -> d.mix.half);
      empty = keep s.mix.empty (fun d -> d.mix.empty);
      block = keep s.mix.block (fun d -> d.mix.block);
      bar = keep s.mix.bar (fun d -> d.mix.bar);
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
  normalize ~defaults
    {
      grid = { seed = r.seed |? defaults.grid.seed; columns = r.columns |? defaults.grid.columns; rows = r.rows |? defaults.grid.rows };
      mix =
        {
          half = r.half |? defaults.mix.half;
          empty = r.empty |? defaults.mix.empty;
          block = r.block |? defaults.mix.block;
          bar = r.bar |? defaults.mix.bar;
        };
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
let file (s : settings) extension = "poster-" ^ Int.to_string s.grid.seed ^ "." ^ extension
