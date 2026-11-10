open Yuka

type node

let setup () : unit =
  [%mel.raw
    {|(function () {
  const { JSDOM } = require("jsdom");
  const dom = new JSDOM("<!doctype html><html><body></body></html>", { runScripts: "outside-only" });
  globalThis.window = dom.window;
  globalThis.document = dom.window.document;
})()|}]

let document () : node = [%mel.raw "document"]
let body () : node = [%mel.raw "document.body"]
let event : string -> node =
  [%mel.raw "function (name) { return new window.Event(name, { bubbles: true }) }"]

let nonbubbling : string -> node =
  [%mel.raw "function (name) { return new window.Event(name, { bubbles: false }) }"]

external create : node -> string -> node = "createElement" [@@mel.send]
external append : node -> node -> unit = "appendChild" [@@mel.send]
external set_html : node -> string -> unit = "innerHTML" [@@mel.set]
external html : node -> string = "innerHTML" [@@mel.get]
external query : node -> string -> node = "querySelector" [@@mel.send]
external query_all : node -> string -> node array = "querySelectorAll" [@@mel.send]
external click : node -> unit = "click" [@@mel.send]
external dispatch : node -> node -> unit = "dispatchEvent" [@@mel.send]
external value : node -> string = "value" [@@mel.get]
external set_value : node -> string -> unit = "value" [@@mel.set]
external set_selected : node -> bool -> unit = "selected" [@@mel.set]
external selected : node -> bool = "selected" [@@mel.get]
external checked : node -> bool = "checked" [@@mel.get]
external get_attribute : node -> string -> string option = "getAttribute"
[@@mel.send] [@@mel.return nullable]
external first_child : node -> node = "firstChild" [@@mel.get]
external child_nodes : node -> node array = "childNodes" [@@mel.get]
external node_type : node -> int = "nodeType" [@@mel.get]
external namespace_uri : node -> string = "namespaceURI" [@@mel.get]
external text_content : node -> string = "textContent" [@@mel.get]
external as_element : node -> Yuka.Client.container = "%identity"

let check = Cases.check
let ints = string_of_int
let same name a b = check name "same" (if a == b then "same" else "different")
let () = setup ()

let container initial =
  let c = create (document ()) "div" in
  append (body ()) c;
  set_html c initial;
  c

let server tree = Internal.render_html (fun () -> Internal.node tree)
let div attrs children = lower "div" attrs children
let span children = lower "span" [] children
let li key children = lower "li" [ attr "data-key" key ] children

let texts c sel =
  String.concat "," (Array.to_list (Array.map text_content (query_all c sel)))

let create_tree () =
  let c = container "stale" in
  let dispose =
    Yuka.Client.render (as_element c) (fun () ->
        div [ attr "class" "a" ] [ text "hello"; span [ text "x" ] ])
  in
  check "created html" {|<div class="a">hello<span>x</span></div>|} (html c);
  dispose ()

let counter () =
  let n = State.make 0 in
  let tree () =
    div []
      [
        span [ hole (fun () -> text (ints (State.get n))) ];
        lower "button" [ on "click" (fun _ -> State.update n succ) ] [ text "+" ];
      ]
  in
  (n, tree)

let hydrate_adopts () =
  let _, tree = counter () in
  let c = container (server (tree ())) in
  check "server html"
    {|<div><span>0</span><button>+</button></div>|} (html c);
  let root = first_child c in
  let button = query c "button" in
  let span_text = (child_nodes (query c "span")).(0) in
  let dispose = Yuka.Client.hydrate (as_element c) tree in
  same "root kept" root (first_child c);
  same "button kept" button (query c "button");
  same "hole text kept" span_text (child_nodes (query c "span")).(0);
  check "html unchanged"
    {|<div><span>0</span><button>+</button></div>|} (html c);
  dispose ()

let hydrate_then_click () =
  let n, tree = counter () in
  let c = container (server (tree ())) in
  let span_text = (child_nodes (query c "span")).(0) in
  let dispose = Yuka.Client.hydrate (as_element c) tree in
  click (query c "button");
  click (query c "button");
  check "state" "2" (ints (State.peek n));
  check "text" "2" (text_content (query c "span"));
  same "text node reused" span_text (child_nodes (query c "span")).(0);
  dispose ()

let render_then_click () =
  let n, tree = counter () in
  let c = container "" in
  let dispose = Yuka.Client.render (as_element c) tree in
  click (query c "button");
  check "state" "1" (ints (State.peek n));
  check "html"
    {|<div><span>1</span><button>+</button></div>|} (html c);
  dispose ()

let handler_removed_after_dispose () =
  let n, tree = counter () in
  let c = container "" in
  let dispose = Yuka.Client.render (as_element c) tree in
  click (query c "button");
  dispose ();
  click (query c "button");
  check "no call after dispose" "1" (ints (State.peek n));
  State.set n 5;
  check "hole stopped" "1" (text_content (query c "span"))

let hydrate_again_after_dispose () =
  let n, tree = counter () in
  let c = container (server (tree ())) in
  let dispose = Yuka.Client.hydrate (as_element c) tree in
  dispose ();
  let dispose = Yuka.Client.hydrate (as_element c) tree in
  click (query c "button");
  check "one call per click" "1" (ints (State.peek n));
  dispose ()

let two_handlers_in_order () =
  let calls = ref [] in
  let c = container "" in
  let dispose =
    Yuka.Client.render (as_element c) (fun () ->
        lower "button"
          [
            on "click" (fun _ -> calls := "a" :: !calls);
            on "click" (fun _ -> calls := "b" :: !calls);
          ]
          [])
  in
  click (query c "button");
  check "both, in order" "a,b" (String.concat "," (List.rev !calls));
  dispose ()

let old_handler_removed_on_hole_rerun () =
  let flag = State.make true in
  let calls = ref 0 in
  let c = container "" in
  let dispose =
    Yuka.Client.render (as_element c) (fun () ->
        hole (fun () ->
            if State.get flag then
              lower "button" [ on "click" (fun _ -> incr calls) ] []
            else span []))
  in
  let old = query c "button" in
  click old;
  check "called" "1" (ints !calls);
  State.set flag false;
  append c old;
  click old;
  check "old handler removed" "1" (ints !calls);
  dispose ()

let direct_handler () =
  let calls = ref 0 in
  let c = container "" in
  let dispose =
    Yuka.Client.render (as_element c) (fun () ->
        lower "input" [ on "focus" (fun _ -> incr calls) ] [])
  in
  let input = query c "input" in
  dispatch input (nonbubbling "focus");
  check "called" "1" (ints !calls);
  dispose ();
  dispatch input (nonbubbling "focus");
  check "removed after dispose" "1" (ints !calls)

let each_item_reads_untracked () =
  let other = State.make 0 in
  let items = State.make [ "a" ] in
  let hole_runs = ref 0 in
  let c = container "" in
  let dispose =
    Yuka.Client.render (as_element c) (fun () ->
        hole (fun () ->
            incr hole_runs;
            lower "ul" []
              [
                each ~key:Fun.id
                  (fun () -> State.get items)
                  (fun id -> li id [ text (id ^ ints (State.get other)) ]);
              ]))
  in
  check "first" "1" (ints !hole_runs);
  State.set other 1;
  check "enclosing hole did not re-run" "1" (ints !hole_runs);
  State.set items [ "a"; "b" ];
  State.set other 2;
  check "still not after an update" "1" (ints !hole_runs);
  check "items render" "a0,b1" (texts c "li");
  dispose ()

let text_hole_in_place () =
  let n = State.make "a" in
  let c = container "" in
  let dispose =
    Yuka.Client.render (as_element c) (fun () ->
        div [] [ hole (fun () -> text (State.get n)) ])
  in
  let t = (child_nodes (first_child c)).(0) in
  State.set n "b";
  check "html" "<div>b</div>" (html c);
  same "text node reused" t (child_nodes (first_child c)).(0);
  dispose ()

let hole_swaps_element () =
  let flag = State.make true in
  let c = container "" in
  let dispose =
    Yuka.Client.render (as_element c) (fun () ->
        div []
          [
            hole (fun () ->
                if State.get flag then span [ text "s" ]
                else lower "p" [] [ text "p" ]);
            text "!";
          ])
  in
  check "first" "<div><!--[--><span>s</span><!--]-->!</div>" (html c);
  State.set flag false;
  check "second" "<div><!--[--><p>p</p><!--]-->!</div>" (html c);
  State.set flag true;
  check "third" "<div><!--[--><span>s</span><!--]-->!</div>" (html c);
  dispose ()

let nested_hole_disposed () =
  let a = State.make 0 in
  let b = State.make 0 in
  let inner_runs = ref 0 in
  let c = container "" in
  let dispose =
    Yuka.Client.render (as_element c) (fun () ->
        hole (fun () ->
            ignore (State.get a);
            hole (fun () ->
                incr inner_runs;
                text (ints (State.get b)))))
  in
  check "start" "1" (ints !inner_runs);
  State.update a succ;
  check "outer rerun starts one new inner" "2" (ints !inner_runs);
  State.update b succ;
  check "only the new inner reacts" "3" (ints !inner_runs);
  check "html" "<!--[--><!--[-->1<!--]--><!--]-->" (html c);
  dispose ()

let dynamic_attributes () =
  let v = State.make "one" in
  let title = State.make (Some "t") in
  let on_ = State.make false in
  let c = container "" in
  let dispose =
    Yuka.Client.render (as_element c) (fun () ->
        lower "input"
          [
            hole_attr "value" (fun () -> Some (State.get v));
            hole_attr "title" (fun () -> State.get title);
            hole_attr "checked" (fun () -> if State.get on_ then Some "" else None);
            on "input" (fun e -> State.set v (Event.target_value e));
          ]
          [])
  in
  let input = query c "input" in
  check "value" "one" (value input);
  check "title" "t" (Option.value (get_attribute input "title") ~default:"none");
  State.set v "two";
  check "value property" "two" (value input);
  check "value is not an attribute" "none"
    (Option.value (get_attribute input "value") ~default:"none");
  State.set title None;
  check "title removed" "none"
    (Option.value (get_attribute input "title") ~default:"none");
  State.set on_ true;
  check "checked property" "true" (string_of_bool (checked input));
  set_value input "typed";
  dispatch input (event "input");
  check "event value" "typed" (State.peek v);
  dispose ()

let item_view log (id, label) =
  li id [ hole (fun () -> text label); lower "b" [] [] ]
  |> fun el ->
  Effect.run ~cleanup:(fun () -> log := ("gone " ^ id) :: !log) (fun () -> ());
  el

let order c = texts c "li"

let each_identity_default () =
  let a = ("a", "A") and b = ("b", "B") in
  let items = State.make [ a; b ] in
  let renders = ref [] in
  let c = container "" in
  let dispose =
    Yuka.Client.render (as_element c) (fun () ->
        lower "ul" []
          [
            each ~key:fst
              (fun () -> State.get items)
              (fun (k, v) ->
                renders := k :: !renders;
                li k [ text v ]);
          ])
  in
  let node k = query c ("[data-key=" ^ k ^ "]") in
  let li_a = node "a" in
  State.set items [ b; a ];
  check "same items moved, not rendered" "a,b" (String.concat "," (List.rev !renders));
  same "a kept" li_a (node "a");
  State.set items [ ("b", "B"); a ];
  check "a new tuple with equal contents renders again" "a,b,b"
    (String.concat "," (List.rev !renders));
  check "order" "B,A" (order c);
  dispose ()

let keyed_list () =
  let items = State.make [ ("a", "A"); ("b", "B"); ("c", "C"); ("d", "D") ] in
  let log = ref [] in
  let c = container "" in
  let dispose =
    Yuka.Client.render (as_element c) (fun () ->
        lower "ul" []
          [ each ~equal:( = ) ~key:fst (fun () -> State.get items) (item_view log) ])
  in
  let node k = query c ("[data-key=" ^ k ^ "]") in
  let a, b, cc, d = (node "a", node "b", node "c", node "d") in
  check "start" "A,B,C,D" (order c);
  State.set items [ ("d", "D"); ("c", "C"); ("b", "B"); ("a", "A") ];
  check "reversed" "D,C,B,A" (order c);
  same "a kept" a (node "a");
  same "b kept" b (node "b");
  same "c kept" cc (node "c");
  same "d kept" d (node "d");
  State.set items [ ("d", "D"); ("x", "X"); ("b", "B"); ("a", "A") ];
  check "removed and inserted" "D,X,B,A" (order c);
  check "removed owner disposed" "gone c" (String.concat "," !log);
  same "b still kept" b (node "b");
  State.set items [ ("d", "D"); ("x", "X"); ("b", "B2"); ("a", "A") ];
  check "value changed" "D,X,B2,A" (order c);
  same "a kept after change" a (node "a");
  same "d kept after change" d (node "d");
  check "re-render disposed old item" "gone b,gone c" (String.concat "," !log);
  State.set items [];
  check "emptied" "" (order c);
  check "all disposed" 
    "gone a,gone b,gone x,gone d,gone b,gone c"
    (String.concat "," !log);
  check "no markers" "<ul></ul>" (html c);
  State.set items [ ("a", "A") ];
  check "refilled" "A" (order c);
  dispose ()

let keyed_list_shuffle () =
  let ids = [ "a"; "b"; "c"; "d"; "e"; "f"; "g" ] in
  let items = State.make ids in
  let c = container "" in
  let dispose =
    Yuka.Client.render (as_element c) (fun () ->
        lower "ul" []
          [
            each ~key:Fun.id
              (fun () -> State.get items)
              (fun id -> li id [ text id ]);
          ])
  in
  let node k = query c ("[data-key=" ^ k ^ "]") in
  let before = List.map node ids in
  List.iter
    (fun next ->
      State.set items next;
      check "order" (String.concat "," next) (order c))
    [
      [ "c"; "a"; "g"; "b"; "f"; "e"; "d" ];
      [ "g"; "x"; "a"; "y" ];
      [ "a"; "g"; "d"; "x"; "b"; "q" ];
    ];
  same "g kept" (List.nth before 6) (node "g");
  same "a kept" (List.hd before) (node "a");
  dispose ()

let adjacent_texts_hydrate () =
  let tree () = div [] [ text "a"; text "b"; text ""; text "c"; lower "i" [] [] ] in
  let c = container (server (tree ())) in
  check "server html" "<div>a<!---->b<!---->c<i></i></div>" (html c);
  let root = first_child c in
  let a = (child_nodes root).(0) in
  let b = (child_nodes root).(2) in
  let before = Array.length (child_nodes root) in
  let dispose = Yuka.Client.hydrate (as_element c) tree in
  same "a adopted" a (child_nodes root).(0);
  same "b adopted" b (child_nodes root).(2);
  check "one empty text created" (ints (before + 1))
    (ints (Array.length (child_nodes root)));
  check "html" "<div>a<!---->b<!---->c<i></i></div>" (html c);
  let c2 = container "" in
  let dispose2 = Yuka.Client.render (as_element c2) tree in
  check "render matches hydrate" (html c) (html c2);
  check "same node count"
    (ints (Array.length (child_nodes root)))
    (ints (Array.length (child_nodes (first_child c2))));
  dispose ();
  dispose2 ()

let hydrate_server_output () =
  let n = State.make 1 in
  let items = State.make [ ("a", "A"); ("b", "B") ] in
  let tree () =
    div [ hole_attr "title" (fun () -> Some (ints (State.get n))) ]
      [
        text "x";
        text "y";
        hole (fun () -> text (ints (State.get n)));
        lower "ul" []
          [ each ~equal:( = ) ~key:fst (fun () -> State.get items) (fun (k, v) -> li k [ text v ]) ];
        lower "button" [ on "click" (fun _ -> State.update n succ) ] [ text "go" ];
      ]
  in
  let c = container (server (tree ())) in
  let server_html = html c in
  let root = first_child c in
  let ul = query c "ul" in
  let li_a = query c "[data-key=a]" in
  let li_b = query c "[data-key=b]" in
  let dispose = Yuka.Client.hydrate (as_element c) tree in
  check "html after hydrate" server_html (html c);
  same "root" root (first_child c);
  same "ul" ul (query c "ul");
  same "li a" li_a (query c "[data-key=a]");
  click (query c "button");
  check "title updated" "2" (Option.value (get_attribute root "title") ~default:"");
  State.set items [ ("b", "B"); ("c", "C"); ("a", "A") ];
  check "list updated" "B,C,A" (order c);
  same "li a moved not recreated" li_a (query c "[data-key=a]");
  same "li b kept" li_b (query c "[data-key=b]");
  dispose ()

let svg_ns = "http://www.w3.org/2000/svg"
let svg_el tag attrs children = lower tag attrs children

let svg_render () =
  let c = container "" in
  let dispose =
    Yuka.Client.render (as_element c) (fun () ->
        div []
          [
            svg_el "svg" [ attr "viewBox" "0 0 1 1" ]
              [
                svg_el "path" [ attr "d" "M0 0" ] [];
                svg_el "foreignObject" [] [ span [ text "h" ] ];
              ];
          ])
  in
  check "svg ns" svg_ns (namespace_uri (query c "svg"));
  check "path ns" svg_ns (namespace_uri (query c "path"));
  check "foreignObject ns" svg_ns (namespace_uri (query c "foreignObject"));
  check "span back to html" "http://www.w3.org/1999/xhtml"
    (namespace_uri (query c "span"));
  check "div ns" "http://www.w3.org/1999/xhtml" (namespace_uri (first_child c));
  check "attribute" "M0 0" (Option.value (get_attribute (query c "path") "d") ~default:"");
  dispose ()

let svg_hole () =
  let big = State.make false in
  let c = container "" in
  let dispose =
    Yuka.Client.render (as_element c) (fun () ->
        svg_el "svg" []
          [
            hole (fun () ->
                if State.get big then svg_el "circle" [] []
                else svg_el "rect" [] []);
          ])
  in
  check "rect ns" svg_ns (namespace_uri (query c "rect"));
  State.set big true;
  check "circle ns" svg_ns (namespace_uri (query c "circle"));
  dispose ()

let svg_hydrate () =
  let tree () =
    div [] [ svg_el "svg" [ attr "width" "1" ] [ svg_el "path" [ attr "d" "M0 0" ] [] ] ]
  in
  let c = container (server (tree ())) in
  let s = query c "svg" in
  let p = query c "path" in
  check "parsed ns" svg_ns (namespace_uri p);
  let dispose = Yuka.Client.hydrate (as_element c) tree in
  same "svg adopted" s (query c "svg");
  same "path adopted" p (query c "path");
  check "one path" "1" (ints (Array.length (query_all c "path")));
  dispose ()

let await_tree ?failed a =
  div []
    [
      text "a";
      Await.make ?failed ~async:a ~loading:(span [ text "wait" ])
        ~children:(fun n -> lower "b" [] [ text (ints n) ])
        ();
      text "b";
    ]

let await_swaps () =
  let a, resolve, _ = Async.make () in
  let c = container "" in
  let dispose = Yuka.Client.render (as_element c) (fun () -> await_tree a) in
  check "loading" "<div>a<!--[--><span>wait</span><!--]-->b</div>" (html c);
  resolve 7;
  check "settled" "<div>a<!--[--><b>7</b><!--]-->b</div>" (html c);
  dispose ()

let await_fails () =
  let a, _, fail = Async.make () in
  let c = container "" in
  let dispose =
    Yuka.Client.render (as_element c) (fun () ->
        await_tree ~failed:(fun m -> lower "i" [] [ text m ]) a)
  in
  fail "boom";
  check "failed" "<div>a<!--[--><i>boom</i><!--]-->b</div>" (html c);
  dispose ();
  let a2, _, fail2 = Async.make () in
  let c2 = container "" in
  let dispose2 = Yuka.Client.render (as_element c2) (fun () -> await_tree a2) in
  fail2 "x";
  check "no failed renderer" "<div>a<!--[--><!--]-->b</div>" (html c2);
  dispose2 ()

let await_hydrates_settled () =
  let a = Async.resolved 3 in
  let c = container (server (await_tree a)) in
  check "server html" "<div>a<!--[--><b>3</b><!--]-->b</div>" (html c);
  let root = first_child c in
  let b = query c "b" in
  let dispose = Yuka.Client.hydrate (as_element c) (fun () -> await_tree a) in
  same "root adopted" root (first_child c);
  same "settled element adopted" b (query c "b");
  check "html" "<div>a<!--[--><b>3</b><!--]-->b</div>" (html c);
  dispose ()

let await_hydrates_pending_then_settles () =
  let a, resolve, _ = Async.make () in
  let c = container (server (await_tree a)) in
  let loading = query c "span" in
  let dispose = Yuka.Client.hydrate (as_element c) (fun () -> await_tree a) in
  same "loading adopted" loading (query c "span");
  resolve 9;
  check "settled" "<div>a<!--[--><b>9</b><!--]-->b</div>" (html c);
  dispose ()

let stop_propagation_and_tag () =
  let log = ref [] in
  let add s = log := s :: !log in
  let c = container "" in
  let dispose =
    Yuka.Client.render (as_element c) (fun () ->
        div [ on "click" (fun _ -> add "outer") ]
          [
            lower "button"
              [
                on "click" (fun e ->
                    add (Event.target_tag e);
                    Event.stop_propagation e);
              ]
              [];
            lower "i" [] [];
          ])
  in
  click (query c "button");
  check "stopped" "button" (String.concat "," (List.rev !log));
  click (query c "i");
  check "bubbles when not stopped" "button,outer" (String.concat "," (List.rev !log));
  dispose ()

let modifier_event : unit -> node =
  [%mel.raw
    "function () { return new window.MouseEvent('click', { bubbles: true, shiftKey: true, altKey: false }) }"]

let active_id : unit -> string =
  [%mel.raw "function () { return document.activeElement ? document.activeElement.id : '' }"]

let stub_scroll : unit -> unit =
  [%mel.raw
    "function () { globalThis.__scrolled = ''; window.Element.prototype.scrollIntoView = function () { globalThis.__scrolled = this.id } }"]

let scrolled : unit -> string = [%mel.raw "function () { return globalThis.__scrolled }"]
let hash : unit -> string = [%mel.raw "function () { return window.location.hash }"]

let modifiers () =
  let seen = ref "" in
  let c = container "" in
  let dispose =
    Yuka.Client.render (as_element c) (fun () ->
        lower "button"
          [
            on "click" (fun e ->
                seen :=
                  string_of_bool (Event.shift_key e)
                  ^ string_of_bool (Event.alt_key e));
          ]
          [])
  in
  dispatch (query c "button") (modifier_event ());
  check "shift and alt" "truefalse" !seen;
  click (query c "button");
  check "plain click" "falsefalse" !seen;
  dispose ()

let browser_functions () =
  let c = container "" in
  let dispose =
    Yuka.Client.render (as_element c) (fun () ->
        div []
          [
            lower "input" [ attr "id" "name" ] [];
            lower "div" [ attr "id" "far" ] [];
            lower "button"
              [
                on "click" (fun _ ->
                    Browser.focus "name";
                    Browser.scroll_into_view "far";
                    Browser.focus "missing";
                    Browser.scroll_into_view "missing";
                    Browser.navigate "#went");
              ]
              [];
          ])
  in
  stub_scroll ();
  click (query c "button");
  check "focus by id" "name" (active_id ());
  check "scroll by id" "far" (scrolled ());
  check "navigate" "#went" (hash ());
  dispose ()

let textarea_hydrate () =
  let v = State.make "one" in
  let tree () =
    div []
      [
        lower "textarea" [ attr "value" "fixed" ] [];
        lower "textarea" [ hole_attr "value" (fun () -> Some (State.get v)) ] [];
      ]
  in
  let c = container (server (tree ())) in
  check "server html" "<div><textarea>fixed</textarea><textarea>one</textarea></div>" (html c);
  let areas = query_all c "textarea" in
  let texts = Array.map first_child areas in
  let dispose = Yuka.Client.hydrate (as_element c) tree in
  check "static value" "fixed" (value areas.(0));
  check "hole value" "one" (value areas.(1));
  same "text node 1 kept" texts.(0) (first_child areas.(0));
  same "text node 2 kept" texts.(1) (first_child areas.(1));
  check "one child each" "1,1"
    (String.concat "," (Array.to_list (Array.map (fun a -> ints (Array.length (child_nodes a))) areas)));
  State.set v "two";
  check "hole update" "two" (value areas.(1));
  check "static kept" "fixed" (value areas.(0));
  dispose ()

let select_hydrate () =
  let v = State.make "b" in
  let option_ k = lower "option" [ attr "value" k ] [ text (String.uppercase_ascii k) ] in
  let tree () =
    lower "select" [ hole_attr "value" (fun () -> Some (State.get v)) ]
      [ option_ "a"; option_ "b"; option_ "c" ]
  in
  let c = container (server (tree ())) in
  check "server html"
    {|<select><option value="a">A</option><option value="b" selected="">B</option><option value="c">C</option></select>|}
    (html c);
  let select = query c "select" in
  let options = query_all c "option" in
  let dispose = Yuka.Client.hydrate (as_element c) tree in
  same "select kept" select (query c "select");
  same "option kept" options.(1) (query_all c "option").(1);
  check "selected matches" "b" (value select);
  State.set v "c";
  check "update" "c" (value select);
  State.set v "a";
  check "update again" "a" (value select);
  dispose ()

let checked_property () =
  let on_ = State.make true in
  let c = container "" in
  let dispose =
    Yuka.Client.render (as_element c) (fun () ->
        lower "input"
          [
            attr "type" "checkbox";
            hole_attr "checked" (fun () -> if State.get on_ then Some "" else None);
          ]
          [])
  in
  let box = query c "input" in
  check "initial" "true" (string_of_bool (checked box));
  click box;
  check "user unchecked" "false" (string_of_bool (checked box));
  State.set on_ false;
  check "state false" "false" (string_of_bool (checked box));
  State.set on_ true;
  check "state true after the user clicked" "true" (string_of_bool (checked box));
  click box;
  State.set on_ false;
  State.set on_ true;
  check "again" "true" (string_of_bool (checked box));
  dispose ()

let selected_property () =
  let on_ = State.make true in
  let c = container "" in
  let dispose =
    Yuka.Client.render (as_element c) (fun () ->
        lower "select" []
          [
            lower "option" [ attr "value" "a" ] [ text "A" ];
            lower "option"
              [
                attr "value" "b";
                hole_attr "selected" (fun () -> if State.get on_ then Some "" else None);
              ]
              [ text "B" ];
          ])
  in
  let select = query c "select" in
  let options = query_all c "option" in
  check "initial" "b" (value select);
  set_selected options.(1) false;
  check "user chose a" "false" (string_of_bool (selected options.(1)));
  State.set on_ false;
  State.set on_ true;
  check "state true after the user chose" "true" (string_of_bool (selected options.(1)));
  check "select follows" "b" (value select);
  State.set on_ false;
  check "state false" "false" (string_of_bool (selected options.(1)));
  dispose ()

let count_templates : unit -> unit =
  [%mel.raw
    "function () { globalThis.__templates = 0; if (!document.__create) { document.__create = document.createElement; document.createElement = function (t) { if (String(t).toLowerCase() === 'template') globalThis.__templates++; return document.__create.apply(document, arguments) } } }"]

let templates_created : unit -> int = [%mel.raw "function () { return globalThis.__templates }"]
let now : unit -> float = [%mel.raw "function () { return performance.now() }"]

let row_shape =
  Template.(
    element "li"
      [ fixed "class" "r"; part_attr 0; part_attr 1 ]
      [ element "span" [] [ part 2 ]; element "b" [] [ text "x"; text "y" ] ])

let row_template = Template.make row_shape

let row ?(wrap = true) ?(template = row_template) count title =
  let title_attr = hole_attr "title" (fun () -> Some (State.get title)) in
  let click = on "click" (fun _ -> State.update count succ) in
  let count_hole = hole (fun () -> text (ints (State.get count))) in
  if wrap then
    Template.(instance template [| attribute title_attr; attribute click; child count_hole |])
  else
    lower "li"
      [ attr "class" "r"; title_attr; click ]
      [ span [ count_hole ]; lower "b" [] [ text "x"; text "y" ] ]

let template_same_output () =
  let render_row wrap =
    let c = container "" in
    let count = State.make 3 and title = State.make "t" in
    let dispose =
      Yuka.Client.render (as_element c) (fun () -> row ~wrap count title)
    in
    let out = html c in
    dispose ();
    out
  in
  check "same html" (render_row false) (render_row true);
  check "expected"
    {|<li class="r" title="t"><span>3</span><b>x<!---->y</b></li>|}
    (render_row true)

let template_works () =
  let c = container "" in
  let count = State.make 0 and title = State.make "a" in
  let dispose =
    Yuka.Client.render (as_element c) (fun () -> row count title)
  in
  let li = query c "li" in
  click li;
  click li;
  check "handler" "2" (text_content (query c "span"));
  check "hole" "2" (ints (State.peek count));
  State.set title "b";
  check "dynamic attribute" "b" (Option.value (get_attribute li "title") ~default:"");
  State.set count 9;
  check "hole update" "9" (text_content (query c "span"));
  dispose ();
  click li;
  check "handler removed after dispose" "9" (ints (State.peek count))

let template_cached () =
  count_templates ();
  let template = Template.make row_shape in
  let items = State.make [ 1; 2; 3 ] in
  let c = container "" in
  let dispose =
    Yuka.Client.render (as_element c) (fun () ->
        lower "ul" []
          [
            each ~key:ints
              (fun () -> State.get items)
              (fun i -> row ~template (State.make i) (State.make "t"));
          ])
  in
  check "three rows" "3" (ints (Array.length (query_all c "li")));
  State.set items [ 1; 2; 3; 4; 5 ];
  check "five rows" "5" (ints (Array.length (query_all c "li")));
  check "one template element for the template" "1" (ints (templates_created ()));
  dispose ()

let template_in_hydrate () =
  let count = State.make 5 and title = State.make "a" in
  let tree () = row count title in
  let c = container (server (tree ())) in
  let li = query c "li" in
  let b = query c "b" in
  count_templates ();
  let dispose = Yuka.Client.hydrate (as_element c) tree in
  same "li adopted" li (query c "li");
  same "b adopted" b (query c "b");
  check "no template cloned when hydrating" "0" (ints (templates_created ()));
  click li;
  check "handler" "6" (text_content (query c "span"));
  dispose ()

let template_timing () =
  let rows = 1000 in
  let run wrap =
    let c = container "" in
    let t0 = now () in
    let dispose =
      Yuka.Client.render (as_element c) (fun () ->
          lower "ul" []
            [
              each ~key:ints
                (fun () -> List.init rows Fun.id)
                (fun i -> row ~wrap (State.make i) (State.make "t"));
            ])
    in
    let t1 = now () in
    let out = html c in
    dispose ();
    (t1 -. t0, out)
  in
  ignore (run true);
  ignore (run false);
  let best wrap = List.fold_left (fun m _ -> min m (fst (run wrap))) infinity [ 1; 2; 3; 4; 5 ] in
  let with_t = best true and without_t = best false in
  Printf.printf "timing: %d rows, best of 5: plain %.1f ms, template %.1f ms\n" rows without_t with_t;
  check "same output" (snd (run false)) (snd (run true))

let slot_a = Template.(make (element "div" [] [ element "i" [] []; part 0 ]))
let slot_b = Template.(make (element "section" [] [ element "i" [] []; part 0 ]))

let template_with_slot () =
  let content = Slot.make (lower "p" [] [ text "x" ]) in
  let wrap = State.make true in
  let view slot =
    lower "main" []
      [
        hole (fun () ->
            Template.instance
              (if State.get wrap then slot_a else slot_b)
              [| Template.child (Yuka.slot slot) |]);
      ]
  in
  let c = container (server (view content)) in
  let p = query c "p" in
  let client =
    match Codec.decode Codec.slot `Null with Ok s -> s | Error m -> raise (Cases.Failed m)
  in
  let dispose = Yuka.Client.hydrate (as_element c) (fun () -> view client) in
  same "adopted" p (query c "p");
  State.set wrap false;
  same "moved into the new template" p (query c "p");
  check "html"
    "<main><section><i></i><!--[$--><p>x</p><!--]--></section></main>"
    (html c);
  dispose ()

let render_html tree =
  let c = container "" in
  let dispose = Yuka.Client.render (as_element c) tree in
  let out = html c in
  dispose ();
  out

let template_clone_same_dom () =
  let t =
    Template.(
      make
        (element "p" []
           [ text "a"; part 0; text "b"; part 1; text "c"; part 2; part 3; text "d";
             element "i" [] []; part 4 ]))
  in
  let s = State.make "h" in
  let cases : (string * client element list) list =
    [
      ("texts", [ text "x"; text "y"; text "z"; text "w"; text "v" ]);
      ("elements", [ span []; span []; span []; span []; span [] ]);
      ("empty", [ empty; text ""; empty; empty; empty ]);
      ( "holes",
        [ hole (fun () -> text (State.get s)); text "y"; hole (fun () -> span []);
          text "w"; hole (fun () -> text (State.get s)) ] );
      ("mixed", [ span []; text "y"; text "z"; span []; text "v" ]);
    ]
  in
  List.iter
    (fun (name, kids) ->
      let kid i = List.nth kids i in
      let by_hand () =
        lower "p" []
          [ text "a"; kid 0; text "b"; kid 1; text "c"; kid 2; kid 3; text "d";
            lower "i" [] []; kid 4 ]
      in
      let instance () = Template.instance t (Array.of_list (List.map Template.child kids)) in
      let expected = server (by_hand ()) in
      check ("clone " ^ name) expected (render_html instance);
      check ("lower " ^ name) expected (render_html by_hand);
      let c = container expected in
      let dispose = Yuka.Client.hydrate (as_element c) instance in
      check ("hydrate " ^ name) expected (html c);
      dispose ())
    cases

let svg_template () =
  let t = Template.(make (element "circle" [ fixed "r" "1"; part_attr 0 ] [])) in
  let c = container "" in
  let dispose =
    Yuka.Client.render (as_element c) (fun () ->
        lower "svg" []
          [ Template.(instance t [| attribute (hole_attr "cx" (fun () -> Some "2")) |]) ])
  in
  let circle = query c "circle" in
  check "svg namespace" "http://www.w3.org/2000/svg" (namespace_uri circle);
  check "html" {|<svg><circle r="1" cx="2"></circle></svg>|} (html c);
  dispose ()

let only_child_hole_hydrates () =
  let s = State.make "x" in
  let tree () = lower "p" [] [ hole (fun () -> text (State.get s)) ] in
  let c = container (server (tree ())) in
  check "server html has no markers" "<p>x</p>" (html c);
  let t = first_child (query c "p") in
  let dispose = Yuka.Client.hydrate (as_element c) tree in
  same "text adopted" t (first_child (query c "p"));
  State.set s "y";
  check "updated in place" "<p>y</p>" (html c);
  same "same text node" t (first_child (query c "p"));
  dispose ();
  let e = State.make "" in
  let tree () =
    lower "p" []
      [ hole (fun () -> if State.get e = "el" then span [ text "s" ] else text (State.get e)) ]
  in
  let c = container (server (tree ())) in
  check "empty text writes nothing" "<p></p>" (html c);
  let dispose = Yuka.Client.hydrate (as_element c) tree in
  check "one empty text node" "1" (ints (Array.length (child_nodes (query c "p"))));
  State.set e "z";
  check "text set" "<p>z</p>" (html c);
  State.set e "el";
  check "element replaces text" "<p><span>s</span></p>" (html c);
  State.set e "w";
  check "text again" "<p>w</p>" (html c);
  dispose ()

let list_clear_disposes () =
  let run sibling =
    let gone = ref 0 in
    let items = State.make [ 1; 2; 3; 4 ] in
    let c = container "" in
    let dispose =
      Yuka.Client.render (as_element c) (fun () ->
          lower "ul" []
            ([ each ~key:ints
                 (fun () -> State.get items)
                 (fun i ->
                   Effect.run ~cleanup:(fun () -> incr gone) (fun () -> ());
                   li (ints i) [ text (ints i) ]) ]
            @ if sibling then [ lower "i" [] [] ] else []))
    in
    State.set items [];
    check "every row disposed" "4" (ints !gone);
    check "rows removed" "" (order c);
    let after_clear = html c in
    State.set items [ 5; 6 ];
    check "refilled" "5,6" (order c);
    State.set items [ 7 ];
    check "replaced" "7" (order c);
    check "replaced rows disposed" "6" (ints !gone);
    dispose ();
    check "dispose disposes the last row" "7" (ints !gone);
    after_clear
  in
  check "only child: parent emptied" "<ul></ul>" (run false);
  check "with a sibling: markers stay" "<ul><!--[--><!--]--><i></i></ul>" (run true)

let row_root_removed_in_one_call () =
  let items = State.make [ "a"; "b"; "c" ] in
  let c = container "" in
  let dispose =
    Yuka.Client.render (as_element c) (fun () ->
        lower "ul" []
          [ each ~key:Fun.id
              (fun () -> State.get items)
              (fun k ->
                if k = "f" then fragment [ text "f1"; li k [] ] else li k [ text k ]) ])
  in
  check "no row markers" {|<ul><li data-key="a">a</li><li data-key="b">b</li><li data-key="c">c</li></ul>|}
    (html c);
  State.set items [ "a"; "c" ];
  check "one removed" {|<ul><li data-key="a">a</li><li data-key="c">c</li></ul>|} (html c);
  State.set items [ "c"; "f"; "a" ];
  check "fragment row has markers"
    {|<ul><li data-key="c">c</li><!--[-->f1<li data-key="f"></li><!--]--><li data-key="a">a</li></ul>|}
    (html c);
  State.set items [ "f"; "a" ];
  check "moved range" {|<ul><!--[-->f1<li data-key="f"></li><!--]--><li data-key="a">a</li></ul>|}
    (html c);
  dispose ()

external select_value : node -> string = "value" [@@mel.get]

let template_select_value () =
  let t =
    Template.(make (element "select" [ fixed "value" "b" ] [ part 0 ]))
  in
  let opt v = lower "option" [ attr "value" v ] [ text v ] in
  let c = container "" in
  let dispose =
    Yuka.Client.render (as_element c) (fun () ->
        Template.(
          instance t
            [| child (each ~key:Fun.id (fun () -> [ "a"; "b"; "c" ]) opt) |]))
  in
  check "value set after options mount" "b" (select_value (query c "select"));
  dispose ()

let parser_changes () =
  let x () = text "x" in
  let cases : (string * Template.shape * (unit -> client element list) * (client element list -> client element)) list =
    Template.
      [
        ( "table gets a tbody",
          element "table" [] [ element "tr" [] [ element "td" [] [ part 0 ] ] ],
          (fun () -> [ x () ]),
          fun k -> lower "table" [] [ lower "tr" [] [ lower "td" [] k ] ] );
        ( "p closed by div",
          element "p" [] [ element "div" [] [ part 0 ] ],
          (fun () -> [ x () ]),
          fun k -> lower "p" [] [ lower "div" [] k ] );
        ( "template element",
          element "div" [] [ element "template" [] [ element "i" [] [ part 0 ] ] ],
          (fun () -> [ x () ]),
          fun k -> lower "div" [] [ lower "template" [] [ lower "i" [] k ] ] );
        ( "pre leading newline",
          element "pre" [] [ text "\n"; part 0; text "y" ],
          (fun () -> [ x () ]),
          fun k -> lower "pre" [] ([ Yuka.text "\n" ] @ k @ [ Yuka.text "y" ]) );
        ( "textarea leading newline",
          element "div" [] [ element "textarea" [] [ text "\nv" ]; part 0 ],
          (fun () -> [ x () ]),
          fun k -> lower "div" [] (lower "textarea" [] [ Yuka.text "\nv" ] :: k) );
        ( "body at the root",
          element "body" [] [ element "i" [] [ part 0 ] ],
          (fun () -> [ x () ]),
          fun k -> lower "body" [] [ lower "i" [] k ] );
        ( "carriage return",
          element "p" [] [ text "a\r\nb"; part 0 ],
          (fun () -> [ x () ]),
          fun k -> lower "p" [] (Yuka.text "a\r\nb" :: k) );
        ( "style text is not escaped",
          element "div" [] [ element "style" [] [ text "a > b {color:red}" ]; part 0 ],
          (fun () -> [ x () ]),
          fun k -> lower "div" [] (lower "style" [] [ Yuka.text "a > b {color:red}" ] :: k) );
      ]
  in
  let wrong = ref [] in
  let check name expected got = if expected <> got then wrong := name :: !wrong in
  List.iter
    (fun (name, shape, kids, by_hand) ->
      let t = Template.make shape in
      let expected = render_html (fun () -> by_hand (kids ())) in
      let got =
        try render_html (fun () -> Template.instance t (Array.of_list (List.map Template.child (kids ()))))
        with e -> "raised " ^ Printexc.to_string e
      in
      check ("parser: " ^ name) expected got;
      let t2 = Template.make shape in
      ignore (try render_html (fun () -> Template.instance t2 (Array.of_list (List.map Template.child (kids ())))) with _ -> "");
      check ("parser, second use: " ^ name) expected
        (try render_html (fun () -> Template.instance t2 (Array.of_list (List.map Template.child (kids ()))))
         with e -> "raised " ^ Printexc.to_string e))
    cases;
  Cases.check "parser: cases that differ from lower" "" (String.concat ", " (List.rev !wrong));
  let c = container "" in
  let dispose =
    Yuka.Client.render (as_element c) (fun () ->
        Template.(instance (make (element "style" [] [ text "a > b {color:red}" ])) [||]))
  in
  check "style text content" "a > b {color:red}" (text_content (query c "style"));
  dispose ()

let all =
  [
    ("dom template select value", template_select_value);
    ("dom template parser changes", parser_changes);
    ("dom create", create_tree);
    ("dom hydrate adopts nodes", hydrate_adopts);
    ("dom click after hydrate", hydrate_then_click);
    ("dom click after render", render_then_click);
    ("dom handler removed after dispose", handler_removed_after_dispose);
    ("dom hydrate again after dispose", hydrate_again_after_dispose);
    ("dom two handlers in order", two_handlers_in_order);
    ("dom old handler removed on hole rerun", old_handler_removed_on_hole_rerun);
    ("dom direct handler", direct_handler);
    ("dom each item reads are untracked", each_item_reads_untracked);
    ("dom text hole in place", text_hole_in_place);
    ("dom hole swaps element", hole_swaps_element);
    ("dom nested hole disposed", nested_hole_disposed);
    ("dom dynamic attributes", dynamic_attributes);
    ("dom keyed list", keyed_list);
    ("dom each compares items by identity", each_identity_default);
    ("dom keyed list shuffle", keyed_list_shuffle);
    ("dom adjacent and empty texts hydrate", adjacent_texts_hydrate);
    ("dom hydrate server output", hydrate_server_output);
    ("dom await swaps", await_swaps);
    ("dom await fails", await_fails);
    ("dom await hydrates settled", await_hydrates_settled);
    ("dom await hydrates pending", await_hydrates_pending_then_settles);
    ("dom stop propagation and target tag", stop_propagation_and_tag);
    ("dom modifier keys", modifiers);
    ("dom browser functions", browser_functions);
    ("dom textarea hydrate", textarea_hydrate);
    ("dom select hydrate", select_hydrate);
    ("dom checked property", checked_property);
    ("dom selected property", selected_property);
    ("dom template same output", template_same_output);
    ("dom template works", template_works);
    ("dom template cached", template_cached);
    ("dom template hydrate walks node", template_in_hydrate);
    ("dom template with a slot", template_with_slot);
    ("dom template timing", template_timing);
    ("dom template clone same dom", template_clone_same_dom);
    ("dom svg template", svg_template);
    ("dom only child hole hydrates without markers", only_child_hole_hydrates);
    ("dom list clear disposes every row", list_clear_disposes);
    ("dom row root removed in one call", row_root_removed_in_one_call);
    ("dom svg render", svg_render);
    ("dom svg hole", svg_hole);
    ("dom svg hydrate", svg_hydrate);
  ]
