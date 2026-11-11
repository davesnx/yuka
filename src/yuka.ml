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
module Template = struct
  include Template

  let make shape ~html ~walk ~kids ~attrs ~values =
    Client.use_element ();
    make shape ~html ~walk ~kids ~attrs ~values
end

let template_of_shape shape =
  Client.use_element ();
  Template.of_shape shape
let template_coded = Template.coded
let template_child = Template.child
let template_attribute = Template.attribute
let template_attribute_option = Template.attribute_option
let template_instance = Template.instance
module Client = struct
  include Client

  type registry = {
    start :
      bool * [ `Hover | `Visible | `Off ] option * bool option * (string -> unit) option -> unit;
  }

  let registry ?(lazy_entries = []) entries =
    {
      start =
        (fun (navigation, prefetch, transitions, on_error) ->
          Option.iter (fun f -> Client.on_error := f) on_error;
          if navigation then Navigation.start ~lazy_entries ?prefetch ?transitions entries
          else Client.start ~lazy_entries entries);
    }
end
module Action = Action
module Optimistic = Optimistic
module Remote = Remote
module Topic = Topic
module Live = Live
module Form = Form
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

  module Form = struct
    let implement = Server.implement_form
  end

  module Live = Live_server
end

let render ?islands ?navigation ?prefetch ?transitions ?on_error ?root () =
  if not Web.in_browser then failwith "Yuka.render: browser only";
  match (islands, root) with
  | None, None -> invalid_arg "Yuka.render: no ~islands and no ~root"
  | _ -> (
      (match root with Some r -> Client.render_root r | None -> ());
      match islands with
      | Some { Client.start } ->
          start ((match navigation with Some n -> n | None -> true), prefetch, transitions, on_error)
      | None -> ())

let unmount () =
  Client.stop_roots ();
  Navigation.stop ()

module Private = struct
  include Types
  include Printer

  let stream = Server.stream
  let settled ?timeout ?preload ~sleep build = Server.settled ?timeout ?preload ~sleep build
  let import_map = Server.import_map
  let set_form (s : session) f = s.form <- Some f
  let set_csrf (s : session) f = s.csrf <- Some f
  let reset_live () = Live.manager := None
  let query = Router.query
  let preload_urls = Server.preload_urls
  let handle_action = Server.handle_action

  let dev_script = Cycle.dev_script
  let dev_events = Cycle.dev_events
  let node n = n
  let template_shape (t : template) = Template.shape t
  let template = template_of_shape
  let recompile (t : template) = template_of_shape (Template.shape t)
  let template_html (t : template) = t.markup
  let parser_changes = Template_build.parser_changes
  let template_plan (t : template) =
    let { Template_build.walk; kids; attrs; values } = t.plan in
    (walk, kids, attrs, values)
  let expand t parts =
    Client.use_element ();
    Template.expand t parts
  let element n = n
  let hole f = Hole f

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
  let render = Client.render
end
