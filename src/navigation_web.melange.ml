open Host

type any

external create_element : node -> string -> node = "createElement" [@@mel.send]
external node_type : node -> int = "nodeType" [@@mel.get]
external local_name : node -> string = "localName" [@@mel.get]
external data : node -> string = "data" [@@mel.get]
external set_data : node -> string -> unit = "data" [@@mel.set]
external append_child : node -> node -> unit = "appendChild" [@@mel.send]
external remove : node -> unit = "remove" [@@mel.send]
external clear : node -> string -> unit = "textContent" [@@mel.set]
external set_attribute : node -> string -> string -> unit = "setAttribute" [@@mel.send]
external remove_attribute : node -> string -> unit = "removeAttribute" [@@mel.send]
external set_string : node -> string -> string -> unit = "" [@@mel.set_index]
external set_bool : node -> string -> bool -> unit = "" [@@mel.set_index]
external set_prop : node -> string -> 'a -> unit = "" [@@mel.set_index]
external query_all : node -> string -> node array = "querySelectorAll" [@@mel.send]
external text_content : node -> string = "textContent" [@@mel.get]
external set_inner_html : node -> string -> unit = "innerHTML" [@@mel.set]
external content : node -> node = "content" [@@mel.get]
external contains : node -> node -> bool = "contains" [@@mel.send]
external lowercase : string -> string = "toLowerCase" [@@mel.send]

external global_document : node = "document"
external global_window : node = "window"
external global_this : node = "globalThis"
external navigator : any = "navigator" [@@mel.scope "window"]
external field : 'o -> string -> any = "" [@@mel.get_index]
external truthy : 'a -> bool = "Boolean"
external push : 'a array -> 'a -> unit = "push" [@@mel.send]
external join : string array -> string -> string = "join" [@@mel.send]
external split : string -> string -> string array = "split" [@@mel.send]
external index_of : string -> string -> int = "indexOf" [@@mel.send]
external slice : string -> int -> int -> string = "slice" [@@mel.send]
external slice_from : string -> int -> string = "slice" [@@mel.send]
external starts_with : string -> string -> bool = "startsWith" [@@mel.send]
external replace_re : string -> Js.Re.t -> string -> string = "replace" [@@mel.send]
external re_test : Js.Re.t -> string -> bool = "test" [@@mel.send]
external re_exec : Js.Re.t -> string -> string array Js.null = "exec" [@@mel.send]
external number : string -> float = "Number"
external number_int : string -> int = "Number"
external char_at : string -> int -> string = "" [@@mel.get_index]
external trim : string -> string = "trim" [@@mel.send]
external date_now : unit -> float = "now" [@@mel.scope "Date"]
external document_title : node -> string = "title" [@@mel.get]
external set_document_title : node -> string -> unit = "title" [@@mel.set]
external document_body : node = "body" [@@mel.scope "document"]
external document_body_null : node Js.null = "body" [@@mel.scope "document"]
external document_head : node = "head" [@@mel.scope "document"]
external document_element : node = "documentElement" [@@mel.scope "document"]
external document_hidden : bool = "hidden" [@@mel.scope "document"]
external active_element : node Js.null = "activeElement" [@@mel.scope "document"]
external location_href : string = "href" [@@mel.scope "window", "location"]
external location_origin : string = "origin" [@@mel.scope "window", "location"]
external query_selector : node -> string -> node Js.null = "querySelector" [@@mel.send]
external get_attribute_null : node -> string -> string Js.null = "getAttribute" [@@mel.send]
external has_attribute : node -> string -> bool = "hasAttribute" [@@mel.send]
external parent_node_null : node -> node Js.null = "parentNode" [@@mel.get]
external parent_of : node -> node = "parentNode" [@@mel.get]
external parent_element_null : node -> node Js.null = "parentElement" [@@mel.get]
external next_sibling_null : node -> node Js.null = "nextSibling" [@@mel.get]
external insert_before_null : node -> node -> node Js.null -> unit = "insertBefore" [@@mel.send]
external append : node -> node -> node = "appendChild" [@@mel.send]
external create_fragment : node -> node = "createDocumentFragment" [@@mel.send]
external inner_html : node -> string = "innerHTML" [@@mel.get]
external set_text_content : node -> string -> unit = "textContent" [@@mel.set]
external is_connected : node -> bool = "isConnected" [@@mel.get]
external focus_with : node -> < .. > Js.t -> unit = "focus" [@@mel.send]
external scroll_into_view : node -> unit = "scrollIntoView" [@@mel.send]
external matches : node -> string -> bool = "matches" [@@mel.send]
external tab_index : node -> int = "tabIndex" [@@mel.get]
external tag_name : node -> string = "tagName" [@@mel.get]
external element_id : node -> string = "id" [@@mel.get]
external children : node -> node array = "children" [@@mel.get]
external child_element : node array -> int -> node Js.undefined = "" [@@mel.get_index]
external replace_state : < .. > Js.t -> string -> string -> unit = "replaceState" [@@mel.scope "window", "history"]

let throw : Js.Exn.t -> unit = [%mel.raw "function (e) { throw e }"]
let set_title t = set_document_title global_document t
let title () = document_title global_document

let active () =
  match Js.Null.toOption active_element with Some a -> a | None -> document_body

let refocus n = focus_with n [%mel.obj { preventScroll = true }]

let route_script () =
  match Js.Null.toOption (query_selector global_document {|script[data-yuka-context="route"]|}) with
  | Some s -> (
      match Js.Null.toOption (parent_node_null s) with Some p -> Some (s, p) | None -> None)
  | None -> None

let put_back (s, p) =
  set_bool s "__yuka_seen" false;
  append_child p s

let layer () =
  match Js.Null.toOption (query_selector global_document "yuka-overlay") with
  | Some o -> o
  | None -> append document_body (create_element global_document "yuka-overlay")

type controller

let scroll_to = Host.scroll_to

let decoded_id hash =
  let id = slice_from hash 1 in
  match decode_uri id with Some d -> d | None -> id

let scroll_to_hash hash =
  let id = decoded_id hash in
  match if id <> "" then Web.DOM.Document.getElementById id Web.DOM.document else None with
  | Some el -> scroll_into_view el
  | None -> scroll_to 0.

type signal
type response
type response_headers
type reader
type chunk
type decoder
type bytes
type url

external new_controller : unit -> controller = "AbortController" [@@mel.new]
external abort : controller -> unit = "abort" [@@mel.send]
external signal : controller -> signal = "signal" [@@mel.get]
external aborted : signal -> bool = "aborted" [@@mel.get]
external fetch_exn : string -> < .. > Js.t -> response promise = "fetch"
external set_entry : 'o -> string -> string -> unit = "" [@@mel.set_index]
external response_url : response -> string = "url" [@@mel.get]
external response_status : response -> int = "status" [@@mel.get]
external response_headers : response -> response_headers = "headers" [@@mel.get]
external headers_get : response_headers -> string -> string Js.null = "get" [@@mel.send]
external response_text : response -> string promise = "text" [@@mel.send]
external response_body : response -> any = "body" [@@mel.get]
external get_reader : any -> reader = "getReader" [@@mel.send]
external read : reader -> chunk promise = "read" [@@mel.send]
external cancel : reader -> unit promise = "cancel" [@@mel.send]
external chunk_value : chunk -> bytes = "value" [@@mel.get]
external chunk_done : chunk -> bool = "done" [@@mel.get]
external text_decoder : unit -> decoder = "TextDecoder" [@@mel.new]
external decode : decoder -> bytes -> < .. > Js.t -> string = "decode" [@@mel.send]
external parse_text : string -> string = "parse" [@@mel.scope "JSON"]
external parse_part : string -> string array = "parse" [@@mel.scope "JSON"]
external new_url : string -> string -> url = "URL" [@@mel.new]
external url_origin : url -> string = "origin" [@@mel.get]
external url_pathname : url -> string = "pathname" [@@mel.get]
external url_search : url -> string = "search" [@@mel.get]
external url_hash : url -> string = "hash" [@@mel.get]
external url_href : url -> string = "href" [@@mel.get]
external set_url_hash : url -> string -> unit = "hash" [@@mel.set]
external then_ : 'a promise -> ('a -> 'b[@mel.uncurry]) -> 'b promise = "then" [@@mel.send]
external then_step : 'a promise -> ('a -> unit promise Js.undefined[@mel.uncurry]) -> unit promise = "then"
[@@mel.send]
external then_reject : unit promise -> (_[@mel.as {json|null|json}]) -> (any -> unit[@mel.uncurry]) -> unit = "then"
[@@mel.send]
external call5 :
  (string -> int -> (string -> string option) -> string -> bool -> unit) ->
  (_[@mel.as {json|null|json}]) ->
  string ->
  int ->
  (string -> string option) ->
  string ->
  bool ->
  unit = "call"
[@@mel.send]
external catch_any : unit promise -> (any -> unit[@mel.uncurry]) -> unit = "catch" [@@mel.send]

let fetch_page (url, keys, prefetch, low, controller, overlay) ok part ended fail =
  let signal = signal controller in
  let headers = [%mel.obj { yuka_navigate = keys [@mel.as "Yuka-Navigate"] }] in
  let init = [%mel.obj { headers; credentials = "same-origin"; signal }] in
  if overlay then set_entry headers "Yuka-Overlay" "1";
  if prefetch <> "" then (
    set_entry headers "Yuka-Prefetch" prefetch;
    set_entry init "cache" "no-store");
  if low then set_entry init "priority" "low";
  let shown = ref false in
  let broke _ = if !shown then ended false else if not (aborted signal) then fail () in
  match fetch_exn url init with
  | exception _ -> fail ()
  | request ->
      then_reject
        (then_step request (fun r ->
             let base = location_href in
             let u = field r "url" in
             let target = new_url (if Js.typeof u = "string" && truthy u then response_url r else url) base in
             let header name =
               let h = field r "headers" in
               if truthy h && truthy (field h "get") then
                 match Js.Null.toOption (headers_get (response_headers r) name) with Some v -> Some v | None -> None
               else None
             in
             let show text streamed =
               if aborted signal then false
               else if url_origin target <> location_origin then (
                 fail ();
                 false)
               else (
                 shown := true;
                 let hash = url_hash target in
                 call5 ok
                   (url_pathname target ^ url_search target ^ if hash <> "" then hash else url_hash (new_url url base))
                   (response_status r) header text streamed;
                 true)
             in
             if (match header "yuka-stream" with None | Some "" -> true | Some _ -> false)
                || not (truthy (response_body r))
             then Js.Undefined.return (then_ (response_text r) (fun text -> ignore (show text false)))
             else
               let reader = get_reader (response_body r) and decoder = text_decoder () in
               let buffer = ref "" and complete = ref false in
               let rec step x =
                 buffer := !buffer ^ decode decoder (chunk_value x) [%mel.obj { stream = not (chunk_done x) }];
                 let rec drain () =
                   let i = index_of !buffer "\n" in
                   if i < 0 then true
                   else
                     let line = slice !buffer 0 i in
                     if not !shown then (
                       let v = parse_text line in
                       buffer := slice_from !buffer (i + 1);
                       if show v true then drain ()
                       else (
                         catch_any (cancel reader) (fun _ -> ());
                         false))
                     else
                       let v = parse_part line in
                       buffer := slice_from !buffer (i + 1);
                       if Array.length v > 0 then part (Array.unsafe_get v 0) (Array.unsafe_get v 1)
                       else complete := true;
                       drain ()
                 in
                 if not (drain ()) then Js.undefined
                 else if not (chunk_done x) then Js.Undefined.return (then_step (read reader) step)
                 else (
                   if !shown then ended !complete else fail ();
                   Js.undefined)
               in
               Js.Undefined.return (then_step (read reader) step)))
        broke

type walker

external create_tree_walker : node -> node -> int -> walker = "createTreeWalker" [@@mel.send]
external create_tree_walker_with : node -> node -> int -> (node -> int[@mel.uncurry]) -> walker = "createTreeWalker"
[@@mel.send]
external next_node : walker -> node Js.null = "nextNode" [@@mel.send]

external body_field : node -> node Js.nullable = "body" [@@mel.get]

let body_of root = match Js.Nullable.toOption (body_field root) with Some b -> b | None -> root

let put root id html =
  let t = create_element global_document "template" and g = create_fragment global_document in
  let root = body_of root in
  set_inner_html t html;
  if id = "" then (
    append_child root (content t);
    g)
  else (
    (match Js.Null.toOption (query_selector root ({|template[data-yuka-failed="|} ^ id ^ {|"]|})) with
    | Some b -> remove b
    | None -> ());
    let w = create_tree_walker global_document root 128 in
    let rec find () =
      let c = next_node w in
      match Js.Null.toOption c with Some n when data n <> "[" ^ id -> find () | _ -> c
    in
    match Js.Null.toOption (find ()) with
    | None -> g
    | Some c ->
        let k = ref 1 in
        let closes n =
          node_type n = 8
          &&
          if char_at (data n) 0 = "[" then (
            incr k;
            !k = 0)
          else
            data n = "]"
            &&
            (decr k;
             !k = 0)
        in
        let rec collect () =
          let n = next_sibling_null c in
          match Js.Null.toOption n with
          | Some m when not (closes m) ->
              append_child g m;
              collect ()
          | _ -> n
        in
        let n = collect () in
        insert_before_null (parent_of c) (content t) n;
        set_data c "[";
        g)

external attribute_text : node -> string -> string = "getAttribute" [@@mel.send]
external array_map : node array -> (node -> 'b[@mel.uncurry]) -> 'b array = "from" [@@mel.scope "Array"]

let failed_views root =
  array_map (query_all (body_of root) "template[data-yuka-failed]") (fun t ->
      (attribute_text t "data-yuka-failed", inner_html t))

type 'a iterator

external match_all : string -> Js.Re.t -> string array iterator = "matchAll" [@@mel.send]
external array_of_iterator : 'a iterator -> 'a array = "from" [@@mel.scope "Array"]

let fail_values root =
  let root = body_of root in
  let scripts = query_all root {|script[type="application/json"]|} in
  for i = 0 to Array.length scripts - 1 do
    let found = array_of_iterator (match_all (text_content (Array.unsafe_get scripts i)) [%mel.re {|/"\$async":"([^"\\]*)"\}/g|}]) in
    for j = 0 to Array.length found - 1 do
      let name = Array.unsafe_get (Array.unsafe_get found j) 1 in
      if not (truthy (query_selector global_document ({|script[data-yuka-async="|} ^ name ^ {|"]|}))) then (
        let e = create_element global_document "script" in
        set_string e "type" "application/json";
        set_attribute e "data-yuka-async" name;
        clear e {|{"error":"broken"}|};
        append_child root e)
    done
  done

external held : node -> int Js.undefined = "__yukaHeld" [@@mel.get]

let pending island =
  let w =
    create_tree_walker_with global_document island 129 (fun n ->
        if node_type n = 8 then 1 else if local_name n = "yuka-island" then 2 else 3)
  in
  let rec scan () =
    match Js.Null.toOption (next_node w) with
    | Some c -> (char_at (data c) 0 = "[" && String.length (data c) > 2) || scan ()
    | None -> false
  in
  scan ()

let hold root owner release =
  let islands = query_all (body_of root) "yuka-island" in
  for j = 0 to Array.length islands - 1 do
    let i = Array.unsafe_get islands j in
    if held i == Js.Undefined.return owner then (
      if release || not (pending i) then (
        set_prop i "__yukaHeld" Js.undefined;
        set_prop i "__yuka_started" Js.undefined))
    else if (not release) && (not (truthy (field i "__yuka_started"))) && pending i then (
      set_prop i "__yukaHeld" owner;
      set_bool i "__yuka_started" true)
  done

let hash_of u =
  let i = index_of u "#" in
  if i < 0 then "" else slice_from u i

let no_hash u = Array.unsafe_get (split u "#") 0
let replace_entry k url = replace_state [%mel.obj { yukaKey = k; yukaAt = history_at () }] "" url
let path_of u = Array.unsafe_get (split (no_hash u) "?") 0

let keys () =
  let out = [||] and outlets = query_all global_document "yuka-outlet" in
  for i = 0 to Array.length outlets - 1 do
    match Js.Null.toOption (get_attribute_null (Array.unsafe_get outlets i) "data-k") with
    | Some k -> push out k
    | None -> ()
  done;
  if Array.length out > 0 then join out " " else "-"

let is_html t = starts_with (lowercase t) "text/html"

external event_type : event -> string = "type" [@@mel.get]


let absolute u =
  let x = new_url u location_href in
  set_url_hash x "";
  url_href x

let max_age v =
  let m = re_exec [%mel.re {|/(?:^|,)\s*max-age=(\d+)/|}] v in
  if re_test [%mel.re {|/(?:^|,)\s*no-(?:store|cache)\s*(?:,|$)/|}] v then 0
  else match Js.Null.toOption m with Some m -> number_int (Array.unsafe_get m 1) | None -> 0

let key_before a b =
  let x = split a "-" and y = split b "-" in
  let at s i = number (Array.unsafe_get s i) in
  at x 0 < at y 0 || (at x 0 = at y 0 && at x 1 < at y 1)

let now = date_now
let after = set_timeout

let save_data () =
  let c = field navigator "connection" in
  truthy c && truthy (field c "saveData")

external effective_type : any -> string Js.undefined = "effectiveType" [@@mel.get]

let hidden_or_slow () =
  let c = field navigator "connection" in
  let slow = truthy c && match Js.Undefined.toOption (effective_type c) with Some ("2g" | "slow-2g") -> true | _ -> false in
  document_hidden || slow

let on_visible f =
  let h _ = if not document_hidden then f () in
  Web.DOM.EventTarget.addEventListener "visibilitychange" h Web.DOM.document;
  fun () -> Web.DOM.EventTarget.removeEventListener "visibilitychange" h Web.DOM.document

let input_names = [| "wheel"; "touchstart"; "keydown"; "pointerdown" |]

let on_input f =
  let o = Web.DOM.EventTarget.options ~capture:true ~passive:true () in
  let rec off () =
    Array.iter (fun n -> Web.DOM.Window.removeEventListenerWithOptions n h o Web.DOM.window) input_names
  and h _ =
    off ();
    f ()
  in
  Array.iter (fun n -> Web.DOM.Window.addEventListenerWithOptions n h o Web.DOM.window) input_names;
  off

type observer
type entry
type rect

external intersection_observer : (entry array -> unit[@mel.uncurry]) -> < .. > Js.t -> observer = "IntersectionObserver"
[@@mel.new] [@@mel.scope "window"]
external intersection_observer_plain : (entry array -> unit[@mel.uncurry]) -> observer = "IntersectionObserver"
[@@mel.new] [@@mel.scope "window"]
external observe_node : observer -> node -> unit = "observe" [@@mel.send]
external unobserve : observer -> node -> unit = "unobserve" [@@mel.send]
external disconnect : observer -> unit = "disconnect" [@@mel.send]
external entry_target : entry -> node = "target" [@@mel.get]
external is_intersecting : entry -> bool = "isIntersecting" [@@mel.get]
external bounding_rect : entry -> rect = "boundingClientRect" [@@mel.get]
external rect_left : rect -> float = "left" [@@mel.get]
external rect_top : rect -> float = "top" [@@mel.get]
external rect_width : rect -> float = "width" [@@mel.get]
external rect_height : rect -> float = "height" [@@mel.get]

let has_observer () = Js.typeof (field global_window "IntersectionObserver") = "function"

let observe els f =
  if not (has_observer ()) then fun () -> ()
  else
    let self = ref Js.null in
    let observer =
      intersection_observer
        (fun entries ->
          for i = 0 to Array.length entries - 1 do
            let e = Array.unsafe_get entries i in
            let t = entry_target e in
            f t (is_intersecting e) (fun () ->
                match Js.Null.toOption !self with Some o -> unobserve o t | None -> ())
          done)
        [%mel.obj { rootMargin = "200px" }]
    in
    self := Js.Null.return observer;
    for i = 0 to Array.length els - 1 do
      observe_node observer (Array.unsafe_get els i)
    done;
    fun () -> disconnect observer

type link = { el : node; h : string; r : rect }

external check_visibility : node -> < .. > Js.t -> bool = "checkVisibility" [@@mel.send]
external some : 'a array -> ('a -> bool[@mel.uncurry]) -> bool = "some" [@@mel.send]
external hypot : float -> float -> float = "hypot" [@@mel.scope "Math"]
external abs_float : float -> float = "abs" [@@mel.scope "Math"]
external max_float : float -> float -> float = "max" [@@mel.scope "Math"]

let trajectory href go =
  if not (has_observer ()) then fun () -> ()
  else
    let last = ref neg_infinity and k = ref 0 and px = ref 0. and py = ref 0. and vx = ref 0. and vy = ref 0. in
    let was = ref "" and links = ref [||] and at = ref neg_infinity and o = ref Js.null in
    let reset _ =
      links := [||];
      at := neg_infinity
    in
    let shown = [%mel.obj { opacityProperty = true; visibilityProperty = true }] in
    let stop () =
      (match Js.Null.toOption !o with Some x -> disconnect x | None -> ());
      o := Js.null
    in
    let refresh () =
      stop ();
      let els = query_all global_document "a[href]" and found = [||] in
      let left = ref (Array.length els) in
      at := date_now ();
      if !left = 0 then links := found
      else
        let self = ref Js.null in
        let mine =
          intersection_observer_plain
            (fun entries ->
              for i = 0 to Array.length entries - 1 do
                let e = Array.unsafe_get entries i in
                let t = entry_target e in
                let h =
                  if is_intersecting e && not (truthy (field t "checkVisibility") && not (check_visibility t shown))
                  then href t
                  else ""
                in
                if h <> "" then push found { el = t; h; r = bounding_rect e }
              done;
              left := !left - Array.length entries;
              if !left <= 0 then (
                (match Js.Null.toOption !self with Some m -> disconnect m | None -> ());
                o := Js.null;
                links := found))
        in
        self := Js.Null.return mine;
        o := Js.Null.return mine;
        for i = 0 to Array.length els - 1 do
          observe_node mine (Array.unsafe_get els i)
        done
    in
    let move e =
      let t = Web.DOM.Event.timeStamp e in
      let gap = t -. !last in
      if Web.DOM.PointerEvent.pointerType e = "mouse" && gap >= 50. then (
        last := t;
        let x = Web.DOM.MouseEvent.clientX e and y = Web.DOM.MouseEvent.clientY e and now = date_now () in
        if
          ((match Js.Null.toOption !o with None -> true | Some _ -> false) || now -. !at > 1000.)
          && (now -. !at > 300. || some !links (fun l -> not (is_connected l.el)))
        then refresh ();
        if gap > 200. then (
          px := x;
          py := y;
          vx := 0.;
          vy := 0.;
          k := 0;
          was := "")
        else (
          incr k;
          let a = if !k > 2 then 0.6 else 0.3 in
          vx := (a *. !vx) +. ((1. -. a) *. (x -. !px) /. gap);
          vy := (a *. !vy) +. ((1. -. a) *. (y -. !py) /. gap);
          px := x;
          py := y;
          let s = hypot !vx !vy in
          let best = ref "" and low = ref 500. in
          if s >= 0.12 then
            Array.iter
              (fun l ->
                let r = l.r in
                let cx = rect_left r +. (rect_width r /. 2.) -. x and cy = rect_top r +. (rect_height r /. 2.) -. y in
                let along = ((cx *. !vx) +. (cy *. !vy)) /. s
                and perp = abs_float ((cx *. !vy) -. (cy *. !vx)) /. s
                and dist = hypot cx cy in
                if
                  not
                    (along < 0.
                    || perp
                       > ((max_float (rect_width r) (rect_height r) /. 2.) +. 30.)
                         *. max_float 0.2 (1. -. (dist /. 1000.))
                         +. 20.)
                then
                  if along +. (perp *. 5.) < !low then (
                    low := along +. (perp *. 5.);
                    best := l.h))
              !links;
          if !best <> "" && !best = !was then go !best;
          was := !best))
    in
    Web.DOM.EventTarget.(addEventListenerWithOptions "pointermove" move (options ~passive:true ()) Web.DOM.document);
    Web.DOM.(Window.addEventListenerWithOptions "scroll" reset (EventTarget.options ~capture:true ~passive:true ()) window);
    fun () ->
      stop ();
      Web.DOM.EventTarget.removeEventListener "pointermove" move Web.DOM.document;
      Web.DOM.(Window.removeEventListenerWithOptions "scroll" reset (EventTarget.options ~capture:true ()) window)

type 'a set

external new_set : unit -> 'a set = "Set" [@@mel.new]
external set_add : 'a set -> 'a -> unit = "add" [@@mel.send]
external set_has : 'a set -> 'a -> bool = "has" [@@mel.send]
external warm_set : node -> string set Js.nullable = "__yukaWarm" [@@mel.get]
external link_href : node -> string = "href" [@@mel.get]
external match_groups : string -> Js.Re.t -> string Js.undefined array iterator = "matchAll" [@@mel.send]
external new_url_at : string -> url = "URL" [@@mel.new]
external new_url_in : string -> url -> url = "URL" [@@mel.new]

let warm final text =
  let seen =
    match Js.Nullable.toOption (warm_set global_document) with
    | Some s -> s
    | None ->
        let s = new_set () in
        set_prop global_document "__yukaWarm" s;
        s
  in
  let base = new_url_at (location_origin ^ final) in
  let present = query_all global_document "link[href]" in
  for i = 0 to Array.length present - 1 do
    set_add seen (link_href (Array.unsafe_get present i))
  done;
  let found =
    array_of_iterator
      (match_groups text
         [%mel.re {|/<link rel="(?:modulepreload" href="([^"]*)">|stylesheet" href="([^"]*)" data-yuka-css>)/g|}])
  in
  for i = 0 to Array.length found - 1 do
    let m = Array.unsafe_get found i in
    let module_href = Js.Undefined.toOption (Array.unsafe_get m 1) in
    let raw =
      match module_href with
      | Some h -> h
      | None -> ( match Js.Undefined.toOption (Array.unsafe_get m 2) with Some h -> h | None -> "")
    in
    let unescaped =
      replace_re
        (replace_re (replace_re raw [%mel.re "/&lt;/g"] "<") [%mel.re "/&quot;/g"] {|"|})
        [%mel.re "/&amp;/g"] "&"
    in
    match new_url_in unescaped base with
    | exception _ -> ()
    | u ->
        let href = url_href u in
        if not (set_has seen href) then (
          set_add seen href;
          let l = create_element global_document "link" in
          set_string l "rel" (match module_href with None -> "prefetch" | Some _ -> "modulepreload");
          set_string l "href" href;
          append_child document_head l)
  done

type transition

external start_view_transition : node -> (unit -> unit[@mel.uncurry]) -> transition = "startViewTransition"
[@@mel.send]
external ready : transition -> unit promise = "ready" [@@mel.get]
external finished : transition -> unit promise = "finished" [@@mel.get]
external then_both : unit promise -> (any -> unit[@mel.uncurry]) -> (any -> unit[@mel.uncurry]) -> unit = "then"
[@@mel.send]
external default_view : node -> node = "defaultView" [@@mel.get]
external view_set_timeout : node -> (unit -> unit[@mel.uncurry]) -> unit = "setTimeout" [@@mel.send]
external transition_id : node -> int Js.undefined = "__yukaTransition" [@@mel.get]

let transition dir f =
  if Js.typeof (field global_document "startViewTransition") <> "function" then f ()
  else
    let h = document_element in
    let id = (match Js.Undefined.toOption (transition_id global_this) with Some n -> n | None -> 0) + 1 in
    set_prop global_this "__yukaTransition" id;
    set_attribute h "data-yuka-nav" dir;
    let finish _ = if transition_id global_this == Js.Undefined.return id then remove_attribute h "data-yuka-nav" in
    let t =
      start_view_transition global_document (fun () ->
          try f () with
          | Js.Exn.Error e -> view_set_timeout (default_view global_document) (fun () -> throw e)
          | e -> view_set_timeout (default_view global_document) (fun () -> raise e))
    in
    then_reject (ready t) (fun _ -> ());
    then_both (finished t) finish finish

type parser

external dom_parser : unit -> parser = "DOMParser" [@@mel.new] [@@mel.scope "document", "defaultView"]
external parse_html : parser -> string -> (_[@mel.as "text/html"]) -> node = "parseFromString" [@@mel.send]
external body_node : node -> node = "body" [@@mel.get]

(* Keeps the body element and replaces its children: the router follows a streamed full page into
   the body element it held before the swap. *)
let swap_page text =
  let parsed = parse_html (dom_parser ()) text in
  set_document_title global_document (document_title parsed);
  set_inner_html document_body (inner_html (body_node parsed))

let adopt_stylesheets () =
  if truthy document_body_null then (
    let head = document_head and seen = new_set () in
    let kept = query_all head "link[data-yuka-css]" in
    for i = 0 to Array.length kept - 1 do
      set_add seen (get_attribute_null (Array.unsafe_get kept i) "href")
    done;
    let moved = query_all document_body "link[data-yuka-css]" in
    for i = 0 to Array.length moved - 1 do
      let l = Array.unsafe_get moved i in
      let href = get_attribute_null l "href" in
      if set_has seen href then remove l
      else (
        set_add seen href;
        append_child head l)
    done;
    set_prop global_document "__yukaSheets" seen)

external yuka_live : node -> node Js.nullable = "__yukaLive" [@@mel.get]
external style : node -> node = "style" [@@mel.get]
external set_css_text : node -> string -> unit = "cssText" [@@mel.set]

let live () =
  let r =
    match Js.Nullable.toOption (yuka_live global_document) with
    | Some r -> r
    | None ->
        let r = create_element global_document "div" in
        set_prop global_document "__yukaLive" r;
        set_string r "id" "yuka-announcer";
        set_attribute r "aria-live" "assertive";
        set_attribute r "aria-atomic" "true";
        set_css_text (style r)
          "position:absolute;top:0;width:1px;height:1px;overflow:hidden;clip-path:inset(50%);white-space:nowrap";
        r
  in
  if not (is_connected r) then
    match Js.Null.toOption document_body_null with Some b -> append_child b r | None -> ()

let focus_on t =
  match Js.Null.toOption t with
  | None -> false
  | Some t ->
      let add = Js.Null.return t != document_body_null && tab_index t < 0 && not (has_attribute t "tabindex") in
      if add then set_attribute t "tabindex" "-1";
      focus_with t [%mel.obj { preventScroll = true }];
      Js.Null.return t == active_element
      ||
      (if add then remove_attribute t "tabindex";
       false)

let settle root hash say =
  let root = body_of root in
  let h = query_selector root "h1" and a = active_element in
  (if say then
     match Js.Nullable.toOption (yuka_live global_document) with
     | Some live ->
         let t = document_title global_document in
         set_text_content live
           (if t <> "" then t else match Js.Null.toOption h with Some h -> trim (text_content h) | None -> "")
     | None -> ());
  let kept =
    match Js.Null.toOption a with
    | Some a ->
        a != document_body
        && (matches a "input,textarea,select,[contenteditable]" || (a != root && contains root a))
    | None -> false
  in
  if not kept then
    let id = decoded_id hash in
    if
      not
        (focus_on (query_selector root "[autofocus]")
        || focus_on (if id <> "" then Js.Null.fromOption (Web.DOM.Document.getElementById id Web.DOM.document) else Js.null)
        || focus_on h
        || focus_on (Js.Null.return root))
    then
      let all = query_all root "*" in
      let rec each i = i < Array.length all && (focus_on (Js.Null.return (Array.unsafe_get all i)) || each (i + 1)) in
      ignore (each 0)

external unshift : int array -> int -> unit = "unshift" [@@mel.send]

let index_in items n =
  let rec go i = if i >= Array.length items then -1 else if Array.unsafe_get items i == n then i else go (i + 1) in
  go 0

let hold_focus () =
  match Js.Null.toOption active_element with
  | Some a when a != document_body ->
      let p = [||] in
      let rec up n =
        match Js.Null.toOption (parent_element_null n) with
        | Some parent when n != document_body ->
            unshift p (index_in (children parent) n);
            up parent
        | _ -> ()
      in
      up a;
      fun () -> (
        let t =
          if is_connected a then Js.Null.return a
          else
            let id = element_id a in
            if id <> "" then Js.Null.fromOption (Web.DOM.Document.getElementById id Web.DOM.document)
            else
              let t = ref document_body_null in
              for j = 0 to Array.length p - 1 do
                t :=
                  match Js.Null.toOption !t with
                  | Some x -> (
                      match Js.Undefined.toOption (child_element (children x) (Array.unsafe_get p j)) with
                      | Some c -> Js.Null.return c
                      | None -> Js.null)
                  | None -> Js.null
              done;
              !t
        in
        match Js.Null.toOption t with
        | Some t when tag_name t = tag_name a ->
            focus_with t [%mel.obj { preventScroll = true }];
            Js.Null.return t == active_element
        | _ -> false)
  | _ -> fun () -> false
