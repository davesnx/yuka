val default_zone : unit -> string
val valid_zone : string -> bool
val short : zone:string -> int -> string
val long : zone:string -> int -> string
val to_time : zone:string -> string -> int option
val prefers_dark : unit -> bool
