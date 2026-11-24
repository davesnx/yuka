(* The native side of storage.melange.ml: every function raises. *)

type t

let localStorage : t = Obj.magic ()
let sessionStorage : t = Obj.magic ()
let getItem (_ : string) (_ : t) : string option = invalid_arg "Web.Storage: browser only"
let setItem ~key:(_ : string) ~value:(_ : string) (_ : t) : unit = invalid_arg "Web.Storage: browser only"
let removeItem (_ : string) (_ : t) : unit = invalid_arg "Web.Storage: browser only"
