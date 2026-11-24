type element
type window
type style

external window : window = "window"
external inner_width : window -> int = "innerWidth" [@@mel.get]
external document_element : element = "documentElement" [@@mel.scope "document"]
external body : element = "body" [@@mel.scope "document"]
external query : string -> element Js.nullable = "querySelector" [@@mel.scope "document"]
external client_width : element -> int = "clientWidth" [@@mel.get]
external offset_width : element -> int = "offsetWidth" [@@mel.get]
external style : element -> style = "style" [@@mel.get]
external computed : element -> style = "getComputedStyle" [@@mel.scope "window"]
external get : style -> string -> string = "getPropertyValue" [@@mel.send]
external set : style -> string -> string -> unit = "setProperty" [@@mel.send]
external parse_float : string -> float = "parseFloat"

let px element property =
  let value = parse_float (get (computed element) property) in
  if Float.is_nan value then 0. else value

(* [scroller] stops scrolling; [padded] gets the width of its scrollbar. *)
let hide ~scroller ~padded ~gap =
  let overflow = get (style scroller) "overflow" and padding = get (style padded) "padding-right" in
  if gap > 0 then set (style padded) "padding-right" (Printf.sprintf "%gpx" (px padded "padding-right" +. float_of_int gap));
  set (style scroller) "overflow" "hidden";
  fun () ->
    set (style scroller) "overflow" overflow;
    set (style padded) "padding-right" padding

let scrolls element =
  match get (computed element) "overflow-y" with "auto" | "scroll" -> true | _ -> false

let container selector =
  match Js.Nullable.toOption (query selector) with
  | Some element when scrolls element ->
      let gap =
        offset_width element - client_width element
        - int_of_float (px element "border-left-width" +. px element "border-right-width")
      in
      Some (hide ~scroller:element ~padded:element ~gap)
  | _ -> None

let lock ~containers () =
  (* Measure every gap before hiding anything: hiding one scrollbar can change another. *)
  let page_gap = inner_width window - client_width document_element in
  let undo = List.filter_map container containers in
  let undo = hide ~scroller:document_element ~padded:body ~gap:page_gap :: undo in
  fun () -> List.iter (fun undo -> undo ()) undo
