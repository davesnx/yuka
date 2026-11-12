type m

external import : string -> m Web.promise = "import"
external router : m -> Types.router = "router" [@@mel.get]

let load () = Web.promise_map router (import "yuka/navigation.js")
