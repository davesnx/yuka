open Yuka

let%action double =
  Yuka.Action.query ~input:Codec.int ~output:Codec.string (fun _ n ->
      Async.return (Action_secret.answer n ^ "-body-of-double"))

module Inner = struct
  let%action shout = Action.mutation ~input:Codec.string ~output:Codec.string (fun _ s -> Async.return (String.uppercase_ascii s))
end

let label = "calc kept on both targets"
