(* The native stand-in for Melange's Dom types, with the same phantom parameters, so the
   native build of yuka.web and of the code that calls it checks the same types. *)

type _baseClass
type 'a eventTarget_like
type eventTarget = _baseClass eventTarget_like
type 'a _node
type 'a node_like = 'a _node eventTarget_like
type node = _baseClass node_like
type 'a _characterData
type 'a characterData_like = 'a _characterData node_like
type characterData = _baseClass characterData_like
type _text
type text = _text characterData_like
type _comment
type comment = _comment characterData_like
type 'a _document
type 'a document_like = 'a _document node_like
type document = _baseClass document_like
type _documentFragment
type documentFragment = _documentFragment node_like
type 'a _element
type 'a element_like = 'a _element node_like
type element = _baseClass element_like
type window
type 'a event_like
type event = _baseClass event_like
