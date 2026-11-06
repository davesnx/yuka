open Types

  type entry = { name : string; decode : Json.t -> (unit -> node, string) result }

  let island ?(loading = `Load) ~name ~props render =
    Island { name; props; render; loading }
  let entry ~name decode = { name; decode }
