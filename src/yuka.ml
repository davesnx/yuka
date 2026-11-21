module Json = Json
module Async = Async
module Status = Status
module Codec = Codec
module State = State
module Effect = struct
  include Base.Effect

  let on_change = State.on_change
end

let with_owner = Base.mount
let batch = Scheduler.batch

type server = Types.server
type client = Types.client
type trigger = Types.trigger
type start = Types.start
include Element

let view_transition f = Web.view_transition (fun () -> batch f)

let view_transition_name name =
  let rec ok i =
    i = String.length name
    || (match name.[i] with
       | 'a' .. 'z' | 'A' .. 'Z' | '_' -> true
       | '0' .. '9' | '-' -> i > 0
       | _ -> false)
       && ok (i + 1)
  in
  if String.length name > 0 && ok 0 then "view-transition-name:" ^ name
  else invalid_arg ("Yuka.view_transition_name: " ^ name)

module Client = struct
  include Client

  type registry = {
    start : bool * bool option * (string -> unit) option -> unit;
  }
end
module Action = Action
module Remote = Remote
module Topic = Topic
module Live = Live
module Form = Form
module Event = Event
module Browser = Browser
module Router = struct
  include Router
  module Param = Router_param
end

let runtime_route_current find = Route.current find
let runtime_route_replace = Route.replace
let runtime_route_push = Route.push

module Console = struct
  let send level browser message = if Web.in_browser then browser message else Types.log_message level message
  let log = send `Info Web.console_log
  let info = send `Info Web.console_info
  let warn = send `Warn Web.console_warn
  let error = send `Error Web.console_error
  let debug = send `Debug Web.console_debug
end

module Server = struct
  include Server
  include Cycle

  type request = Types.context
  type log_level = Types.log_level

  let to_string build = Server.to_string (Kind.fn build)
  let page ?title ?head body = Cycle.page ?title ?head (Kind.fn body)

  module Action = struct
    let implement = Server.implement
    let reject = Server.reject
  end

  module Form = struct
    let implement = Server.implement_form
  end

  module Live = Live_server
  module Generated = struct
    type rules = Cycle.rules
    type layer = Cycle.layer = { key : string; data : bool; wrap : Types.server Kind.element -> Types.server Kind.element }
    type plan = Cycle.plan = { layers : layer list; page : Cycle.page; overlay : Cycle.page option }

    type fallback = Cycle.fallback = {
      layers : layer list;
      not_found : string -> Cycle.page;
      error : unit -> Cycle.page;
    }

    type target = Cycle.target =
      | Page of {
          rules : rules;
          guards : (unit -> (unit, Cycle.stop) result Async.t) list;
          load : unit -> (plan, Cycle.stop) result Async.t;
          fallback : fallback;
        }
      | Handler of {
          rules : rules;
          action : bool;
          cross_origin : bool;
          guards : (unit -> (unit, Cycle.stop) result Async.t) list;
          run : unit -> Cycle.response Async.t;
        }

    let rules = Cycle.rules
    let default_not_found = Cycle.default_not_found
    let default_error = Cycle.default_error
    let loaded = Cycle.loaded
    let app = Cycle.app
  end

  module Adapter = struct
    module type Backend = Cycle.ADAPTER

    module Make = Cycle.Make

    let default_log = Cycle.default_log

    let build_id = Cycle.build_id
  end

  module Prerender = struct
    let config = Cycle.prerender_config
    let seeds = Cycle.prerender_seeds
    let prerenderable = Cycle.prerenderable
    let links = Cycle.links
    let file = Cycle.prerender_file
    let missing_page = Cycle.missing_page
    let css_files = Cycle.css_files
    let served_dirs = Cycle.served_dirs
  end

  let set_default_log f = Types.default_log := f

  module Testing = struct
    let live_run = Live_server.run
    let live_mark = Live_server.mark
    let memory_down = Live_server.memory_down
    let bus_send (b : Live.bus) = b.send
    let bus_listen (b : Live.bus) = b.listen
    let bus_on_restart (b : Live.bus) = b.on_restart
    let json_diff = Json_diff.diff
    let live_state ?node ~sleep request name key = Live_server.ssr_state ~sleep (Live_server.pick node) request name key
    let json_patch = Json_patch.apply

    let request ?(header = fun _ -> None) ?session ?(meth = `GET) ?(target = "") ?body () : request =
      let empty = Server.empty_context () in
      let body =
        match body with
        | None -> empty.body
        | Some text -> Server.read_once (fun ~limit -> Async.return (if String.length text > limit then None else Some text))
      in
      { empty with header; session = (fun () -> session); meth; target; path = fst (Router.split_target target); body }
  end
end

let render ?islands ?navigation ?transitions ?on_error ?root () =
  if not Web.in_browser then invalid_arg "Yuka.render: browser only";
  match (islands, root) with
  | None, None -> invalid_arg "Yuka.render: no ~islands and no ~root"
  | _ -> (
      (match root with Some r -> Client.render_root r | None -> ());
      match islands with
      | Some { Client.start } ->
          start ((match navigation with Some n -> n | None -> true), transitions, on_error)
      | None -> ())

let stop () =
  Client.stop_roots ();
  Navigation_stub.stop ()

type runtime_template = Template.t
type 'kind runtime_part = 'kind Template.part
type runtime_entry = Client.entry
type runtime_lazy_entry = Client.lazy_entry
type 'a runtime_promise = 'a Client.promise
type runtime_router = Types.router
type 'f runtime_form_decoding = 'f Form_core.decoding

let runtime_attr = attr_unchecked
let runtime_hole_attr = hole_attr_unchecked
let runtime_hole = hole
let runtime_text_call f x = hole (fun () -> text (f x))
let runtime_call_attr name f x = hole_attr_unchecked name (fun () -> Some (f x))
let runtime_url_attr = url_attr
let runtime_url_hole_attr = url_hole_attr
let runtime_template = Template.coded
let runtime_child = Template.child
let runtime_attribute = Template.attribute
let runtime_attribute_option = Template.attribute_option
let runtime_instance = Template.instance
let runtime_stylesheet = stylesheet
let runtime_island = Client.island
let runtime_entry = Client.entry
let runtime_lazy_entry = Client.lazy_entry
let runtime_promise_map = Client.promise_map

let runtime_registry ?(lazy_entries = []) ?navigation:load entries =
  {
    Client.start =
      (fun (navigation, transitions, on_error) ->
        Option.iter (fun f -> Client.on_error := f) on_error;
        match load with
        | Some load when navigation ->
            Navigation_stub.start ~load ~lazy_entries ?transitions entries
        | _ -> Client.start ~lazy_entries entries);
  }

let runtime_form_fields = Form_core.fields
let runtime_form_field = Form_core.field
let runtime_form_get = Form_core.get
let runtime_form_finish = Form_core.finish
let runtime_form_put = Form_core.put

module Private = struct
  include Types
  include Printer

  type env = Scheduler.env

  let print s build = print s build

  let stream ?head ?early ?import_map ?timeout ?title ?styles ?scripts ?preload ~sleep ~write build =
    Server.stream ?head ?early ?import_map ?timeout ?title ?styles ?scripts ?preload ~sleep ~write (Kind.fn build)

  let settled ?timeout ?preload ?id_prefix ~sleep build =
    Server.settled ?timeout ?preload ?id_prefix ~sleep (Kind.fn build)
  let import_map = Server.import_map
  let set_form (s : session) f = s.form <- Some f
  let set_csrf (s : session) f = s.csrf <- Some f
  let reset_live () = !Bridge.reset_live ()
  let query = Router.query
  let preload_urls ~manifest ~base ?metafile ?entry () = Server.preload_urls ~manifest ~base ?metafile ?entry ()
  let handle_action ~name ~header ~body =
    Server.handle_action ~live:(Live_server.mark_json (Live_server.main ())) ~name ~header ~body

  let dev_script = Cycle.dev_script
  let dev_events = Cycle.dev_events ~log:(fun level m -> !Types.default_log level m)
  let node = Kind.to_node

  module Template = struct
    include Template

    let make shape ~html ~walk ~kids ~attrs ~values =
      Client.use_element ();
      make shape ~html ~walk ~kids ~attrs ~values
  end

  let template shape =
    Client.use_element ();
    Template.of_shape shape

  let recompile (t : template) = template (Template.shape t)
  let template_html (t : template) = t.markup
  let parser_changes = Template_build.parser_changes
  let template_plan (t : template) =
    let { Template_build.walk; kids; attrs; values } = t.plan in
    (walk, kids, attrs, values)
  let expand t parts =
    Client.use_element ();
    Template.expand t parts
  let element = Kind.of_node
  let hole f = Hole f

  let owned f =
    let o = Base.new_owner () in
    let parent = !(Base.current_owner ()) in
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

  let with_context bindings f =
    let o = Base.new_owner () in
    o.env <- add_bindings bindings o.env;
    Option.iter (fun p -> ignore (Base.add_disposer p (fun () -> Base.dispose_owner o))) !(Base.current_owner ());
    Base.with_owner o f

  let server_rendering () = !(Base.server_rendering ())
  let in_browser = Web.in_browser
  let decode_uri = Web.decode_uri
  let platform = Platform.platform
  let entry_name (e : Island.entry) = e.name
  let entry_decode (e : Island.entry) j = e.decode j

  let owner_size () =
    match !(Base.current_owner ()) with
    | Some o -> Base.owner_size o
    | None -> 0

  let has_readers s = Option.is_some (State.signal s).node.first

  let slot = slot

  module Slot = Slot

  let slot_content (s : slot) = s.content
  let slot_dom (s : slot) = s.dom
  let call_action = Bridge.send
  let async_source = Types.async_source
  let page_contexts () = !Platform.swapped != Platform.no_swap
  let render = Client.render
  let hydrate = Client.hydrate
end
