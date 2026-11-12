open Types

  type entry = { name : string; decode : Json.t -> (unit -> node, string) result }

  let island ?(start = `Load) ~name ~props render =
    Kind.of_node (Island { name; props; render = Kind.fn render; start })
  let entry ~name decode = { name; decode = Kind.decoder decode }
