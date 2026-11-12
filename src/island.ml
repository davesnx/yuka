open Types

  type entry = { name : string; decode : Json.t -> (unit -> node, string) result }

  let island ?(start = `Load) ~name ~props render =
    Island { name; props; render; start }
  let entry ~name decode = { name; decode }
