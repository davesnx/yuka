type t = string ref

let create _ = ref ""
let add_char b c = b := !b ^ Web.of_char c
let add_string b s = b := !b ^ s

let add_substring b s offset len =
  if offset < 0 || len < 0 || offset > String.length s - len then invalid_arg "Buffer.add_substring";
  b := !b ^ Web.sub s offset len

let contents b = !b
