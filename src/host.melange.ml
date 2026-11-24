type node = Web.DOM.element
type event = Web.DOM.event

external as_element : 'a Web.DOM.node_like -> node = "%identity"
external as_elements : Web.DOM.node option -> node option = "%identity"
external as_data : 'a Web.DOM.node_like -> Web.DOM.characterData = "%identity"
type 'a promise = 'a Js.Promise.t
type any

let in_browser = true

external global_window : node = "window"
external global_document : node = "document"
external global_this : node = "globalThis"

external owner_document : node -> node = "ownerDocument" [@@mel.get]
external create_element : node -> string -> node = "createElement" [@@mel.send]
external node_type : node -> int = "nodeType" [@@mel.get]
external local_name : node -> string = "localName" [@@mel.get]
external append_child : node -> node -> unit = "appendChild" [@@mel.send]
external set_attribute : node -> string -> string -> unit = "setAttribute" [@@mel.send]
external set_string : node -> string -> string -> unit = "" [@@mel.set_index]
external set_bool : node -> string -> bool -> unit = "" [@@mel.set_index]
external set_prop : 'o -> string -> 'a -> unit = "" [@@mel.set_index]
external get_prop : 'o -> string -> 'a option = "" [@@mel.get_index] [@@mel.return nullable]
external add_listener : node -> string -> (event -> unit) -> unit = "addEventListener" [@@mel.send]
external remove_listener : node -> string -> (event -> unit) -> unit = "removeEventListener" [@@mel.send]
external target : event -> node = "target" [@@mel.get]
external value : node -> string = "value" [@@mel.get]
external checked : node -> bool = "checked" [@@mel.get]
external key : event -> string = "key" [@@mel.get]
external meta_key : event -> bool = "metaKey" [@@mel.get]
external ctrl_key : event -> bool = "ctrlKey" [@@mel.get]
external prevent_default : event -> unit = "preventDefault" [@@mel.send]


external query_all : node -> string -> node array = "querySelectorAll" [@@mel.send]
external console_error : string -> unit = "error" [@@mel.scope "console"]
external console_warn : string -> unit = "warn" [@@mel.scope "console"]
external console_info : string -> unit = "info" [@@mel.scope "console"]
external console_log : string -> unit = "log" [@@mel.scope "console"]
external console_debug : string -> unit = "debug" [@@mel.scope "console"]

external field : 'o -> string -> any = "" [@@mel.get_index]
external truthy : 'a -> bool = "Boolean"
external js_string : 'a -> string = "String"
external push : 'a array -> 'a -> unit = "push" [@@mel.send]
external join : string array -> string -> string = "join" [@@mel.send]
external lowercase : string -> string = "toLowerCase" [@@mel.send]
external index_of : string -> string -> int = "indexOf" [@@mel.send]
external slice : string -> int -> int -> string = "slice" [@@mel.send]
external slice_from : string -> int -> string = "slice" [@@mel.send]
external default_view : node -> node = "defaultView" [@@mel.get]
external parent_element : node -> node option = "parentElement"
[@@mel.get] [@@mel.return nullable]
external closest : node -> string -> node Js.null = "closest" [@@mel.send]
external query_selector : node -> string -> node option = "querySelector"
[@@mel.send] [@@mel.return nullable]
external get_attribute_null : node -> string -> string Js.null = "getAttribute" [@@mel.send]
external has_attribute : node -> string -> bool = "hasAttribute" [@@mel.send]
external dispatch : node -> event -> unit = "dispatchEvent" [@@mel.send]
external has_own : 'o -> string -> bool = "hasOwnProperty" [@@mel.send]
external has_key : node -> string -> bool = "has" [@@mel.scope "Reflect"]
external delete_key : node -> string -> unit = "deleteProperty" [@@mel.scope "Reflect"]
external error_message : Js.Exn.t -> string = "message" [@@mel.get]
external re_test : Js.Re.t -> string -> bool = "test" [@@mel.send]
external replace_re : string -> Js.Re.t -> string -> string = "replace" [@@mel.send]

let is_function v = Js.typeof v = "function"
let message e = if truthy e && truthy (error_message e) then js_string (error_message e) else js_string e

external exn_id : exn -> string = "MEL_EXN_ID" [@@mel.get]

let exn_to_string e =
  let args = [||] and i = ref 1 in
  while has_own e ("_" ^ string_of_int !i) do
    push args (js_string (field e ("_" ^ string_of_int !i)));
    incr i
  done;
  if Array.length args > 0 then exn_id e ^ "(" ^ join args ", " ^ ")" else exn_id e

external encode_uri : string -> string = "encodeURIComponent"
external decode_uri_exn : string -> string = "decodeURIComponent"

let decode_uri s = try Some (decode_uri_exn s) with _ -> None

external replace_by : string -> Js.Re.t -> (string -> string[@mel.uncurry]) -> string = "replace"
[@@mel.send]
external char_code : string -> int -> int = "charCodeAt" [@@mel.send]
external radix : int -> int -> string = "toString" [@@mel.send]
external uppercase : string -> string = "toUpperCase" [@@mel.send]

let encode_cookie_value s =
  try
    Some
      (replace_by (encode_uri s) [%mel.re "/[!'()*]/g"] (fun c ->
           "%" ^ uppercase (radix (char_code c 0) 16)))
  with _ -> None

external contains : node -> node -> bool = "contains" [@@mel.send]

type controller
type signal
type response

external abort_controller : unit -> controller = "AbortController" [@@mel.new]
external signal : controller -> signal = "signal" [@@mel.get]
external aborted : signal -> bool = "aborted" [@@mel.get]
external abort : controller -> unit = "abort" [@@mel.send]
external status : response -> int = "status" [@@mel.get]
external text : response -> string promise = "text" [@@mel.send]
external then_ : 'a promise -> ('a -> 'b[@mel.uncurry]) -> 'b promise = "then" [@@mel.send]
external then_promise : 'a promise -> ('a -> 'b promise[@mel.uncurry]) -> 'b promise = "then" [@@mel.send]
external then_or : 'a promise -> ('a -> unit[@mel.uncurry]) -> (Js.Exn.t -> unit[@mel.uncurry]) -> unit = "then"
[@@mel.send]
external catch : unit promise -> (Js.Exn.t -> unit[@mel.uncurry]) -> unit = "catch" [@@mel.send]

external fetch_exn : string -> < .. > Js.t -> response promise = "fetch"

let fetch_post url body ok fail =
  let control = abort_controller () in
  match
    fetch_exn url
      [%mel.obj
        {
          _method = "POST";
          headers = [%mel.obj { content_type = "application/json" [@mel.as "Content-Type"] }];
          body;
          signal = signal control;
        }]
  with
  | exception Js.Exn.Error e ->
      fail false (message e);
      fun () -> ()
  | request ->
      let code = ref 0 in
      then_or
        (then_promise request (fun r ->
             code := status r;
             text r))
        (fun t -> ok !code t)
        (fun e -> fail (aborted (signal control)) (message e));
      fun () -> abort control

type mutation_observer
type mutation
external mutation_observer : (mutation array -> mutation_observer -> unit[@mel.uncurry]) -> mutation_observer
  = "MutationObserver"
[@@mel.new] [@@mel.scope "document", "defaultView"]
external observe_mutations : mutation_observer -> node -> < .. > Js.t -> unit = "observe" [@@mel.send]
external disconnect_mutations : mutation_observer -> unit = "disconnect" [@@mel.send]
external added_nodes : mutation -> node array = "addedNodes" [@@mel.get]
external mutation_type : mutation -> string = "type" [@@mel.get]
external mutation_target : mutation -> node = "target" [@@mel.get]

let watch_added check =
  let observer =
    mutation_observer (fun records observer ->
        let added = [||] in
        for i = 0 to Array.length records - 1 do
          let r = Array.unsafe_get records i in
          let nodes = added_nodes r in
          for j = 0 to Array.length nodes - 1 do
            let n = Array.unsafe_get nodes j in
            if node_type n = 1 then push added n
          done;
          let t = mutation_target r in
          if mutation_type r = "characterData" then (
            match parent_element t with Some p when local_name p = "script" -> push added p | _ -> ())
          else if local_name t = "script" && Array.length nodes > 0 then push added t
        done;
        if Array.length added > 0 && check added then disconnect_mutations observer)
  in
  observe_mutations observer global_document [%mel.obj { childList = true; subtree = true; characterData = true }];
  fun () -> disconnect_mutations observer

external shift_key : event -> bool = "shiftKey" [@@mel.get]
external alt_key : event -> bool = "altKey" [@@mel.get]
external client_x : event -> float = "clientX" [@@mel.get]
external client_y : event -> float = "clientY" [@@mel.get]
external pointer_type : event -> string = "pointerType" [@@mel.get]
external stop_propagation : event -> unit = "stopPropagation" [@@mel.send]
external set_flag : event -> string -> bool -> unit = "" [@@mel.set_index]
external get_flag : event -> string -> bool option = "" [@@mel.get_index] [@@mel.return nullable]
external location_replace : string -> unit = "replace" [@@mel.scope "window", "location"]
external location_assign : string -> unit = "assign" [@@mel.scope "window", "location"]

let navigate replace url = if replace then location_replace url else location_assign url

external confirm : string -> bool = "confirm" [@@mel.scope "window"]
external focus_node : node -> unit = "focus" [@@mel.send]
external scroll_into_view_node : node -> unit = "scrollIntoView" [@@mel.send]

let focus id = match Web.DOM.Document.getElementById id Web.DOM.document with Some el -> focus_node el | None -> ()

let scroll_into_view id =
  match Web.DOM.Document.getElementById id Web.DOM.document with Some el -> scroll_into_view_node el | None -> ()



let has_intersection_observer el =
  is_function (field (default_view (owner_document el)) "IntersectionObserver")

type form_data
type form_value
type form_entry = string * form_value

external form_data_of : node -> node -> form_data = "FormData" [@@mel.new] [@@mel.send]
external form_data_each : form_data -> (form_value -> string -> unit[@mel.uncurry]) -> unit = "forEach"
[@@mel.send]
external form_text : form_value -> string = "%identity"
external submitter : event -> node option = "submitter" [@@mel.get] [@@mel.return nullable]
external name : node -> string = "name" [@@mel.get]

let form_values ev =
  let el = target ev and out = [||] in
  form_data_each (form_data_of (default_view (owner_document el)) el) (fun v k ->
      if Js.typeof v = "string" then push out (k, form_text v));
  (match submitter ev with Some s when truthy (name s) -> push out (name s, value s) | _ -> ());
  out

external microtask : (unit -> unit) -> unit = "queueMicrotask"

type timer

external set_timeout_ : (unit -> unit[@mel.uncurry]) -> int -> timer = "setTimeout"
external clear_timeout : timer -> unit = "clearTimeout"

let set_timeout ms f =
  let id = set_timeout_ (fun () -> f ()) ms in
  fun () -> clear_timeout id

external request_idle_callback : node -> (unit -> unit[@mel.uncurry]) -> timer = "requestIdleCallback"
[@@mel.send]
external cancel_idle_callback : node -> timer -> unit = "cancelIdleCallback" [@@mel.send]
external view_set_timeout : node -> (unit -> unit[@mel.uncurry]) -> int -> timer = "setTimeout" [@@mel.send]
external view_clear_timeout : node -> timer -> unit = "clearTimeout" [@@mel.send]

let on_idle f =
  let w = default_view global_document in
  if is_function (field w "requestIdleCallback") then
    let id = request_idle_callback w (fun () -> f ()) in
    fun () -> (if is_function (field w "cancelIdleCallback") then cancel_idle_callback w id)
  else
    let id = view_set_timeout w (fun () -> f ()) 200 in
    fun () -> view_clear_timeout w id

external request_animation_frame : node -> (float -> unit[@mel.uncurry]) -> int = "requestAnimationFrame"
[@@mel.send]
external cancel_animation_frame : node -> int -> unit = "cancelAnimationFrame" [@@mel.send]

let on_frame f =
  let w = default_view global_document in
  let live = ref true and id = ref 0 in
  let rec tick time =
    if !live then (
      id := request_animation_frame w tick;
      f time)
  in
  id := request_animation_frame w tick;
  fun () ->
    live := false;
    cancel_animation_frame w !id

external performance : node -> node = "performance" [@@mel.get]
external performance_now : node -> float = "now" [@@mel.send]

let now () = performance_now (performance (default_view global_document))

type intersection_observer
type intersection

external intersection_observer :
  node -> (intersection array -> unit[@mel.uncurry]) -> intersection_observer
  = "IntersectionObserver"
[@@mel.new] [@@mel.send]
external observe_intersections : intersection_observer -> node -> unit = "observe" [@@mel.send]
external disconnect_intersections : intersection_observer -> unit = "disconnect" [@@mel.send]
external is_intersecting : intersection -> bool = "isIntersecting" [@@mel.get]

let on_visible el f =
  let self = ref Js.null in
  let observer =
    intersection_observer (default_view (owner_document el)) (fun entries ->
        let rec first i =
          if i < Array.length entries then
            if is_intersecting (Array.unsafe_get entries i) then (
              (match Js.Null.toOption !self with Some o -> disconnect_intersections o | None -> ());
              f ())
            else first (i + 1)
        in
        first 0)
  in
  self := Js.Null.return observer;
  observe_intersections observer el;
  fun () -> disconnect_intersections observer

external map_promise : 'a promise -> ('a -> 'b) -> 'b promise = "then" [@@mel.send]

let promise_map f p = map_promise p f
let promise_then ok fail p = catch (map_promise p (fun v -> ignore (ok v))) (fun e -> fail (message e))

external document_ready_state : node -> string = "readyState" [@@mel.get]

let ready_state () = document_ready_state global_document

let on_dom_ready f =
  let handler _ = f () in
  add_listener global_document "DOMContentLoaded" handler;
  fun () -> remove_listener global_document "DOMContentLoaded" handler



external clone_node : node -> bool -> node = "cloneNode" [@@mel.send]
external first_child_node : node -> node = "firstChild" [@@mel.get]
external next_sibling_node : node -> node = "nextSibling" [@@mel.get]

let walk root w =
  let out = [| root |] and i = ref 0 in
  while !i < Array.length w do
    let step = Array.unsafe_get w !i in
    let n = ref (Array.unsafe_get out (step asr 1)) in
    if step land 1 = 0 then n := first_child_node !n;
    for _ = 1 to Array.unsafe_get w (!i + 1) do
      n := next_sibling_node !n
    done;
    push out !n;
    i := !i + 2
  done;
  out

type range

external create_range : node -> range = "createRange" [@@mel.send]
external set_start_after : range -> node -> unit = "setStartAfter" [@@mel.send]
external set_end_before : range -> node -> unit = "setEndBefore" [@@mel.send]
external delete_contents : range -> unit = "deleteContents" [@@mel.send]

let delete_between parent start stop =
  let r = create_range (owner_document parent) in
  set_start_after r start;
  set_end_before r stop;
  delete_contents r


type recorded = {
  kind : string;
  node : node;
  ev : event;
  is_field : bool;
  text : string;
  ticked : bool Js.undefined;
}

external event_type : event -> string = "type" [@@mel.get]
external button : event -> int = "button" [@@mel.get]
external code : event -> string = "code" [@@mel.get]
external repeat : event -> bool = "repeat" [@@mel.get]
external input_data : event -> string Js.null = "data" [@@mel.get]
external input_type : event -> string = "inputType" [@@mel.get]
external checked_undefined : node -> bool Js.undefined = "checked" [@@mel.get]
external set_value : node -> string -> unit = "value" [@@mel.set]
external set_checked : node -> bool -> unit = "checked" [@@mel.set]
external input_kind : node -> string = "type" [@@mel.get]
external add_capture : node -> string -> (event -> unit) -> (_[@mel.as {json|true|json}]) -> unit = "addEventListener"
[@@mel.send]
external remove_capture : node -> string -> (event -> unit) -> (_[@mel.as {json|true|json}]) -> unit
  = "removeEventListener"
[@@mel.send]
external new_event : node -> string -> < .. > Js.t -> event = "Event" [@@mel.new] [@@mel.send]
external new_mouse_event : node -> string -> < .. > Js.t -> event = "MouseEvent" [@@mel.new] [@@mel.send]
external new_keyboard_event : node -> string -> < .. > Js.t -> event = "KeyboardEvent" [@@mel.new] [@@mel.send]
external new_input_event : node -> string -> < .. > Js.t -> event = "InputEvent" [@@mel.new] [@@mel.send]

let recorded_types = [| "click"; "input"; "change"; "submit"; "keydown" |]

let copy_event w kind ev =
  if kind = "click" then
    new_mouse_event w kind
      [%mel.obj
        {
          bubbles = true;
          cancelable = true;
          clientX = client_x ev;
          clientY = client_y ev;
          button = button ev;
          shiftKey = shift_key ev;
          ctrlKey = ctrl_key ev;
          altKey = alt_key ev;
          metaKey = meta_key ev;
        }]
  else if kind = "keydown" then
    new_keyboard_event w kind
      [%mel.obj
        {
          bubbles = true;
          cancelable = true;
          key = key ev;
          code = code ev;
          repeat = repeat ev;
          shiftKey = shift_key ev;
          ctrlKey = ctrl_key ev;
          altKey = alt_key ev;
          metaKey = meta_key ev;
        }]
  else if kind = "input" && truthy (field w "InputEvent") then
    new_input_event w kind [%mel.obj { bubbles = true; cancelable = true; data = input_data ev; inputType = input_type ev }]
  else new_event w kind [%mel.obj { bubbles = true; cancelable = true }]

let record_events island =
  let queue = ref [||] in
  let listener ev =
    let t = target ev in
    let mine =
      if truthy (field t "closest") then
        Js.Null.return island == closest t "yuka-island"
      else true
    in
    if mine then (
        let kind = event_type ev in
        let is_field = (kind = "input" || kind = "change") && truthy t && has_key t "value" in
        if is_field then set_prop t "__yukaRecorded" 1;
        push !queue
          {
            kind;
            node = t;
            ev;
            is_field;
            text = (if is_field then value t else "");
            ticked = (if is_field then checked_undefined t else Js.undefined);
          })
  in
  let each f = Array.iter f recorded_types in
  each (fun t -> add_capture island t listener);
  let stop () =
    each (fun t -> remove_capture island t listener);
    Array.iter (fun i -> delete_key i.node "__yukaRecorded") !queue
  in
  let drop () =
    stop ();
    queue := [||]
  in
  let replay () =
    stop ();
    let items = !queue in
    queue := [||];
    let w = default_view (owner_document island) in
    Array.iter
      (fun { kind; node; ev; is_field; text; ticked } ->
        if contains island node then (
          if is_field then (
            set_value node text;
            match Js.Undefined.toOption ticked with Some c -> set_checked node c | None -> ());
          let copy = copy_event w kind ev in
          let toggles = kind = "click" && (input_kind node = "checkbox" || input_kind node = "radio") in
          let before = toggles && checked node in
          dispatch node copy;
          if toggles then set_checked node before))
      items
  in
  (drop, replay)

external options : node -> node array = "options" [@@mel.get]
external selected : node -> bool = "selected" [@@mel.get]
external default_checked : node -> bool = "defaultChecked" [@@mel.get]
external default_value : node -> string = "defaultValue" [@@mel.get]

let touched n tag =
  if tag = "option" then
    match Js.Null.toOption (closest n "select") with Some s when truthy (field s "__yukaKept") -> 1 | _ -> 0
  else
    let changed =
      if tag = "select" then (
        let d = options (clone_node n true) and o = options n in
        let rec differs i =
          i < Array.length o
          && (selected (Array.unsafe_get o i) <> selected (Array.unsafe_get d i) || differs (i + 1))
        in
        let c = differs 0 in
        set_bool n "__yukaKept" c;
        c)
      else if tag = "input" || tag = "textarea" then
        let t = input_kind n in
        if t = "checkbox" || t = "radio" then checked n <> default_checked n else value n <> default_value n
      else false
    in
    if not changed then 0
    else if truthy (field n "__yukaRecorded") || (input_kind n = "radio" && not (checked n)) then 1
    else 2

let fire n =
  let w = default_view (owner_document n) in
  dispatch n (new_event w "input" [%mel.obj { bubbles = true }]);
  dispatch n (new_event w "change" [%mel.obj { bubbles = true }])

type url

external new_url : string -> string -> url = "URL" [@@mel.new]
external url_origin : url -> string = "origin" [@@mel.get]
external url_pathname : url -> string = "pathname" [@@mel.get]
external url_search : url -> string = "search" [@@mel.get]
external url_href : url -> string = "href" [@@mel.get]
external set_search : url -> string -> unit = "search" [@@mel.set]
external location_href : string = "href" [@@mel.scope "window", "location"]
external location_origin : string = "origin" [@@mel.scope "window", "location"]
external location_pathname : string = "pathname" [@@mel.scope "window", "location"]
external location_search : string = "search" [@@mel.scope "window", "location"]
external location_protocol : string = "protocol" [@@mel.scope "window", "location"]
external location_host : string = "host" [@@mel.scope "window", "location"]

let same_origin url = try url_origin (new_url url location_href) = location_origin with _ -> false
let current_url () = location_pathname ^ location_search

let local_url u =
  try
    let x = new_url u location_href in
    if url_origin x = location_origin then url_pathname x ^ url_search x else url_href x
  with _ -> u

external date_now : unit -> float = "now" [@@mel.scope "Date"]

let fresh_key () =
  let k = (match get_prop global_this "__yukaKeys" with Some k -> k | None -> 0) + 1 in
  set_prop global_this "__yukaKeys" k;
  js_string (date_now ()) ^ "-" ^ string_of_int k

external history_state : any = "state" [@@mel.scope "window", "history"]
external state_key : any -> string = "yukaKey" [@@mel.get]
external state_at : any -> int = "yukaAt" [@@mel.get]
external push_state : 'a -> string -> string -> unit = "pushState" [@@mel.scope "window", "history"]
external replace_state : 'a -> string -> string -> unit = "replaceState" [@@mel.scope "window", "history"]

let entry_at s = if truthy s && truthy (field s "yukaAt") then state_at s else 0

let history_key () =
  let s = history_state in
  if truthy s && Js.typeof (field s "yukaKey") = "string" then state_key s else ""

let history_replace_key k = replace_state [%mel.obj { yukaKey = k }] "" location_href
let history_push_key k url = push_state [%mel.obj { yukaKey = k; yukaAt = entry_at history_state + 1 }] "" url
let history_at () = entry_at history_state

external history_go : int -> unit = "go" [@@mel.scope "window", "history"]

type style

external get_computed_style : node -> style = "getComputedStyle" [@@mel.scope "window"]
external overflow_y : style -> string = "overflowY" [@@mel.get]
external document_body : node Js.null = "body" [@@mel.scope "document"]
external document_element : node = "documentElement" [@@mel.scope "document"]
external scroll_top : node -> float = "scrollTop" [@@mel.get]
external set_scroll_top : node -> float -> unit = "scrollTop" [@@mel.set]
external window_scroll_y : float = "scrollY" [@@mel.scope "window"]
external window_scroll_to : float -> float -> unit = "scrollTo" [@@mel.scope "window"]

let or_zero x = if truthy x then x else 0.

external parent_element_null : node -> node Js.null = "parentElement" [@@mel.get]

let scrolls el =
  let oy = overflow_y (get_computed_style el) in
  oy = "auto" || oy = "scroll"

let scroller () =
  if truthy (field global_window "getComputedStyle") then
    let outlets = query_all global_document "yuka-outlet" in
    let n = Array.length outlets in
    let rec up el =
      match Js.Null.toOption el with
      | Some e when el != document_body && e != document_element -> if scrolls e then el else up (parent_element_null e)
      | _ -> Js.null
    in
    if n > 0 then up (parent_element_null (Array.unsafe_get outlets (n - 1))) else Js.null
  else Js.null

let scroll_y () =
  match Js.Null.toOption (scroller ()) with
  | Some el -> or_zero (scroll_top el)
  | None -> or_zero window_scroll_y

let scroll_to y =
  match Js.Null.toOption (scroller ()) with Some el -> set_scroll_top el y | None -> window_scroll_to 0. y

let scroll_box_to y = match Js.Null.toOption (scroller ()) with Some el -> set_scroll_top el y | None -> ()

external set_document_cookie : node -> string -> unit = "cookie" [@@mel.set]

let set_cookie cookie = set_document_cookie global_document cookie

external history_back : unit -> unit = "back" [@@mel.scope "window", "history"]

let history_replace_url url = replace_state history_state "" url

external window_history : node = "history" [@@mel.scope "window"]
external set_scroll_restoration : node -> string -> unit = "scrollRestoration" [@@mel.set]

let scroll_restoration mode = try set_scroll_restoration window_history mode with _ -> ()

external persisted_field : event -> bool Js.undefined = "persisted" [@@mel.get]

let persisted e = persisted_field e == Js.Undefined.return true

external default_prevented : event -> bool = "defaultPrevented" [@@mel.get]

let plain_click e =
  not (default_prevented e || button e <> 0 || meta_key e || ctrl_key e || shift_key e || alt_key e)

external yuka_base : node -> string option = "__yukaBase" [@@mel.get] [@@mel.return undefined_to_opt]
external meta_content : node -> string = "content" [@@mel.get]

let base () =
  match yuka_base global_document with
  | Some b -> b
  | None ->
      let b =
        match query_selector global_document {|meta[name="yuka-base"]|} with
        | Some m -> meta_content m
        | None -> ""
      in
      set_string global_document "__yukaBase" b;
      b

external anchor_origin : node -> string = "origin" [@@mel.get]
external anchor_pathname : node -> string = "pathname" [@@mel.get]
external anchor_search : node -> string = "search" [@@mel.get]
external anchor_hash : node -> string = "hash" [@@mel.get]
external anchor_href : node -> string = "href" [@@mel.get]
external starts_with : string -> string -> bool = "startsWith" [@@mel.send]

let other_target t = match Js.Null.toOption t with Some t -> t <> "" && t <> "_self" | None -> false

let is_off v = match Js.Null.toOption v with Some "off" -> true | _ -> false

let link_in prefetch t b =
  match Js.Null.toOption (if truthy t && truthy (field t "closest") then closest t "a[href]" else Js.null) with
  | None -> ""
  | Some a ->
      if
        other_target (get_attribute_null a "target")
        || has_attribute a "download"
        || has_attribute a "data-yuka-reload"
        || (prefetch && is_off (get_attribute_null a "data-yuka-prefetch"))
      then ""
      else
        let path = anchor_pathname a in
        if anchor_origin a <> location_origin || (b <> "" && path <> b && not (starts_with path (b ^ "/"))) then
          ""
        else if anchor_hash a <> "" && path = location_pathname && anchor_search a = location_search then ""
        else anchor_href a

let link_href prefetch t = link_in prefetch t (base ())

external link : node -> (_[@mel.as "a[href]"]) -> node = "closest" [@@mel.send]
external is_trusted : event -> bool = "isTrusted" [@@mel.get]
external form_prototype : node = "prototype" [@@mel.scope "HTMLFormElement"]
external is_prototype_of : node -> node -> bool = "isPrototypeOf" [@@mel.send]
external submitter_nullable : event -> node Js.nullable = "submitter" [@@mel.get]
external base_uri : string = "baseURI" [@@mel.scope "document"]
external form_data_with : node -> node Js.nullable -> form_data = "FormData" [@@mel.new]
external form_pairs : form_data -> (form_entry -> string * string[@mel.uncurry]) -> (string * string) array = "from"
[@@mel.scope "Array"]
external file_name : form_value -> string = "name" [@@mel.get]

type search_params

external search_params : (string * string) array -> search_params = "URLSearchParams" [@@mel.new]
external search_text : search_params -> string = "toString" [@@mel.send]

let form_url e =
  let f = target e and s = submitter_nullable e in
  if default_prevented e || (not (is_trusted e)) || not (is_prototype_of form_prototype f) then ""
  else
    let attr n =
      match Js.Nullable.toOption s with
      | Some s when has_attribute s ("form" ^ n) -> get_attribute_null s ("form" ^ n)
      | _ -> get_attribute_null f n
    in
    let get = match Js.Null.toOption (attr "method") with Some m when m <> "" -> lowercase m = "get" | _ -> true in
    if (not get) || other_target (attr "target") || has_attribute f "data-yuka-reload" then ""
    else
      try
        let u = new_url (match Js.Null.toOption (attr "action") with Some a -> a | None -> "") base_uri in
        if url_origin u <> location_origin then ""
        else (
          set_search u
            (search_text
               (search_params
                  (form_pairs (form_data_with f s) (fun (k, v) ->
                       (k, if Js.typeof v = "string" then form_text v else file_name v)))));
          url_href u)
      with _ -> ""

type 'a table

external table : unit -> 'a table = "Map" [@@mel.new]
external table_get : 'a table -> string -> 'a option = "get"
[@@mel.send] [@@mel.return undefined_to_opt]
external table_set : 'a table -> string -> 'a -> unit = "set" [@@mel.send]
external table_has : 'a table -> string -> bool = "has" [@@mel.send]
external table_delete : 'a table -> string -> unit = "delete" [@@mel.send]
external table_size : 'a table -> int = "size" [@@mel.get]
external table_clear : 'a table -> unit = "clear" [@@mel.send]
external session_get : string -> string Js.null = "getItem" [@@mel.scope "sessionStorage"]
external session_set : string -> string -> unit = "setItem" [@@mel.scope "sessionStorage"]
external json_parse_nullable : string Js.null -> any = "parse" [@@mel.scope "JSON"]
external json_stringify : any -> string = "stringify" [@@mel.scope "JSON"]
external filter : any -> (any -> bool[@mel.uncurry]) -> any = "filter" [@@mel.send]
external item : any -> int -> any = "" [@@mel.get_index]
external table_of : any -> 'a table = "Map" [@@mel.new]
external table_entries : 'a table -> any = "from" [@@mel.scope "Array"]
external slice_any : any -> int -> any = "slice" [@@mel.send]

type 'a iterator

external table_iterator : 'a table -> 'a iterator = "values" [@@mel.send]
external array_of_iterator : 'a iterator -> 'a array = "from" [@@mel.scope "Array"]

let stored_scrolls () =
  try
    table_of
      (filter (json_parse_nullable (session_get "yuka-scroll")) (fun e ->
           Js.typeof (item e 0) = "string" && Js.typeof (item e 1) = "number"))
  with _ -> table ()

let store_scrolls t =
  try session_set "yuka-scroll" (json_stringify (slice_any (table_entries t) (-100))) with _ -> ()

let table_values t = array_of_iterator (table_iterator t)

type ('k, 'v) keyed

external keyed_map : unit -> ('k, 'v) keyed = "Map" [@@mel.new]

let keyed _ = keyed_map ()

external keyed_get : ('k, 'v) keyed -> 'k -> 'v option = "get"
[@@mel.send] [@@mel.return undefined_to_opt]
external keyed_set : ('k, 'v) keyed -> 'k -> 'v -> unit = "set" [@@mel.send]
external keyed_size : ('k, 'v) keyed -> int = "size" [@@mel.get]
external keyed_clear : ('k, 'v) keyed -> unit = "clear" [@@mel.send]
external keyed_each : ('k, 'v) keyed -> ('v -> 'k -> unit[@mel.uncurry]) -> unit = "forEach" [@@mel.send]
external keyed_delete : ('k, 'v) keyed -> 'k -> unit = "delete" [@@mel.send]

let keyed_keep t keep = keyed_each t (fun v k -> if not (keep v) then keyed_delete t k)

external to_exponential : float -> int -> string = "toExponential" [@@mel.send]
external parse_float : string -> float = "Number"
external number_int : string -> int = "Number"
external repeat_text : string -> int -> string = "repeat" [@@mel.send]
external replace_text : string -> string -> string -> string = "replace" [@@mel.send]
external char_at : string -> int -> string = "" [@@mel.get_index]

let trim_zeros s = replace_re s [%mel.re "/0+$/"] ""

let shortest_float f =
  if f = 0. then "0"
  else
    let neg = f < 0. in
    let rec go p =
      let e = to_exponential f (p - 1) in
      if p < 17 && parse_float e <> f then go (p + 1)
      else
        let e =
          if p = 17 then
            let x = to_exponential f 99 in
            let i = index_of x "e" in
            let all = replace_text (slice x (if neg then 1 else 0) i) "." "" in
            if re_test [%mel.re "/^50*$/"] (slice_from all 17) && char_code all 16 land 1 = 0 then
              (if neg then "-" else "") ^ char_at all 0 ^ "." ^ slice all 1 17 ^ slice_from x i
            else e
          else e
        in
        let at = index_of e "e" in
        let x = number_int (slice_from e (at + 1)) in
        let d = replace_text (slice e (if neg then 1 else 0) at) "." "" in
        let s =
          if x < -4 || x >= p then
            let m = trim_zeros d and a = if x < 0 then -x else x in
            char_at m 0
            ^ (if String.length m > 1 then "." ^ slice_from m 1 else "")
            ^ "e"
            ^ (if x < 0 then "-" else "+")
            ^ (if a < 10 then "0" else "")
            ^ string_of_int a
          else if x >= 0 then
            let frac = trim_zeros (slice_from d (x + 1)) in
            slice d 0 (x + 1) ^ if frac <> "" then "." ^ frac else ""
          else "0." ^ trim_zeros (repeat_text "0" (-x - 1) ^ d)
        in
        if neg then "-" ^ s else s
    in
    go 15

let parse_int t =
  let n = parse_float t in
  let i = int_of_float n in
  if float_of_int i = n then Some i else None

type json =
  [ `Null
  | `Bool of bool
  | `Int of int
  | `Float of float
  | `String of string
  | `List of json list
  | `Assoc of (string * json) list ]

external json_parse_exn : string -> any = "parse" [@@mel.scope "JSON"]
external is_array : any -> bool = "isArray" [@@mel.scope "Array"]
external object_keys : any -> string array = "keys" [@@mel.scope "Object"]
external any_bool : any -> bool = "%identity"
external any_float : any -> float = "%identity"
external any_string : any -> string = "%identity"
external any_array : any -> any array = "%identity"

let rec json_of v d : json =
  if Js.Nullable.isNullable (Js.Nullable.return v) then `Null
  else
    match Js.typeof v with
    | "boolean" -> `Bool (any_bool v)
    | "number" ->
        let n = any_float v in
        let i = int_of_float n in
        if float_of_int i = n then `Int i else `Float n
    | "string" -> `String (any_string v)
    | _ ->
        if d > 512 then Js.Exn.raiseError "nesting too deep"
        else if is_array v then (
          let a = any_array v and l = ref [] in
          for i = Array.length a - 1 downto 0 do
            l := json_of (Array.unsafe_get a i) (d + 1) :: !l
          done;
          `List !l)
        else
          let k = object_keys v and l = ref [] in
          for i = Array.length k - 1 downto 0 do
            let key = Array.unsafe_get k i in
            l := (key, json_of (field v key) (d + 1)) :: !l
          done;
          `Assoc !l

let parse_json s =
  match json_of (json_parse_exn s) 1 with
  | v -> Ok v
  | exception Js.Exn.Error e -> Error (if truthy e then js_string (error_message e) else js_string e)

type socket
type message_event
type close_event

external web_socket : string -> socket = "WebSocket" [@@mel.new]
external set_onopen : socket -> (unit -> unit[@mel.uncurry]) -> unit = "onopen" [@@mel.set]
external set_onmessage : socket -> (message_event -> unit[@mel.uncurry]) -> unit = "onmessage" [@@mel.set]
external set_onclose : socket -> (close_event -> unit[@mel.uncurry]) -> unit = "onclose" [@@mel.set]
external message_text : message_event -> string = "data" [@@mel.get]
external close_code : close_event -> int = "code" [@@mel.get]
external socket_ready_state : socket -> int = "readyState" [@@mel.get]
external send : socket -> string -> unit = "send" [@@mel.send]
external close : socket -> int -> unit = "close" [@@mel.send]
external set_handler : socket -> string -> 'a Js.null -> unit = "" [@@mel.set_index]

let socket_open url opened message closed =
  let s = web_socket url in
  set_onopen s (fun () -> opened ());
  set_onmessage s (fun e -> if Js.typeof (field e "data") = "string" then message (message_text e));
  set_onclose s (fun e -> closed (close_code e));
  s

let socket_send s text = if socket_ready_state s = 1 then send s text

let socket_close s code =
  set_handler s "onclose" Js.null;
  set_handler s "onmessage" Js.null;
  set_handler s "onopen" Js.null;
  close s code

let live_url () = (if location_protocol = "https:" then "wss://" else "ws://") ^ location_host

external navigator : any = "navigator" [@@mel.scope "window"]

let online () =
  let n = navigator in
  (not (truthy n))
  ||
  let on = field n "onLine" in
  not (Js.typeof on = "boolean" && not (truthy on))

let on_online f =
  let handler _ = f () in
  add_listener global_window "online" handler;
  fun () -> remove_listener global_window "online" handler

external random : unit -> float = "random" [@@mel.scope "Math"]

let nonce () = slice_from (js_string (random ())) 2

let fetch_text url ok fail =
  catch
    (then_promise (fetch_exn url [%mel.obj { credentials = "same-origin" }]) (fun r -> then_ (text r) (fun t -> ok (status r) t)))
    (fun e -> fail (message e))

type sheets

external new_sheets : unit -> sheets = "Set" [@@mel.new]
external sheets_add : sheets -> string Js.null -> unit = "add" [@@mel.send]
external sheets_has : sheets -> string -> bool = "has" [@@mel.send]
external yuka_sheets : node -> sheets option = "__yukaSheets" [@@mel.get] [@@mel.return nullable]
external document_head : node = "head" [@@mel.scope "document"]

let add_stylesheet href =
  let seen =
    match yuka_sheets global_document with
    | Some s -> s
    | None ->
        let s = new_sheets () in
        set_prop global_document "__yukaSheets" s;
        Array.iter (fun l -> sheets_add s (get_attribute_null l "href")) (query_all global_document "link[data-yuka-css]");
        s
  in
  if not (sheets_has seen href) then (
    sheets_add seen (Js.Null.return href);
    let l = create_element global_document "link" in
    set_string l "rel" "stylesheet";
    set_attribute l "href" href;
    set_attribute l "data-yuka-css" "";
    append_child document_head l)

let read_file (_ : string) : string option = None

let buffers : Stdlib.Buffer.t list ref = ref []

let take_buffer () =
  match !buffers with
  | b :: rest ->
      buffers := rest;
      Some b
  | [] -> None

let give_buffer b = buffers := b :: !buffers

type 'a local = 'a

let local f = f ()
let local_get v = v

let skip_clean (_ : string) i = i

let sub s offset len = slice s offset (offset + len)

external of_char : char -> string = "fromCharCode" [@@mel.scope "String"]

let refuse_url_name n =
  if
    n = ""
    || re_test
         [%mel.re
           {|/[\s"'>\/=<\x00-\x1f\x7f]|^on|^(href|src|action|formaction|xlink:?href|poster|cite|data|background|longdesc|manifest|codebase|icon|srcdoc)$/i|}]
         n
  then Js.Exn.raiseError ("Yuka: refused attribute name " ^ n)

let tree_digest _ = invalid_arg "Yuka.Server.tree_digest: native only"
