type entry = Island.entry
type registry = Types.registry
type lazy_entry = Client.lazy_entry
type container = Web.node
type 'a promise = 'a Web.promise

let island = Client.island
let entry = Client.entry
let promise_map = Client.promise_map
let lazy_entry = Client.lazy_entry
let hydrate = Client.hydrate

let registry ?(lazy_entries = []) entries =
  {
    Types.start =
      (fun (navigation, prefetch, transitions, on_error) ->
        Option.iter (fun f -> Client.on_error := f) on_error;
        if navigation then
          Navigation_stub.start ~load:Navigation_load.load ~lazy_entries ?prefetch ?transitions entries
        else Client.start ~lazy_entries entries);
  }
