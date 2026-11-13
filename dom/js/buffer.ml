type t = string ref

external of_char : char -> string = "fromCharCode" [@@mel.scope "String"]
external slice : string -> int -> int -> string = "slice" [@@mel.send]

let create _ = ref ""
let add_char b c = b := !b ^ of_char c
let add_string b s = b := !b ^ s

let add_substring b s offset len =
  if offset < 0 || len < 0 || offset > String.length s - len then invalid_arg "Buffer.add_substring";
  b := !b ^ slice s offset (offset + len)

let contents b = !b
