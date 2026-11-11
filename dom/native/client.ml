include Island

type container = Web.node
type 'a promise = 'a Web.promise

let promise_map = Web.promise_map

type lazy_entry = unit

let lazy_entry ~name:_ _ = ()

let browser_only () = failwith "Yuka: browser only"
let render _ _ = browser_only ()
let hydrate _ _ = browser_only ()
let render_root _ = browser_only ()
let stop_roots () = ()
let start ?lazy_entries:_ _ = browser_only ()
let stop () = ()
let stop_within _ = ()
let on_error : (string -> unit) ref = ref ignore
let use_element () = ()
let use_await () = ()
let use_slot () = ()
let use_catch () = ()
