module Json = Json
module Async = Async
module Status = Status
module Codec = Codec
module State = struct include State end
module Effect = Base.Effect

let owner = Base.mount
let batch = Scheduler.batch

type server = Types.server
type client = Types.client
type slot = Types.slot
type trigger = Types.trigger
type loading = Types.loading
include Element
module Template = struct include Template end
module Client = Client
module Action = Action
module Optimistic = Optimistic
module Remote = Remote
module Event = Platform.Event
module Browser = Platform.Browser
module Router = Router

module Server = struct
  include Server
  include Cycle

  module Action = struct
    let implement = Server.implement
    let reject = Server.reject
    let rejected = Server.rejected
  end
end

let mount ?islands ?(navigation = true) ?on_error () =
  match islands with
  | Some r when Web.in_browser ->
      Option.iter (fun f -> Client.on_error := f) on_error;
      let { Client.entries; lazy_registry } = r in
      if navigation then Navigation.start ~lazy_entries:lazy_registry entries
      else Client.start ~lazy_entries:lazy_registry entries
  | _ ->
      failwith
        "Yuka.mount: no island registry or not in the browser. Run it in a \
         Melange client entry built with yuka.ppx, which adds ~islands."

let unmount = Navigation.stop

module Private = struct
  include Types
  include Printer

  let stream = Server.stream
  let settled ?timeout ?preload ~sleep build = Server.settled ?timeout ?preload ~sleep build
  let import_map = Server.import_map
  let query = Router.query
  let preload_urls = Server.preload_urls
  let handle_action = Server.handle_action

  let node n = n
  let template_shape (t : template) = t.shape
  let template = Template.of_shape
  let recompile (t : template) = Template.of_shape t.shape
  let template_html (t : template) = t.markup
  let template_plan (t : template) =
    let { Template_build.walk; kids; attrs; values } = t.plan in
    (walk, kids, attrs, values)
  let expand = Template.expand
  let element n = n

  let owned f =
    let o = Base.new_owner () in
    let parent = !Base.current_owner in
    let id =
      Option.map
        (fun p -> (p, Base.add_disposer p (fun () -> Base.dispose_owner o)))
        parent
    in
    let forget () = Option.iter (fun (p, c) -> Base.remove_disposer p c) id in
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
    | Some o -> Base.owner_size o
    | None -> 0

  let has_readers (s : _ Signal.t) = Option.is_some s.node.first

  let slot_content (s : slot) = s.content
  let slot_dom (s : slot) = s.dom
  let call_action = Action.transport
  let async_source = Types.async_source
  let action_codecs (a : (_, _, _) Action.t) = (a.input, a.output)
end
