(* The native side of DOM.melange.ml, so that code built for both the server and the browser
   can call it. Every function raises. The types are unit here: the browser build checks them. *)

type 'a node_like = unit
type 'a element_like = unit
type 'a document_like = unit
type node = unit
type element = unit
type document = unit
type window = unit
type event = unit

let window : window = ()
let document : document = ()

module NodeList = struct
  type 'a t = unit

  let length (_ : 'a t) : int = invalid_arg "Web.DOM: browser only"
  let item (_ : int) (_ : 'a t) : 'a option = invalid_arg "Web.DOM: browser only"
  let forEach (_ : 'a -> unit) (_ : 'a t) : unit = invalid_arg "Web.DOM: browser only"
  let toArray (_ : 'a t) : 'a array = invalid_arg "Web.DOM: browser only"
end

module Element = struct
  let getAttribute (_ : string) (_ : 'a element_like) : string option = invalid_arg "Web.DOM: browser only"
  let setAttribute ~name:(_ : string) ~value:(_ : string) (_ : 'a element_like) : unit = invalid_arg "Web.DOM: browser only"
  let removeAttribute (_ : string) (_ : 'a element_like) : unit = invalid_arg "Web.DOM: browser only"
end

module Document = struct
  let documentElement (_ : 'a document_like) : element = invalid_arg "Web.DOM: browser only"
  let querySelector (_ : string) (_ : 'a document_like) : element option = invalid_arg "Web.DOM: browser only"
  let querySelectorAll (_ : string) (_ : 'a document_like) : element NodeList.t = invalid_arg "Web.DOM: browser only"
end

module HTMLIFrameElement = struct
  let contentDocument (_ : 'a element_like) : document option = invalid_arg "Web.DOM: browser only"
end

module MediaQueryList = struct
  type t = unit

  let matches (_ : t) : bool = invalid_arg "Web.DOM: browser only"
end

module Window = struct
  let matchMedia (_ : string) (_ : window) : MediaQueryList.t = invalid_arg "Web.DOM: browser only"
end
