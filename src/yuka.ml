module Json = Json
module Async = Async
module Codec = Codec
module State = Base.State
module Effect = Base.Effect

let mount = Base.mount

type server = Types.server
type client = Types.client
type slot = Types.slot
type loading = Types.loading
include Element
module Client = Client
module Action = Action
module Event = Platform.Event
module Browser = Platform.Browser
module Router = Router
module Server = Server

module Internal = struct
  include Types
  include Printer

  let node n = n
  let element n = n

  let owned f =
    let o = Base.new_owner () in
    let parent = !Base.current_owner in
    let id =
      Option.map
        (fun p -> (p, Base.add_disposer p (fun () -> Base.dispose_owner o)))
        parent
    in
    let forget () =
      Option.iter (fun (p, id) -> Hashtbl.remove p.Base.disposers id) id
    in
    match Base.with_owner o f with
    | result ->
        ( result,
          fun () ->
            forget ();
            Base.dispose_owner o )
    | exception e ->
        forget ();
        Base.dispose_owner o;
        raise e

  let server_rendering = Base.server_rendering
  let platform = Platform.platform
  let entry_name (e : Island.entry) = e.name
  let entry_decode (e : Island.entry) j = e.decode j
  let untracked = Scheduler.untrack

  let owner_size () =
    match !Base.current_owner with
    | Some o -> Hashtbl.length o.Base.disposers
    | None -> 0

  let slot_content (s : slot) = s.content
  let slot_dom (s : slot) = s.dom
  let call_action = Action.transport
  let async_source = Types.async_source
  let action_codecs (a : (_, _) Action.t) = (a.input, a.output)
end
