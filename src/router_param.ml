type 'a t = { decode : string -> 'a option; encode : 'a -> string }

let make ~decode ~encode = { decode; encode }
let int = { decode = Router.int_param; encode = string_of_int }
let string = { decode = (fun s -> Some s); encode = (fun s -> s) }

let bool =
  {
    decode = (function "true" -> Some true | "false" -> Some false | _ -> None);
    encode = string_of_bool;
  }

let decode p s = p.decode s
let encode p v = p.encode v
