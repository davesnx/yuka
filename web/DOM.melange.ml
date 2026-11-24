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

  type options

  external options : ?capture:bool -> ?passive:bool -> unit -> options = "" [@@mel.obj]

  external addEventListenerWithOptions :
    string -> ('b event_like -> unit) -> options -> ('a eventTarget_like[@mel.this]) -> unit = "addEventListener"
  [@@mel.send]

  external removeEventListenerWithOptions :
    string -> ('b event_like -> unit) -> options -> ('a eventTarget_like[@mel.this]) -> unit = "removeEventListener"
  [@@mel.send]

  external addEventListenerUseCapture :
    string -> ('b event_like -> unit) -> (_[@mel.as {json|true|json}]) -> ('a eventTarget_like[@mel.this]) -> unit
    = "addEventListener"
  [@@mel.send]

  external removeEventListenerUseCapture :
    string -> ('b event_like -> unit) -> (_[@mel.as {json|true|json}]) -> ('a eventTarget_like[@mel.this]) -> unit
    = "removeEventListener"
  [@@mel.send]

  external dispatchEvent : 'b event_like -> ('a eventTarget_like[@mel.this]) -> bool = "dispatchEvent" [@@mel.send]
end

(* Events. A constructor takes the window whose Event class it uses (the one of the target's
   document, ownerDocument.defaultView), so an event made for a node of another document is of
   that document. *)
module Event = struct
  type init

  external init : ?bubbles:bool -> ?cancelable:bool -> unit -> init = "" [@@mel.obj]
  external make : string -> init -> (window[@mel.this]) -> event = "Event" [@@mel.new] [@@mel.send]
  external type_ : 'a event_like -> string = "type" [@@mel.get]
  external target : 'a event_like -> eventTarget = "target" [@@mel.get]
  external timeStamp : 'a event_like -> float = "timeStamp" [@@mel.get]
  external isTrusted : 'a event_like -> bool = "isTrusted" [@@mel.get]
  external defaultPrevented : 'a event_like -> bool = "defaultPrevented" [@@mel.get]
  external preventDefault : 'a event_like -> unit = "preventDefault" [@@mel.send]
  external stopPropagation : 'a event_like -> unit = "stopPropagation" [@@mel.send]
end

module MouseEvent = struct
  type init

  external init :
    ?bubbles:bool ->
    ?cancelable:bool ->
    ?clientX:float ->
    ?clientY:float ->
    ?button:int ->
    ?shiftKey:bool ->
    ?ctrlKey:bool ->
    ?altKey:bool ->
    ?metaKey:bool ->
    unit ->
    init = ""
  [@@mel.obj]

  external make : string -> init -> (window[@mel.this]) -> event = "MouseEvent" [@@mel.new] [@@mel.send]
  external clientX : 'a event_like -> float = "clientX" [@@mel.get]
  external clientY : 'a event_like -> float = "clientY" [@@mel.get]
  external button : 'a event_like -> int = "button" [@@mel.get]
  external shiftKey : 'a event_like -> bool = "shiftKey" [@@mel.get]
  external ctrlKey : 'a event_like -> bool = "ctrlKey" [@@mel.get]
  external altKey : 'a event_like -> bool = "altKey" [@@mel.get]
  external metaKey : 'a event_like -> bool = "metaKey" [@@mel.get]
end

module KeyboardEvent = struct
  type init

  external init :
    ?bubbles:bool ->
    ?cancelable:bool ->
    ?key:string ->
    ?code:string ->
    ?repeat:bool ->
    ?shiftKey:bool ->
    ?ctrlKey:bool ->
    ?altKey:bool ->
    ?metaKey:bool ->
    unit ->
    init = ""
  [@@mel.obj]

  external make : string -> init -> (window[@mel.this]) -> event = "KeyboardEvent" [@@mel.new] [@@mel.send]
  external key : 'a event_like -> string = "key" [@@mel.get]
  external code : 'a event_like -> string = "code" [@@mel.get]
  external repeat : 'a event_like -> bool = "repeat" [@@mel.get]
end

module PointerEvent = struct
  external pointerType : 'a event_like -> string = "pointerType" [@@mel.get]
end

module InputEvent = struct
  type init

  external init : ?bubbles:bool -> ?cancelable:bool -> ?data:string -> ?inputType:string -> unit -> init = ""
  [@@mel.obj]

  external make : string -> init -> (window[@mel.this]) -> event = "InputEvent" [@@mel.new] [@@mel.send]
  external data : 'a event_like -> string option = "data" [@@mel.get] [@@mel.return nullable]
  external inputType : 'a event_like -> string = "inputType" [@@mel.get]
end

module SubmitEvent = struct
  external submitter : 'a event_like -> element option = "submitter" [@@mel.get] [@@mel.return nullable]
end

module PageTransitionEvent = struct
  external persisted : 'a event_like -> bool = "persisted" [@@mel.get]
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

  external closest : string -> ('a element_like[@mel.this]) -> element option = "closest"
  [@@mel.send] [@@mel.return nullable]

  external hasAttribute : string -> ('a element_like[@mel.this]) -> bool = "hasAttribute" [@@mel.send]
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

module HTMLCollection = struct
  type 'a t

  external length : 'a t -> int = "length" [@@mel.get]
  external toArray : 'a t -> 'a array = "from" [@@mel.scope "Array"]
end

module HTMLInputElement = struct
  external value : 'a element_like -> string = "value" [@@mel.get]
  external setValue : 'a element_like -> string -> unit = "value" [@@mel.set]
  external checked : 'a element_like -> bool = "checked" [@@mel.get]
  external setChecked : 'a element_like -> bool -> unit = "checked" [@@mel.set]
  external type_ : 'a element_like -> string = "type" [@@mel.get]
  external name : 'a element_like -> string = "name" [@@mel.get]
  external defaultValue : 'a element_like -> string = "defaultValue" [@@mel.get]
  external defaultChecked : 'a element_like -> bool = "defaultChecked" [@@mel.get]
end

module HTMLSelectElement = struct
  external options : 'a element_like -> element HTMLCollection.t = "options" [@@mel.get]
end

module HTMLOptionElement = struct
  external selected : 'a element_like -> bool = "selected" [@@mel.get]
end

module HTMLAnchorElement = struct
  external href : 'a element_like -> string = "href" [@@mel.get]
  external origin : 'a element_like -> string = "origin" [@@mel.get]
  external pathname : 'a element_like -> string = "pathname" [@@mel.get]
  external search : 'a element_like -> string = "search" [@@mel.get]
  external hash : 'a element_like -> string = "hash" [@@mel.get]
end

module HTMLMetaElement = struct
  external content : 'a element_like -> string = "content" [@@mel.get]
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

  external addEventListenerWithOptions :
    string -> ('b event_like -> unit) -> EventTarget.options -> (window[@mel.this]) -> unit = "addEventListener"
  [@@mel.send]

  external removeEventListenerWithOptions :
    string -> ('b event_like -> unit) -> EventTarget.options -> (window[@mel.this]) -> unit = "removeEventListener"
  [@@mel.send]

  external matchMedia : string -> (window[@mel.this]) -> MediaQueryList.t = "matchMedia" [@@mel.send]
end
