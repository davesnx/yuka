(* The Web Storage API. Reading localStorage or sessionStorage throws when the browser denies
   storage, so a caller that must not fail wraps the call. storage.ml is the native side. *)

type t

external localStorage : t = "localStorage"
external sessionStorage : t = "sessionStorage"
external getItem : string -> (t[@mel.this]) -> string option = "getItem" [@@mel.send] [@@mel.return nullable]
external setItem : key:string -> value:string -> (t[@mel.this]) -> unit = "setItem" [@@mel.send]
external removeItem : string -> (t[@mel.this]) -> unit = "removeItem" [@@mel.send]
