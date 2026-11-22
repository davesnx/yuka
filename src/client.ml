include Island

type container = Web.node

let container _ = None
type 'a promise = 'a Web.promise

let promise_map = Web.promise_map

type lazy_entry = unit

let lazy_entry ~name:_ _ = ()

let acting : Base.owner option ref = ref None
let own_call _ _ = ()

let query name input k =
  let raw, resolve, _ = Async.make () in
  let stop = !Bridge.send name input resolve in
  Answers.record (Answers.key name input) (match Async.status raw with Async.Done r -> Some r | _ -> None) raw;
  Async.on_settled raw (function Async.Done r -> k r | Async.Pending | Async.Failed _ -> ());
  stop

let browser_only () = invalid_arg "Yuka: browser only"
let render _ _ = browser_only ()
let hydrate _ _ = browser_only ()
let render_root _ = browser_only ()
let stop_roots () = ()
let start ?lazy_entries:_ _ = browser_only ()
let stop () = ()
let stop_within _ = ()
let has_handler _ _ _ = false
let on_error : (string -> unit) ref = ref ignore
let use_element () = ()
let use_url_check () = ()
let use_await () = ()
let use_slot () = ()
let use_catch () = ()
let at _ = None
let mount_at _ _ _ = browser_only ()
let hole_start_at _ = browser_only ()
let comment_at _ _ = browser_only ()
let drop_rest_at _ = browser_only ()
let skip_region _ = browser_only ()
let off_page_at _ _ = browser_only ()
let use_actions () = ()
