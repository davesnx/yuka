(* The DOM and HTML interfaces that Yuka and its demos use, with their MDN names. A member
   takes the type of the interface that defines it ('a Dom.node_like for Node), so an element
   or a document is accepted with no coercion. A member of a specific interface, as
   HTMLIFrameElement.contentDocument, takes any element: there are no downcasts. The receiver
   is the last argument, so calls pipe with |>; arguments of the same type have labels. A null
   result is None. DOM.ml is the native side, where every function raises. *)

type _baseClass = Dom._baseClass
type 'a eventTarget_like = 'a Dom.eventTarget_like
type 'a _node = 'a Dom._node
type 'a node_like = 'a Dom.node_like
type node = Dom.node
type 'a _element = 'a Dom._element
type 'a element_like = 'a Dom.element_like
type element = Dom.element
type 'a _document = 'a Dom._document
type 'a document_like = 'a Dom.document_like
type document = Dom.document
type window = Dom.window
type 'a event_like = 'a Dom.event_like
type event = Dom.event

external window : window = "window"
external document : document = "document"

module NodeList = struct
  type 'a t

  external length : 'a t -> int = "length" [@@mel.get]
  external item : int -> ('a t[@mel.this]) -> 'a option = "item" [@@mel.send] [@@mel.return nullable]
  external forEach : ('a -> unit[@mel.uncurry]) -> ('a t[@mel.this]) -> unit = "forEach" [@@mel.send]
  external toArray : 'a t -> 'a array = "from" [@@mel.scope "Array"]
end

module Element = struct
  external getAttribute : string -> ('a element_like[@mel.this]) -> string option = "getAttribute"
  [@@mel.send] [@@mel.return nullable]

  external setAttribute : name:string -> value:string -> ('a element_like[@mel.this]) -> unit = "setAttribute"
  [@@mel.send]

  external removeAttribute : string -> ('a element_like[@mel.this]) -> unit = "removeAttribute" [@@mel.send]
end

module Document = struct
  external documentElement : 'a document_like -> element = "documentElement" [@@mel.get]

  external querySelector : string -> ('a document_like[@mel.this]) -> element option = "querySelector"
  [@@mel.send] [@@mel.return nullable]

  external querySelectorAll : string -> ('a document_like[@mel.this]) -> element NodeList.t = "querySelectorAll"
  [@@mel.send]
end

module HTMLIFrameElement = struct
  external contentDocument : 'a element_like -> document option = "contentDocument"
  [@@mel.get] [@@mel.return nullable]
end

module MediaQueryList = struct
  type t

  external matches : t -> bool = "matches" [@@mel.get]
end

module Window = struct
  external matchMedia : string -> (window[@mel.this]) -> MediaQueryList.t = "matchMedia" [@@mel.send]
end
