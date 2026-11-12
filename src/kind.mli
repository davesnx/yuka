type +'kind element

external of_node : Types.node -> 'kind element = "%identity"
external to_node : 'kind element -> Types.node = "%identity"
external nodes : 'kind element list -> Types.node list = "%identity"
external node_array : 'kind element array -> Types.node array = "%identity"
type 'a to_node = 'a -> Types.node
type ('a, 'kind) of_node = 'a -> 'kind element
type to_fallback = error:string -> reset:(unit -> unit) -> Types.node
type to_decoder = Json.t -> (unit -> Types.node, string) result

external fn : ('a -> 'kind element) -> 'a to_node = "%identity"
external of_fn : ('a -> Types.node) -> ('a, 'kind) of_node = "%identity"

external fallback :
  (error:string -> reset:(unit -> unit) -> 'kind element) -> to_fallback
  = "%identity"

external decoder :
  (Json.t -> (unit -> 'kind element, string) result) -> to_decoder = "%identity"
