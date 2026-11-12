type t

external of_slot : Types.slot -> t = "%identity"
external to_slot : t -> Types.slot = "%identity"
