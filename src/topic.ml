type ('k, 's) t = { name : string; key : 'k Codec.t; state : 's Codec.t }

let declare ~name ~key ~state = { name; key; state }
let name t = t.name
let wire_key t k = Json.to_string (t.key.encode k)
