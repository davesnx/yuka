include Island

type container = Web.node
type 'a promise = 'a Web.promise

let promise_map = Web.promise_map

type lazy_entry = unit

let lazy_entry ~name:_ _ = ()

type registry = { entries : Island.entry list; lazy_registry : lazy_entry list }

let registry ?(lazy_entries = []) entries = { entries; lazy_registry = lazy_entries }
let browser_only () = failwith "Yuka: browser only"
let render _ _ = browser_only ()
let hydrate _ _ = browser_only ()
let start ?lazy_entries:_ _ = browser_only ()
let stop () = ()
let stop_within _ = ()
let on_error : (string -> unit) ref = ref ignore
