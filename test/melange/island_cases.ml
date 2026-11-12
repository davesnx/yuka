open Yuka

let check = Cases.check

let start_islands ?lazy_entries entries =
  Yuka.render ~islands:(Yuka.runtime_registry ?lazy_entries entries) ~navigation:false ()
let ints = string_of_int
let same = Dom_cases.same

let capture_errors : unit -> unit =
  [%mel.raw
    {|function () { globalThis.__errors = []; globalThis.__console_error = console.error; console.error = function (m) { globalThis.__errors.push(m); }; }|}]

let errors : unit -> string =
  [%mel.raw
    {|function () { console.error = globalThis.__console_error; return globalThis.__errors.join("|"); }|}]

let clear_body : unit -> unit =
  [%mel.raw {|function () { document.body.innerHTML = ""; }|}]

let reset_body () =
  Yuka.stop ();
  clear_body ()

let install_fetch : string -> int -> string -> unit =
  [%mel.raw
    {|function (mode, status, body) {
  globalThis.__calls = [];
  globalThis.fetch = function (url, init) {
    globalThis.__calls.push({ url: url, init: init });
    if (mode === "network") return Promise.reject(new Error("down"));
    if (mode === "hang") return new Promise(function (resolve, reject) {
      init.signal.addEventListener("abort", function () { reject(new Error("aborted")); });
    });
    return Promise.resolve({ status: status, text: function () { return Promise.resolve(body); } });
  };
}|}]

let calls : unit -> string =
  [%mel.raw
    {|function () {
  const c = globalThis.__calls;
  const last = c[c.length - 1];
  return JSON.stringify([last.url, last.init.method, last.init.headers["Content-Type"], last.init.body, c.length]);
}|}]

let counter_view n =
  let c = State.make n in
  element "div" []
    [
      element "span" [] [ hole (fun () -> text (ints (State.get c))) ];
      element "button" [ on "click" (fun _ -> State.update c succ) ] [ text "+" ];
    ]

let counter_island ?(name = "Counter") ?start n =
  runtime_island ?start ~name ~props:(Codec.encode Codec.int n) (fun () -> counter_view n)

let counter_entry =
  runtime_entry ~name:"Counter" (fun json ->
      Result.map
        (fun n -> fun () -> counter_view n)
        (Codec.decode Codec.int json))

let page islands = element "main" [] islands
let spans c = String.concat "," (Array.to_list (Array.map Dom_cases.text_content (Dom_cases.query_all c "span")))

let setup_page tree =
  reset_body ();
  Dom_cases.container (Dom_cases.server tree)

let islands_start () =
  let c = setup_page (page [ counter_island 5; counter_island 10 ]) in
  let buttons = Dom_cases.query_all c "button" in
  let roots = Dom_cases.query_all c "yuka-island > div" in
  start_islands [ counter_entry ];
  same "button 1 adopted" buttons.(0) (Dom_cases.query_all c "button").(0);
  same "button 2 adopted" buttons.(1) (Dom_cases.query_all c "button").(1);
  same "root 1 adopted" roots.(0) (Dom_cases.query_all c "yuka-island > div").(0);
  check "props decoded" "5,10" (spans c);
  Dom_cases.click (Dom_cases.query_all c "button").(0);
  check "only island 1 changes" "6,10" (spans c);
  Dom_cases.click (Dom_cases.query_all c "button").(1);
  Dom_cases.click (Dom_cases.query_all c "button").(1);
  check "only island 2 changes" "6,12" (spans c)

let islands_start_in_document_order () =
  ignore (setup_page (page [ counter_island 1; counter_island 2; counter_island 3 ]));
  let started = ref [] in
  let entry =
    runtime_entry ~name:"Counter" (fun json ->
        Result.map
          (fun n ->
            started := ints n :: !started;
            fun () -> counter_view n)
          (Codec.decode Codec.int json))
  in
  start_islands [ entry ];
  check "start order" "1,2,3" (String.concat "," (List.rev !started))

let unknown_island () =
  let c =
    setup_page (page [ counter_island ~name:"Nope" 1; counter_island 10 ])
  in
  let before = Dom_cases.html (Dom_cases.query_all c "yuka-island").(0) in
  capture_errors ();
  start_islands [ counter_entry ];
  let logged = errors () in
  check "logged" "yuka island i1 (Nope): unknown island name" logged;
  check "server html kept" before (Dom_cases.html (Dom_cases.query_all c "yuka-island").(0));
  Dom_cases.click (Dom_cases.query_all c "button").(0);
  Dom_cases.click (Dom_cases.query_all c "button").(1);
  check "other island started" "1,11" (spans c)

let broken_islands () =
  reset_body ();
  let c =
    Dom_cases.container
      {|<yuka-island data-name="Counter" data-id="i1"><span>x</span></yuka-island><script type="application/json" data-yuka-props="i1">"text"</script><yuka-island data-name="Counter" data-id="i2"><span>y</span></yuka-island><yuka-island data-name="Counter" data-id="i3"><span>z</span></yuka-island><script type="application/json" data-yuka-props="i3">{oops</script>|}
  in
  capture_errors ();
  start_islands [ counter_entry ];
  let logged = errors () in
  let has s =
    let n = String.length s and m = String.length logged in
    let rec go i = i + n <= m && (String.sub logged i n = s || go (i + 1)) in
    string_of_bool (go 0)
  in
  check "decode error with id" "true" (has "yuka island i1 (Counter): cannot decode props");
  check "missing script" "true" (has "yuka island i2 (Counter): props script not found");
  check "bad json" "true" (has "yuka island i3 (Counter): bad props JSON");
  check "html kept" "x,y,z" (spans c)

let start_twice () =
  let c = setup_page (page [ counter_island 0 ]) in
  start_islands [ counter_entry ];
  start_islands [ counter_entry ];
  Dom_cases.click (Dom_cases.query_all c "button").(0);
  check "one handler" "1" (spans c)

let action = Action.mutation ~name:"create issue" ~input:Codec.string ~output:Codec.int

let status_text = function
  | Async.Done (Ok n) -> "done " ^ ints n
  | Async.Done (Error e) -> "error " ^ Status.error_to_string e
  | Async.Failed m -> "failed " ^ m
  | Async.Pending -> "pending"

let contains s sub =
  let n = String.length sub and m = String.length s in
  let rec go i = i + n <= m && (String.sub s i n = sub || go (i + 1)) in
  go 0

let action_case ~mode ~status ~body expected_status expected_call =
 fun finish ->
  reset_body ();
  start_islands [];
  install_fetch mode status body;
  Async.on_settled (Action.call action "hi") (fun st ->
      finish (fun () ->
          check "result" expected_status (status_text st);
          if expected_call then
            check "request"
              {|["/_yuka/action/create%20issue","POST","application/json","\"hi\"",1]|}
              (calls ())))

let action_contains ~mode ~status ~body part =
 fun finish ->
  reset_body ();
  start_islands [];
  install_fetch mode status body;
  Async.on_settled (Action.call action "hi") (fun st ->
      finish (fun () ->
          let t = status_text st in
          check ("failure mentions " ^ part) "true" (string_of_bool (contains t part));
          check "is an error" "error " (String.sub t 0 6)))

let lazy_view a =
  Await.make ~async:a ~loading:(element "span" [] [ text "loading" ])
    ~failed:(fun m -> element "i" [] [ text ("failed " ^ m) ])
    ~children:(fun n -> element "b" [] [ text (ints n) ])
    ()

let lazy_entry =
  runtime_entry ~name:"Lazy" (fun json ->
      Result.map
        (fun a -> fun () -> lazy_view a)
        (Codec.decode (Codec.async Codec.int) json))

let lazy_island ?(start = "[s1") ?(body = "<span>loading</span>") id props =
  Printf.sprintf
    {|<yuka-island data-name="Lazy" data-id="%s"><!--%s-->%s<!--]--></yuka-island><script type="application/json" data-yuka-props="%s">%s</script>|}
    id start body id props

let island_html c = Dom_cases.html (Dom_cases.query_all c "yuka-island").(0)

let async_prop_value () =
  reset_body ();
  let c =
    Dom_cases.container
      (lazy_island ~body:"<b>5</b>" "i1" {|{"$async":"a1"}|}
      ^ {|<script type="application/json" data-yuka-async="a1">{"ok":5}</script>|})
  in
  let b = Dom_cases.query c "b" in
  start_islands [ lazy_entry ];
  check "value rendered" "<!--[s1--><b>5</b><!--]-->" (island_html c);
  same "settled content adopted" b (Dom_cases.query c "b")

let async_prop_mismatch () =
  reset_body ();
  let c =
    Dom_cases.container
      (lazy_island "i1" {|{"$async":"a1"}|}
      ^ {|<script type="application/json" data-yuka-async="a1">{"ok":5}</script>|})
  in
  start_islands [ lazy_entry ];
  check "stale loading removed" "<!--[s1--><b>5</b><!--]-->" (island_html c)

let async_prop_error () =
  reset_body ();
  let c =
    Dom_cases.container
      (lazy_island "i1" {|{"$async":"a1"}|}
      ^ {|<script type="application/json" data-yuka-async="a1">{"error":"nope"}</script>|})
  in
  start_islands [ lazy_entry ];
  check "failed rendered" "<!--[s1--><i>failed nope</i><!--]-->" (island_html c)

let async_prop_inline () =
  reset_body ();
  let c =
    Dom_cases.container
      (lazy_island ~start:"[" "i1" {|{"$async":"a1","ok":8}|})
  in
  start_islands [ lazy_entry ];
  check "inline value" "<!--[--><b>8</b><!--]-->" (island_html c)

let hole_start_marker () =
  reset_body ();
  let c = Dom_cases.container (lazy_island "i1" {|{"$async":"a1","ok":1}|}) in
  start_islands [ lazy_entry ];
  check "start marker kept" "<!--[s1--><b>1</b><!--]-->" (island_html c)

let after : (unit -> unit) -> unit =
  [%mel.raw "function (f) { setTimeout(f, 0) }"]

let add_script : string -> unit =
  [%mel.raw
    {|function (json) { const s = document.createElement("script"); s.type = "application/json"; s.setAttribute("data-yuka-async", "a1"); s.textContent = json; document.body.appendChild(s); }|}]

let fresh_doc : string -> Dom_cases.node =
  [%mel.raw
    {|function (scripts) {
  const { JSDOM } = require("jsdom");
  const dom = new JSDOM("<!doctype html><html><body></body></html>", { runScripts: scripts });
  return dom.window.document;
}|}]

let eval_in : Dom_cases.node -> string -> unit =
  [%mel.raw "function (doc, js) { doc.defaultView.eval(js) }"]

let doc_body : Dom_cases.node -> Dom_cases.node = [%mel.raw "function (doc) { return doc.body }"]

let fill_js =
  let s = Private.fill_script in
  String.sub s 8 (String.length s - 8 - 9)

let fill_view a =
  element "div" []
    [
      text "x";
      Await.make ~async:a ~loading:(hole (fun () -> text "wait"))
        ~children:(fun n ->
          element "section" []
            [
              hole (fun () -> text (ints n));
              Await.make ~async:(Async.return "z") ~loading:empty
                ~children:(fun z -> element "i" [] [ text z ])
                ();
              text "t";
            ])
        ();
      element "p" [] [];
    ]

let streamed () =
  let a, resolve, _ = Async.make () in
  let session = Private.session ~streaming:true ~islands_only:false in
  let shell = Private.print session (fun () -> Private.node (fill_view a)) in
  let pending = Private.take_pending session in
  resolve 4;
  let chunk =
    match pending with
    | [ Private.Pending_await { id; fill; _ } ] -> (id, fill ())
    | _ -> raise (Cases.Failed "expected one pending await")
  in
  (a, shell, chunk)

let fill_runs () =
  let a, shell, (id, chunk) = streamed () in
  check "shell" "<div>x<!--[s1--><!--[-->wait<!--]--><!--]--><p></p></div>" shell;
  let doc = fresh_doc "outside-only" in
  let body = doc_body doc in
  eval_in doc fill_js;
  Dom_cases.set_html body (shell ^ {|<template data-yuka-fill="|} ^ id ^ {|">|} ^ chunk ^ "</template>");
  eval_in doc ({|window.__yukaFill("|} ^ id ^ {|")|});
  check "filled"
    "<div>x<!--[s1--><section><!--[-->4<!--]--><!--[--><i>z</i><!--]-->t</section><!--]--><p></p></div>"
    (Dom_cases.html body);
  ignore a

let run_scripts : Dom_cases.node -> string -> unit =
  [%mel.raw
    {|function (doc, html) {
  const holder = doc.createElement("div");
  holder.innerHTML = html;
  holder.querySelectorAll("script").forEach(function (old) {
    const s = doc.createElement("script");
    s.textContent = old.textContent;
    old.replaceWith(s);
  });
  while (holder.firstChild) doc.body.appendChild(holder.firstChild);
}|}]

let fill_script_removed () =
  let _, shell, (id, chunk) = streamed () in
  let doc = fresh_doc "dangerously" in
  run_scripts doc Private.fill_script;
  Dom_cases.set_html (doc_body doc) shell;
  run_scripts doc
    ({|<template data-yuka-fill="|} ^ id ^ {|">|} ^ chunk ^ {|</template><script>__yukaFill("|} ^ id ^ {|")</script>|});
  check "no template, no script"
    "<div>x<!--[s1--><section><!--[-->4<!--]--><!--[--><i>z</i><!--]-->t</section><!--]--><p></p></div>"
    (Dom_cases.html (doc_body doc))

let fill_then_hydrate () =
  let a, shell, (id, chunk) = streamed () in
  let doc = fresh_doc "outside-only" in
  let body = doc_body doc in
  eval_in doc fill_js;
  Dom_cases.set_html body
    (shell ^ {|<template data-yuka-fill="|} ^ id ^ {|">|} ^ chunk ^ "</template>");
  eval_in doc ({|window.__yukaFill("|} ^ id ^ {|")|});
  let section = Dom_cases.query body "section" in
  let p = Dom_cases.query body "p" in
  let i = Dom_cases.query body "i" in
  let before = Dom_cases.html body in
  let dispose =
    Yuka.Private.hydrate (Dom_cases.as_element body) (fun () -> fill_view a)
  in
  same "section adopted" section (Dom_cases.query body "section");
  same "i adopted" i (Dom_cases.query body "i");
  same "p adopted" p (Dom_cases.query body "p");
  check "html unchanged" before (Dom_cases.html body);
  dispose ()

let empty_slot () =
  match Codec.decode Codec.slot `Null with
  | Ok s -> s
  | Error m -> raise (Cases.Failed m)

let slot_node p = Dom_cases.query p "p"

let slot_page_tree slot =
  element "div" []
    [
      text "a";
      hole (fun () ->
          if true then element "div" [] [ Yuka.slot slot ] else empty);
    ]

let slot_adopted () =
  let content = Slot.make (element "p" [] [ text "x"; element "b" [] [ text "y" ] ]) in
  let server_html = Dom_cases.server (element "div" [] [ text "a"; Yuka.slot content ]) in
  check "server html"
    "<div>a<!--[$--><p>x<b>y</b></p><!--]--></div>" server_html;
  let c = Dom_cases.container server_html in
  let p = slot_node c in
  let client = empty_slot () in
  let dispose =
    Yuka.Private.hydrate (Dom_cases.as_element c) (fun () ->
        element "div" [] [ text "a"; Yuka.slot client ])
  in
  same "slot node adopted" p (slot_node c);
  check "captured" "1" (ints (List.length !(Private.slot_dom client)));
  check "html unchanged" server_html (Dom_cases.html c);
  dispose ()

let slot_moves_with_hole () =
  let content = Slot.make (element "p" [] [ text "x" ]) in
  let wrap = State.make true in
  let view slot =
    element "main" []
      [
        hole (fun () ->
            if State.get wrap then element "div" [] [ Yuka.slot slot ]
            else element "section" [] [ Yuka.slot slot ]);
      ]
  in
  let c = Dom_cases.container (Dom_cases.server (view content)) in
  let p = slot_node c in
  let client = empty_slot () in
  let dispose = Yuka.Private.hydrate (Dom_cases.as_element c) (fun () -> view client) in
  same "adopted" p (slot_node c);
  State.set wrap false;
  check "moved into section"
    "<main><section><!--[$--><p>x</p><!--]--></section></main>"
    (Dom_cases.html c);
  same "same node after move" p (slot_node c);
  State.set wrap true;
  same "same node after second move" p (slot_node c);
  check "back"
    "<main><div><!--[$--><p>x</p><!--]--></div></main>"
    (Dom_cases.html c);
  dispose ()

let slot_never_captured () =
  let c = Dom_cases.container "" in
  let dispose =
    Yuka.Private.render (Dom_cases.as_element c) (fun () ->
        element "div" [] [ Yuka.slot (empty_slot ()) ])
  in
  check "markers only" "<div><!--[$--><!--]--></div>" (Dom_cases.html c);
  dispose ()

let outer_view slot =
  let wrap = State.make true in
  element "div" []
    [
      element "button" [ attr "id" "outer"; on "click" (fun _ -> State.update wrap not) ] [];
      hole (fun () ->
          if State.get wrap then element "div" [] [ Yuka.slot slot ]
          else element "section" [] [ Yuka.slot slot ]);
    ]

let outer_entry =
  runtime_entry ~name:"Outer" (fun _ ->
      Ok (fun () -> outer_view (empty_slot ())))

let nested_island ~outer_loading () =
  let inner = counter_island 5 in
  let tree =
    page
      [
        runtime_island ?start:outer_loading ~name:"Outer" ~props:`Null (fun () ->
            outer_view (Slot.make inner));
      ]
  in
  reset_body ();
  let c = Dom_cases.container (Dom_cases.server tree) in
  let counter_button = Dom_cases.query c "yuka-island yuka-island button" in
  start_islands [ outer_entry; counter_entry ];
  (c, counter_button)

let click_outer c = Dom_cases.click (Dom_cases.query c "#outer")

let slot_island_outer_first () =
  let c, button = nested_island ~outer_loading:None () in
  same "inner button kept" button (Dom_cases.query c "yuka-island yuka-island button");
  Dom_cases.click (Dom_cases.query c "yuka-island yuka-island button");
  check "inner works" "6" (Dom_cases.text_content (Dom_cases.query c "yuka-island yuka-island span"));
  click_outer c;
  same "inner button kept after move" button (Dom_cases.query c "yuka-island yuka-island button");
  Dom_cases.click (Dom_cases.query c "yuka-island yuka-island button");
  check "inner state kept after move" "7"
    (Dom_cases.text_content (Dom_cases.query c "yuka-island yuka-island span"))

let fire : Dom_cases.node -> string -> unit =
  [%mel.raw "function (el, name) { el.dispatchEvent(new window.Event(name, { bubbles: true })) }"]

let slot_island_inner_first () =
  let c, button = nested_island ~outer_loading:(Some `Interaction) () in
  Dom_cases.click (Dom_cases.query c "yuka-island yuka-island button");
  check "inner started first" "6" (Dom_cases.text_content (Dom_cases.query c "yuka-island yuka-island span"));
  click_outer c;
  check "outer still server html" "0"
    (ints (Array.length (Dom_cases.query_all c "section")));
  fire (Dom_cases.query c "#outer") "pointerover";
  check "recorded click replayed at start" "1" (ints (Array.length (Dom_cases.query_all c "section")));
  click_outer c;
  check "outer works after start" "0" (ints (Array.length (Dom_cases.query_all c "section")));
  click_outer c;
  check "and again" "1" (ints (Array.length (Dom_cases.query_all c "section")));
  same "inner button kept" button (Dom_cases.query c "yuka-island yuka-island button");
  Dom_cases.click (Dom_cases.query c "yuka-island yuka-island button");
  check "inner state kept" "7" (Dom_cases.text_content (Dom_cases.query c "yuka-island yuka-island span"))

let stub_browser : unit -> unit =
  [%mel.raw
    {|function () {
  globalThis.__idle = [];
  window.requestIdleCallback = function (f) { globalThis.__idle.push(f); return globalThis.__idle.length - 1; };
  window.cancelIdleCallback = function (id) { globalThis.__idle[id] = null; };
  globalThis.__io = null;
  window.IntersectionObserver = function (cb) { this.cb = cb; this.targets = []; this.disconnected = false; globalThis.__io = this; };
  window.IntersectionObserver.prototype.observe = function (el) { this.targets.push(el); };
  window.IntersectionObserver.prototype.disconnect = function () { this.disconnected = true; };
}|}]

let unstub_idle : unit -> unit = [%mel.raw "function () { delete window.requestIdleCallback }"]
let unstub_io : unit -> unit = [%mel.raw "function () { delete window.IntersectionObserver }"]
let run_idle : unit -> int = [%mel.raw "function () { const l = globalThis.__idle; globalThis.__idle = []; const live = l.filter(function (f) { return f }); live.forEach(function (f) { f() }); return live.length }"]
let io_target_is_first_child : unit -> bool = [%mel.raw "function () { return globalThis.__io.targets.length === 1 && globalThis.__io.targets[0] === globalThis.__io.targets[0].parentElement.firstElementChild }"]
let io_report : bool -> unit = [%mel.raw "function (v) { if (!globalThis.__io.disconnected) globalThis.__io.cb([{ isIntersecting: v }]) }"]
let io_disconnected : unit -> bool = [%mel.raw "function () { return globalThis.__io.disconnected }"]

let one_island loading =
  reset_body ();
  let c = Dom_cases.container (Dom_cases.server (page [ counter_island ?start:loading 0 ])) in
  stub_browser ();
  c

let btn c = Dom_cases.query c "button"

let strategy_load_default () =
  let c = one_island None in
  start_islands [ counter_entry ];
  Dom_cases.click (btn c);
  check "started at once" "1" (spans c)

let strategy_data_attribute () =
  let c = one_island (Some `Idle) in
  check "written" "idle"
    (Option.value (Dom_cases.get_attribute (Dom_cases.query c "yuka-island") "data-start") ~default:"");
  check "style" "display:contents"
    (Option.value (Dom_cases.get_attribute (Dom_cases.query c "yuka-island") "style") ~default:"")

let strategy_idle () =
  let c = one_island (Some `Idle) in
  start_islands [ counter_entry ];
  start_islands [ counter_entry ];
  Dom_cases.click (btn c);
  check "not started before idle" "0" (spans c);
  check "one callback" "1" (ints (run_idle ()));
  Dom_cases.click (btn c);
  check "the click before idle is replayed, the new one is live" "2" (spans c)

let strategy_visible () =
  let c = one_island (Some `Visible) in
  start_islands [ counter_entry ];
  check "observes first child" "true" (string_of_bool (io_target_is_first_child ()));
  Dom_cases.click (btn c);
  check "not started" "0" (spans c);
  io_report false;
  Dom_cases.click (btn c);
  check "not visible yet" "0" (spans c);
  io_report true;
  check "disconnected" "true" (string_of_bool (io_disconnected ()));
  Dom_cases.click (btn c);
  check "two recorded clicks replayed, one live" "3" (spans c)

let strategy_visible_without_observer () =
  let c = one_island (Some `Visible) in
  unstub_io ();
  start_islands [ counter_entry ];
  Dom_cases.click (btn c);
  check "started at once" "1" (spans c)

let strategy_interaction () =
  let c = one_island (Some `Interaction) in
  start_islands [ counter_entry ];
  Dom_cases.click (btn c);
  check "not started" "0" (spans c);
  fire (btn c) "focusin";
  fire (btn c) "pointerover";
  fire (btn c) "touchstart";
  Dom_cases.click (btn c);
  check "recorded click replayed once, listeners removed" "2" (spans c)

let strategy_interaction_each_event () =
  List.iter
    (fun name ->
      let c = one_island (Some `Interaction) in
      start_islands [ counter_entry ];
      fire (btn c) name;
      Dom_cases.click (btn c);
      check ("started by " ^ name) "1" (spans c))
    [ "pointerover"; "focusin"; "touchstart" ]

let body_node : unit -> Dom_cases.node = Dom_cases.body

let set_ready : string -> unit =
  [%mel.raw "function (v) { Object.defineProperty(document, 'readyState', { configurable: true, get: function () { return v } }) }"]

let clear_ready : unit -> unit = [%mel.raw "function () { delete document.readyState }"]

let append_html : string -> unit =
  [%mel.raw "function (h) { document.body.insertAdjacentHTML('beforeend', h) }"]

let set_script_text : string -> string -> unit =
  [%mel.raw "function (id, t) { document.querySelector('script[data-yuka-props=' + id + ']').textContent = t }"]

let eval_global : string -> unit = [%mel.raw "function (js) { window.eval(js) }"]
let dispatch_ready : unit -> unit =
  [%mel.raw "function () { document.dispatchEvent(new window.Event('DOMContentLoaded')) }"]

let split_island html =
  let marker = "</yuka-island>" in
  let n = String.length marker in
  let rec find i = if String.sub html i n = marker then i + n else find (i + 1) in
  let i = find 0 in
  (String.sub html 0 i, String.sub html i (String.length html - i))

let after_ms : int -> (unit -> unit) -> unit =
  [%mel.raw "function (ms, f) { setTimeout(function () { f() }, ms) }"]

let stop_disposes () =
  let c = one_island None in
  start_islands [ counter_entry ];
  Dom_cases.click (btn c);
  check "running" "1" (spans c);
  Yuka.stop ();
  Dom_cases.click (btn c);
  check "handlers removed" "1" (spans c);
  let c2 = one_island None in
  start_islands [ counter_entry ];
  Dom_cases.click (btn c2);
  check "start works again on a new body" "1" (spans c2);
  Yuka.stop ()

let stop_restarts_same_body () =
  let c = one_island None in
  start_islands [ counter_entry ];
  Yuka.stop ();
  start_islands [ counter_entry ];
  Dom_cases.click (btn c);
  check "island started again" "1" (spans c);
  Yuka.stop ()

let stop_cancels_idle () =
  let c = one_island (Some `Idle) in
  start_islands [ counter_entry ];
  Yuka.stop ();
  check "no callback left" "0" (ints (run_idle ()));
  Dom_cases.click (btn c);
  check "not started" "0" (spans c)

let stop_cancels_visible () =
  let c = one_island (Some `Visible) in
  start_islands [ counter_entry ];
  Yuka.stop ();
  check "observer disconnected" "true" (string_of_bool (io_disconnected ()));
  io_report true;
  Dom_cases.click (btn c);
  check "not started" "0" (spans c)

let stop_cancels_interaction () =
  let c = one_island (Some `Interaction) in
  start_islands [ counter_entry ];
  Yuka.stop ();
  fire (btn c) "pointerover";
  Dom_cases.click (btn c);
  check "not started" "0" (spans c)

external of_js : 'a Js.Promise.t -> 'a Yuka.runtime_promise = "%identity"
external import : string -> 'a Js.Promise.t = "import"
external entry_of : 'a -> Yuka.runtime_entry = "entry" [@@mel.get]

let import_calls = ref 0

let lazy_counter () =
  Yuka.runtime_lazy_entry ~name:"LazyCounter" (fun () ->
      incr import_calls;
      of_js
        (Js.Promise.then_
           (fun m -> Js.Promise.resolve (entry_of m))
           (import "./counter_island.js")))

let emitted_has_dynamic_import : unit -> bool =
  [%mel.raw {|function () { return /\bimport\("\.\/counter_island\.js"\)/.test(require("fs").readFileSync(__filename, "utf8")) }|}]

let dynamic_import_emitted () =
  check "the emitted JS has import(...)" "true" (string_of_bool (emitted_has_dynamic_import ()))

let lazy_page loading = page [ Counter_island.island ?start:loading 3; Counter_island.island ?start:loading 4 ]

let lazy_click_started c i =
  Dom_cases.click (Dom_cases.query_all c "button").(i)

let count_queries : unit -> unit =
  [%mel.raw
    {|function () {
  globalThis.__queries = 0;
  if (globalThis.__qsa) return;
  globalThis.__qsa = [window.Document.prototype].map(function (proto) {
    const original = proto.querySelectorAll;
    proto.querySelectorAll = function () { globalThis.__queries++; return original.apply(this, arguments); };
    return [proto, original];
  });
}|}]

let queries : unit -> int = [%mel.raw "function () { return globalThis.__queries }"]

let uncount_queries : unit -> unit =
  [%mel.raw "function () { (globalThis.__qsa || []).forEach(function (p) { p[0].querySelectorAll = p[1]; }); globalThis.__qsa = null }"]

let tick finish_with = after_ms 20 finish_with

let replay_log : string list ref = ref []

let replay_view () =
  let count = State.make 0 in
  let chosen = State.make "" in
  let keys = State.make "" in
  let log s = replay_log := s :: !replay_log in
  element "div" []
    [
      element "span" [ attr "id" "count" ] [ hole (fun () -> text (ints (State.get count))) ];
      element "button"
        [ on "click" (fun _ -> log "c"; State.update count succ) ]
        [ text "+" ];
      element "select"
        [ on "change" (fun e -> log ("s:" ^ Event.target_value e); State.set chosen (Event.target_value e)) ]
        [
          element "option" [ attr "value" "a" ] [ text "A" ];
          element "option" [ attr "value" "b" ] [ text "B" ];
        ];
      element "span" [ attr "id" "chosen" ] [ hole (fun () -> text (State.get chosen)) ];
      element "input" [ on "keydown" (fun e -> log ("k:" ^ Event.key e); State.update keys (fun k -> k ^ Event.key e)) ] [];
      element "span" [ attr "id" "keys" ] [ hole (fun () -> text (State.get keys)) ];
    ]

let replay_entry =
  runtime_entry ~name:"Replay" (fun _ -> Ok (fun () -> replay_view ()))

let replay_island ?start () =
  runtime_island ?start ~name:"Replay" ~props:`Null (fun () -> replay_view ())

let key_event : Dom_cases.node -> string -> unit =
  [%mel.raw "function (el, key) { el.dispatchEvent(new window.KeyboardEvent('keydown', { key: key, bubbles: true, cancelable: true })) }"]

let choose : Dom_cases.node -> string -> unit =
  [%mel.raw "function (el, v) { el.value = v; el.dispatchEvent(new window.Event('change', { bubbles: true })) }"]

let slow_lazy () =
  let resolve = ref (fun () -> ()) in
  let entry =
    Yuka.runtime_lazy_entry ~name:"Replay" (fun () ->
        of_js (Js.Promise.make (fun ~resolve:r ~reject:_ -> resolve := (fun () -> r replay_entry [@u]))))
  in
  (entry, fun () -> !resolve ())

let select_view () =
  let chosen = State.make "a" in
  element "div" []
    [
      element "select"
        [
          hole_attr "value" (fun () -> Some (State.get chosen));
          on "change" (fun e -> State.set chosen (Event.target_value e));
        ]
        [
          element "option" [ attr "value" "a" ] [ text "A" ];
          element "option" [ attr "value" "b" ] [ text "B" ];
        ];
      element "span" [ attr "id" "chosen" ] [ hole (fun () -> text (State.get chosen)) ];
    ]

let select_entry = runtime_entry ~name:"Select" (fun _ -> Ok (fun () -> select_view ()))

let select_island () =
  runtime_island ~start:`Interaction ~name:"Select" ~props:`Null (fun () -> select_view ())

let replay_select_with_value_hole () =
  reset_body ();
  let c = Dom_cases.container (Dom_cases.server (page [ select_island () ])) in
  start_islands [ select_entry ];
  choose (Dom_cases.query c "select") "b";
  fire (Dom_cases.query c "select") "pointerover";
  check "handler saw the new value" "b" (Dom_cases.text_content (Dom_cases.query c "#chosen"));
  check "select shows it" "b" (Dom_cases.value (Dom_cases.query c "select"));
  Yuka.stop ()

let navigations : string list ref = ref []

let platform_override_survives () =
  reset_body ();
  navigations := [];
  let c = Dom_cases.container (Dom_cases.server (page [ select_island () ])) in
  start_islands [ select_entry ];
  Private.platform :=
    { !Private.platform with navigate = (fun url -> navigations := url :: !navigations) };
  fire (Dom_cases.query c "select") "pointerover";
  Browser.navigate "/next";
  check "the override is still installed after an island started" "/next"
    (String.concat "," !navigations);
  Yuka.stop ();
  reset_body ();
  let c2 = Dom_cases.container (Dom_cases.server (page [ select_island () ])) in
  start_islands [ select_entry ];
  fire (Dom_cases.query c2 "select") "pointerover";
  Browser.navigate "/again";
  check "still there after stop and start" "/again,/next" (String.concat "," !navigations);
  choose (Dom_cases.query c2 "select") "b";
  check "islands still work" "b" (Dom_cases.text_content (Dom_cases.query c2 "#chosen"));
  Yuka.stop ()

let texts_of c = String.concat "," (List.map (fun s -> Dom_cases.text_content (Dom_cases.query c s)) [ "#count"; "#chosen"; "#keys" ])

let async =
  [
    ( "replay: events made while the code loads",
      fun finish ->
        reset_body ();
        replay_log := [];
        let c = Dom_cases.container (Dom_cases.server (page [ replay_island () ])) in
        let entry, release = slow_lazy () in
        start_islands ~lazy_entries:[ entry ] [];
        Dom_cases.click (Dom_cases.query c "button");
        choose (Dom_cases.query c "select") "b";
        key_event (Dom_cases.query c "input") "x";
        Dom_cases.click (Dom_cases.query c "button");
        let before = texts_of c in
        release ();
        after_ms 30 (fun () ->
            let applied = texts_of c in
            Dom_cases.click (Dom_cases.query c "button");
            let again = texts_of c in
            finish (fun () ->
                check "nothing applied before the load" "0,,"  before;
                check "applied after the load" "2,b,x" applied;
                check "order kept" "c,s:b,k:x,c" (String.concat "," (List.rev !replay_log |> fun l -> List.filteri (fun i _ -> i < 4) l));
                check "recording stopped" "3,b,x" again;
                Yuka.stop ())) );
    ( "replay: stop drops the queue",
      fun finish ->
        reset_body ();
        replay_log := [];
        let c = Dom_cases.container (Dom_cases.server (page [ replay_island () ])) in
        let entry, release = slow_lazy () in
        start_islands ~lazy_entries:[ entry ] [];
        Dom_cases.click (Dom_cases.query c "button");
        Yuka.stop ();
        release ();
        after_ms 30 (fun () ->
            Dom_cases.click (Dom_cases.query c "button");
            finish (fun () ->
                check "nothing replayed or started" "0,," (texts_of c);
                check "no handler ran" "" (String.concat "," !replay_log))) );
    ( "jsdom finishes loading", fun finish -> after_ms 50 (fun () -> finish ignore) );
    ( "early start: island added after start",
      fun finish ->
        reset_body ();
        set_ready "loading";
        start_islands [ counter_entry ];
        let html = Dom_cases.server (counter_island 0) in
        append_html html;
        tick (fun () ->
            Dom_cases.click (Dom_cases.query (body_node ()) "button");
            clear_ready ();
            finish (fun () ->
                check "started on arrival" "1" (Dom_cases.text_content (Dom_cases.query (body_node ()) "span"));
                Yuka.stop ())) );
    ( "early start: island waits for its props script",
      fun finish ->
        reset_body ();
        set_ready "loading";
        capture_errors ();
        start_islands [ counter_entry ];
        let island, script = split_island (Dom_cases.server (counter_island 0)) in
        append_html island;
        tick (fun () ->
            Dom_cases.click (Dom_cases.query (body_node ()) "button");
            let early = Dom_cases.text_content (Dom_cases.query (body_node ()) "span") in
            append_html script;
            tick (fun () ->
                Dom_cases.click (Dom_cases.query (body_node ()) "button");
                let late = Dom_cases.text_content (Dom_cases.query (body_node ()) "span") in
                let logged = errors () in
                clear_ready ();
                finish (fun () ->
                    check "not started without props" "0" early;
                    check "started when the script arrived" "1" late;
                    check "no error" "" logged;
                    Yuka.stop ()))) );
    ( "early start: partial props script",
      fun finish ->
        reset_body ();
        set_ready "loading";
        capture_errors ();
        start_islands [ counter_entry ];
        let island, script = split_island (Dom_cases.server (counter_island 7)) in
        let partial =
          String.concat "" [ island; {|<script type="application/json" data-yuka-props="i1">|} ]
        in
        ignore script;
        append_html partial;
        tick (fun () ->
            Dom_cases.click (Dom_cases.query (body_node ()) "button");
            let early = Dom_cases.text_content (Dom_cases.query (body_node ()) "span") in
            set_script_text "i1" "";
            set_script_text "i1" "7";
            tick (fun () ->
                Dom_cases.click (Dom_cases.query (body_node ()) "button");
                let late = Dom_cases.text_content (Dom_cases.query (body_node ()) "span") in
                let logged = errors () in
                clear_ready ();
                finish (fun () ->
                    check "not started on an empty script" "7" early;
                    check "started when complete" "8" late;
                    check "no error" "" logged;
                    Yuka.stop ()))) );
    ( "early start: unrelated mutations cost no scan",
      fun finish ->
        reset_body ();
        set_ready "loading";
        start_islands [ counter_entry ];
        count_queries ();
        append_html "<p>one</p><div><span>two</span></div>";
        tick (fun () ->
            let n = queries () in
            uncount_queries ();
            clear_ready ();
            finish (fun () ->
                check "no whole-document query for unrelated nodes" "0" (ints n);
                Yuka.stop ())) );
    ( "early start: no observer after DOMContentLoaded",
      fun finish ->
        reset_body ();
        set_ready "loading";
        start_islands [ counter_entry ];
        dispatch_ready ();
        count_queries ();
        append_html (Dom_cases.server (counter_island 0));
        tick (fun () ->
            let n = queries () in
            uncount_queries ();
            Dom_cases.click (Dom_cases.query (body_node ()) "button");
            clear_ready ();
            finish (fun () ->
                check "no scan after the final one" "0" (ints n);
                check "island added later is not started by the observer" "0"
                  (Dom_cases.text_content (Dom_cases.query (body_node ()) "span"));
                Yuka.stop ())) );
    ( "early start: async value watcher ignores other mutations",
      fun finish ->
        reset_body ();
        set_ready "loading";
        let value = Async.make () in
        ignore value;
        let c = Dom_cases.container (Dom_cases.server (page [ Counter_island.island 0 ])) in
        ignore c;
        let pending =
          match
            Codec.decode
              (Codec.async (Codec.make ~encode:(fun j -> j) ~decode:(fun j -> Ok j)))
              (`Assoc [ ("$async", `String "a1") ])
          with
          | Ok a -> a
          | Error m -> raise (Cases.Failed m)
        in
        count_queries ();
        append_html "<p>other</p>";
        tick (fun () ->
            let n = queries () in
            uncount_queries ();
            let unrelated = n in
            append_html {|<script type="application/json" data-yuka-async="a1">{"ok":4}</script>|};
            tick (fun () ->
                clear_ready ();
                finish (fun () ->
                    check "no whole-document query for unrelated nodes" "0" (ints unrelated);
                    check "resolved when it arrived" "ok 4"
                      (match Async.status pending with
                      | Async.Done (`Int n) -> "ok " ^ ints n
                      | _ -> "not done")))) );
    ( "early start: stop disconnects the watcher",
      fun finish ->
        reset_body ();
        start_islands [ counter_entry ];
        Yuka.stop ();
        append_html (Dom_cases.server (counter_island 0));
        tick (fun () ->
            Dom_cases.click (Dom_cases.query (body_node ()) "button");
            finish (fun () ->
                check "not started after stop" "0" (Dom_cases.text_content (Dom_cases.query (body_node ()) "span")))) );
    ( "early start: a fill brings an island",
      fun finish ->
        reset_body ();
        eval_global fill_js;
        set_ready "loading";
        let html = Dom_cases.server (counter_island 0) in
        append_html ({|<div><!--[s1-->loading<!--]--></div>|});
        start_islands [ counter_entry ];
        append_html ({|<template data-yuka-fill="s1">|} ^ html ^ "</template>");
        eval_global {|__yukaFill("s1")|};
        tick (fun () ->
            Dom_cases.click (Dom_cases.query (body_node ()) "button");
            clear_ready ();
            finish (fun () ->
                check "island from the fill started" "1" (Dom_cases.text_content (Dom_cases.query (body_node ()) "span"));
                Yuka.stop ())) );
    ( "lazy entry loads on start",
      fun finish ->
        import_calls := 0;
        reset_body ();
        let c = Dom_cases.container (Dom_cases.server (lazy_page None)) in
        start_islands ~lazy_entries:[ lazy_counter () ] [];
        check "import called once for two islands" "1" (ints !import_calls);
        after_ms 100 (fun () ->
            lazy_click_started c 0;
            finish (fun () ->
                check "island works after the import" "4,4" (spans c);
                Yuka.stop ())) );
    ( "lazy entry waits for the strategy",
      fun finish ->
        import_calls := 0;
        let c = one_island None in
        ignore c;
        reset_body ();
        stub_browser ();
        let c = Dom_cases.container (Dom_cases.server (lazy_page (Some `Idle))) in
        start_islands ~lazy_entries:[ lazy_counter () ] [];
        let before = !import_calls in
        ignore (run_idle ());
        after_ms 100 (fun () ->
            lazy_click_started c 1;
            finish (fun () ->
                check "no import before idle" "0" (ints before);
                check "imported after idle" "1" (ints !import_calls);
                check "island works" "3,5" (spans c);
                Yuka.stop ())) );
    ( "lazy entry that fails to load",
      fun finish ->
        reset_body ();
        let c = Dom_cases.container (Dom_cases.server (lazy_page None)) in
        let bad =
          Yuka.runtime_lazy_entry ~name:"LazyCounter" (fun () -> of_js (Js.Promise.reject (Failure "no chunk")))
        in
        capture_errors ();
        start_islands ~lazy_entries:[ bad ] [];
        after_ms 50 (fun () ->
            let logged = errors () in
            finish (fun () ->
                check "logged" "true" (string_of_bool (contains logged "cannot load code"));
                check "html kept" "3,4" (spans c);
                Yuka.stop ())) );
    ( "stop aborts an action in flight",
      fun finish ->
        reset_body ();
        start_islands [];
        install_fetch "hang" 0 "";
        let result = Action.call action "hi" in
        check "pending" "pending" (status_text (Async.status result));
        Yuka.stop ();
        Async.on_settled result (fun st ->
            finish (fun () -> check "cancelled" "error network error: cancelled" (status_text st))) );
    ( "stop leaves a settled action alone",
      fun finish ->
        reset_body ();
        start_islands [];
        install_fetch "ok" 200 {|{"ok":3}|};
        let result = Action.call action "hi" in
        Async.on_settled result (fun st ->
            Yuka.stop ();
            finish (fun () -> check "done" "done 3" (status_text st))) );
    ( "start idle falls back to a timeout",
      fun finish ->
        let c = one_island (Some `Idle) in
        unstub_idle ();
        start_islands [ counter_entry ];
        after_ms 50 (fun () ->
            Dom_cases.click (btn c);
            let early = spans c in
            after_ms 300 (fun () ->
                Dom_cases.click (btn c);
                finish (fun () ->
                    check "not started before the timeout" "0" early;
                    check "started after the timeout: replayed click plus live click" "2" (spans c)))) );
    ( "async prop arrives after start",
      fun finish ->
        reset_body ();
        let c =
          Dom_cases.container (lazy_island ~start:"[s1" "i1" {|{"$async":"a1"}|})
        in
        let span = Dom_cases.query c "span" in
        start_islands [ lazy_entry ];
        same "loading adopted" span (Dom_cases.query c "span");
        let before = island_html c in
        add_script {|{"ok":11}|};
        after (fun () ->
            finish (fun () ->
                check "still loading before" "<!--[s1--><span>loading</span><!--]-->" before;
                check "resolved on arrival" "<!--[s1--><b>11</b><!--]-->" (island_html c))) );

    ( "action ok",
      action_case ~mode:"ok" ~status:200 ~body:{|{"ok":42}|} "done 42" true );
    ( "action rejected in a 400",
      action_case ~mode:"ok" ~status:400 ~body:{|{"error":"title is empty"}|} "error title is empty" false );
    ( "action origin check in a 403",
      action_case ~mode:"ok" ~status:403 ~body:{|{"error":"origin mismatch"}|} "error forbidden" false );
    ( "action unknown in a 404",
      action_case ~mode:"ok" ~status:404 ~body:{|{"error":"unknown action"}|} "error not found" false );
    ( "action error in a 500",
      action_case ~mode:"ok" ~status:500 ~body:{|{"error":"boom"}|} "error server error" false );
    ( "action error in a 200",
      action_contains ~mode:"ok" ~status:200 ~body:{|{"error":"boom"}|} "unexpected response (HTTP 200)" );
    ( "action non-JSON body",
      action_case ~mode:"ok" ~status:502 ~body:"<html>" "error server error" false );
    ( "action network failure",
      action_contains ~mode:"network" ~status:0 ~body:"" "network error: down" );
    ( "action output decode failure",
      action_contains ~mode:"ok" ~status:200 ~body:{|{"ok":"x"}|} "expected" );
  ]

let ready_final_scan () =
  reset_body ();
  set_ready "loading";
  capture_errors ();
  append_html (fst (split_island (Dom_cases.server (counter_island 0))));
  start_islands [ counter_entry ];
  let during = errors () in
  capture_errors ();
  dispatch_ready ();
  let after = errors () in
  clear_ready ();
  check "silent while loading" "" during;
  check "reported at DOMContentLoaded" "yuka island i1 (Counter): props script not found" after;
  Yuka.stop ()

let replay_interaction () =
  reset_body ();
  replay_log := [];
  let c = Dom_cases.container (Dom_cases.server (page [ replay_island ~start:`Interaction () ])) in
  start_islands [ replay_entry ];
  Dom_cases.click (Dom_cases.query c "button");
  Dom_cases.click (Dom_cases.query c "button");
  check "not started" "0,," (texts_of c);
  fire (Dom_cases.query c "button") "pointerover";
  check "replayed after the start" "2,," (texts_of c);
  Dom_cases.click (Dom_cases.query c "button");
  check "live afterwards, once" "3,," (texts_of c);
  Yuka.stop ()

let all =
  [
    ("platform override survives island starts", platform_override_survives);
    ("replay select with a value hole", replay_select_with_value_hole);
    ("replay on interaction", replay_interaction);
    ("early start: final scan at DOMContentLoaded", ready_final_scan);
    ("dynamic import is emitted", dynamic_import_emitted);
    ("stop disposes islands", stop_disposes);
    ("stop then start on the same body", stop_restarts_same_body);
    ("stop cancels idle", stop_cancels_idle);
    ("stop cancels visible", stop_cancels_visible);
    ("stop cancels interaction", stop_cancels_interaction);
    ("slot adopted", slot_adopted);
    ("slot moves with a hole", slot_moves_with_hole);
    ("slot never captured", slot_never_captured);
    ("slot island, outer starts first", slot_island_outer_first);
    ("slot island, inner starts first", slot_island_inner_first);
    ("start default loads at once", strategy_load_default);
    ("start data attribute and style", strategy_data_attribute);
    ("start idle", strategy_idle);
    ("start visible", strategy_visible);
    ("start visible without observer", strategy_visible_without_observer);
    ("start interaction", strategy_interaction);
    ("start interaction each event", strategy_interaction_each_event);
    ("stream fill script runs", fill_runs);
    ("stream fill removes template and script", fill_script_removed);
    ("stream fill then hydrate", fill_then_hydrate);
    ("async prop value in page", async_prop_value);
    ("async prop error in page", async_prop_error);
    ("async prop with stale loading html", async_prop_mismatch);
    ("async prop inline ok", async_prop_inline);
    ("hole start marker with id", hole_start_marker);
    ("island start adopts and isolates", islands_start);
    ("islands start in document order", islands_start_in_document_order);
    ("island unknown name", unknown_island);
    ("island broken props", broken_islands);
    ("island start twice", start_twice);
  ]
