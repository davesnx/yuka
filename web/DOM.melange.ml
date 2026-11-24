(* The DOM and HTML interfaces that Yuka and its demos use, with their MDN names. A member
   takes the type of the interface that defines it ('a node_like for Node), so an element or a
   document is accepted with no coercion. A member of a specific interface, as
   HTMLIFrameElement.contentDocument, takes any element: there are no downcasts. The receiver
   is the last argument, so calls pipe with |>, but a property setter takes it first, as the
   assignment it stands for (el.x = v), since Melange binds a setter only that way. Arguments of
   the same type have labels. A null
   result is None. The native side, DOM.ml, is generated from this file: same members, each
   raises. *)

type _baseClass = Dom._baseClass
type 'a eventTarget_like = 'a Dom.eventTarget_like
type eventTarget = Dom.eventTarget
type 'a node_like = 'a Dom.node_like
type node = Dom.node
type 'a characterData_like = 'a Dom.characterData_like
type characterData = Dom.characterData
type text = Dom.text
type comment = Dom.comment
type 'a document_like = 'a Dom.document_like
type document = Dom.document
type documentFragment = Dom.documentFragment
type 'a element_like = 'a Dom.element_like
type element = Dom.element
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

module EventTarget = struct
  external addEventListener : string -> ('b event_like -> unit) -> ('a eventTarget_like[@mel.this]) -> unit
    = "addEventListener"
  [@@mel.send]

  external removeEventListener : string -> ('b event_like -> unit) -> ('a eventTarget_like[@mel.this]) -> unit
    = "removeEventListener"
  [@@mel.send]
end

module Node = struct
  external nodeType : 'a node_like -> int = "nodeType" [@@mel.get]
  external ownerDocument : 'a node_like -> document option = "ownerDocument" [@@mel.get] [@@mel.return nullable]
  external parentNode : 'a node_like -> node option = "parentNode" [@@mel.get] [@@mel.return nullable]
  external parentElement : 'a node_like -> element option = "parentElement" [@@mel.get] [@@mel.return nullable]
  external firstChild : 'a node_like -> node option = "firstChild" [@@mel.get] [@@mel.return nullable]
  external lastChild : 'a node_like -> node option = "lastChild" [@@mel.get] [@@mel.return nullable]
  external nextSibling : 'a node_like -> node option = "nextSibling" [@@mel.get] [@@mel.return nullable]
  external previousSibling : 'a node_like -> node option = "previousSibling" [@@mel.get] [@@mel.return nullable]
  external childNodes : 'a node_like -> node NodeList.t = "childNodes" [@@mel.get]
  external textContent : 'a node_like -> string = "textContent" [@@mel.get]
  external setTextContent : 'a node_like -> string -> unit = "textContent" [@@mel.set]
  external appendChild : 'b node_like -> ('a node_like[@mel.this]) -> unit = "appendChild" [@@mel.send]

  external insertBefore : child:'b node_like -> before:'c node_like -> ('a node_like[@mel.this]) -> unit
    = "insertBefore"
  [@@mel.send]

  external cloneNode : deep:bool -> ('a node_like[@mel.this]) -> 'a node_like = "cloneNode" [@@mel.send]
  external contains : 'b node_like -> ('a node_like[@mel.this]) -> bool = "contains" [@@mel.send]
end

module CharacterData = struct
  external data : 'a characterData_like -> string = "data" [@@mel.get]
  external setData : 'a characterData_like -> string -> unit = "data" [@@mel.set]
end

module Element = struct
  external localName : 'a element_like -> string = "localName" [@@mel.get]

  external getAttribute : string -> ('a element_like[@mel.this]) -> string option = "getAttribute"
  [@@mel.send] [@@mel.return nullable]

  external setAttribute : name:string -> value:string -> ('a element_like[@mel.this]) -> unit = "setAttribute"
  [@@mel.send]

  external removeAttribute : string -> ('a element_like[@mel.this]) -> unit = "removeAttribute" [@@mel.send]

  external firstElementChild : 'a element_like -> element option = "firstElementChild"
  [@@mel.get] [@@mel.return nullable]

  external querySelector : string -> ('a element_like[@mel.this]) -> element option = "querySelector"
  [@@mel.send] [@@mel.return nullable]

  external querySelectorAll : string -> ('a element_like[@mel.this]) -> element NodeList.t = "querySelectorAll"
  [@@mel.send]

  external setInnerHTML : 'a element_like -> string -> unit = "innerHTML" [@@mel.set]
  external remove : 'a element_like -> unit = "remove" [@@mel.send]
end

module Document = struct
  external documentElement : 'a document_like -> element = "documentElement" [@@mel.get]
  external body : 'a document_like -> element option = "body" [@@mel.get] [@@mel.return nullable]
  external createElement : string -> ('a document_like[@mel.this]) -> element = "createElement" [@@mel.send]

  external createElementNS : namespace:string -> name:string -> ('a document_like[@mel.this]) -> element
    = "createElementNS"
  [@@mel.send]

  external createTextNode : string -> ('a document_like[@mel.this]) -> text = "createTextNode" [@@mel.send]
  external createComment : string -> ('a document_like[@mel.this]) -> comment = "createComment" [@@mel.send]
  external importNode : 'b node_like -> deep:bool -> ('a document_like[@mel.this]) -> 'b node_like = "importNode"
  [@@mel.send]

  external getElementById : string -> ('a document_like[@mel.this]) -> element option = "getElementById"
  [@@mel.send] [@@mel.return nullable]

  external querySelector : string -> ('a document_like[@mel.this]) -> element option = "querySelector"
  [@@mel.send] [@@mel.return nullable]

  external querySelectorAll : string -> ('a document_like[@mel.this]) -> element NodeList.t = "querySelectorAll"
  [@@mel.send]
end

module HTMLTemplateElement = struct
  external content : 'a element_like -> documentFragment = "content" [@@mel.get]
end

module HTMLIFrameElement = struct
  external contentDocument : 'a element_like -> document option = "contentDocument"
  [@@mel.get] [@@mel.return nullable]
end

module Range = struct
  type t

  external make : 'a document_like -> t = "createRange" [@@mel.send]
  external setStartAfter : 'a node_like -> (t[@mel.this]) -> unit = "setStartAfter" [@@mel.send]
  external setEndBefore : 'a node_like -> (t[@mel.this]) -> unit = "setEndBefore" [@@mel.send]
  external deleteContents : t -> unit = "deleteContents" [@@mel.send]
end

module MediaQueryList = struct
  type t

  external matches : t -> bool = "matches" [@@mel.get]
end

module Window = struct
  external addEventListener : string -> ('b event_like -> unit) -> (window[@mel.this]) -> unit = "addEventListener"
  [@@mel.send]

  external removeEventListener : string -> ('b event_like -> unit) -> (window[@mel.this]) -> unit
    = "removeEventListener"
  [@@mel.send]

  external matchMedia : string -> (window[@mel.this]) -> MediaQueryList.t = "matchMedia" [@@mel.send]
end
