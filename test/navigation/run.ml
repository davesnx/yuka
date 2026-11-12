open Yuka

let check = Cases.check

let setup : string -> unit =
  [%mel.raw
    {|function (html) {
  const { JSDOM, VirtualConsole } = require("jsdom");
  const log = globalThis.__log = [];
  globalThis.__calls = [];
  globalThis.__ignoreAbort = false;
  globalThis.__failSync = false;
  globalThis.__now = 1000000;
  globalThis.__scrollThrows = false;
  Date.now = function () { return globalThis.__now; };
  const vc = new VirtualConsole();
  vc.on("jsdomError", function (e) {
    log.push(e.message.indexOf("navigation") >= 0 ? "assign" : "jsdom:" + e.message);
  });
  const dom = new JSDOM("<!doctype html><html><head><title>start</title></head><body>" + html + "</body></html>", { url: "http://localhost/start?x=1", virtualConsole: vc });
  const w = dom.window;
  globalThis.window = w;
  globalThis.document = w.document;
  Object.defineProperty(w, "scrollY", { value: 0, writable: true, configurable: true });
  w.scrollTo = function (x, y) { if (globalThis.__scrollThrows) throw new Error("scroll failed"); log.push("scroll:" + y); };
  w.Element.prototype.scrollIntoView = function () { log.push("into:" + this.id); };
  globalThis.fetch = function (url, init) {
    if (globalThis.__failSync) throw new Error("sync");
    const call = { url: url, init: init };
    globalThis.__calls.push(call);
    return new Promise(function (res, rej) {
      call.resolve = function (text, finalUrl, status, type, extra) {
        res({
          url: finalUrl,
          status: status,
          headers: { get: function (n) { n = n.toLowerCase(); return n === "content-type" ? type : (extra && n in extra ? extra[n] : null); } },
          text: function () { return Promise.resolve(text); },
        });
      };
      call.reject = rej;
      init.signal.addEventListener("abort", function () {
        if (!globalThis.__ignoreAbort) rej(new Error("aborted"));
      });
    });
  };
}|}]

let log : string -> unit = [%mel.raw "function (s) { globalThis.__log.push(s) }"]
let log_read : unit -> string = [%mel.raw "function () { return globalThis.__log.join('|') }"]
let log_g : unit -> string =
  [%mel.raw "function () { return globalThis.__log.filter(function (s) { return s.startsWith('g') }).join('|') }"]

let log_clear : unit -> unit = [%mel.raw "function () { globalThis.__log.length = 0 }"]
let calls : unit -> int = [%mel.raw "function () { return globalThis.__calls.length }"]
let call_url : int -> string = [%mel.raw "function (i) { return globalThis.__calls[i].url }"]

let call_header : int -> string =
  [%mel.raw "function (i) { return String(globalThis.__calls[i].init.headers['Yuka-Navigate']) }"]

let call_aborted : int -> bool =
  [%mel.raw "function (i) { return globalThis.__calls[i].init.signal.aborted }"]

let resolve_with : int -> string -> string -> int -> string -> unit =
  [%mel.raw "function (i, text, url, status, type) { globalThis.__calls[i].resolve(text, url || undefined, status, type) }"]

let resolve_call i text url = resolve_with i text url 200 "text/html; charset=utf-8"

let resolve_headers : int -> string -> int -> (string * string) array -> unit =
  [%mel.raw
    {|function (i, text, status, pairs) {
  const extra = {};
  pairs.forEach(function (p) { extra[p[0]] = p[1]; });
  globalThis.__calls[i].resolve(text, undefined, status, "text/html; charset=utf-8", extra);
}|}]

let count_listeners : unit -> unit =
  [%mel.raw
    {|function () {
  const counts = globalThis.__listeners = { click: 0, popstate: 0 };
  const wrap = function (target) {
    const add = target.addEventListener;
    target.addEventListener = function (name) {
      if (name in counts) counts[name]++;
      return add.apply(this, arguments);
    };
  };
  wrap(window);
  wrap(document);
}|}]

let listeners : unit -> string =
  [%mel.raw "function () { return globalThis.__listeners.click + ',' + globalThis.__listeners.popstate }"]

let reject_call : int -> unit =
  [%mel.raw "function (i) { globalThis.__calls[i].reject(new Error('down')) }"]

let ignore_abort : unit -> unit = [%mel.raw "function () { globalThis.__ignoreAbort = true }"]
let fail_sync : unit -> unit = [%mel.raw "function () { globalThis.__failSync = true }"]

let click : string -> string -> bool =
  [%mel.raw
    {|function (sel, flags) {
  const el = document.querySelector(sel);
  const ev = new window.MouseEvent("click", {
    bubbles: true, cancelable: true,
    button: flags.indexOf("middle") >= 0 ? 1 : 0,
    ctrlKey: flags.indexOf("ctrl") >= 0, metaKey: flags.indexOf("meta") >= 0,
    shiftKey: flags.indexOf("shift") >= 0, altKey: flags.indexOf("alt") >= 0,
  });
  el.dispatchEvent(ev);
  return ev.defaultPrevented;
}|}]

let prevent_on : string -> unit =
  [%mel.raw
    "function (sel) { document.querySelector(sel).addEventListener('click', function (e) { e.preventDefault() }) }"]

let location_ : unit -> string =
  [%mel.raw "function () { return window.location.pathname + window.location.search + window.location.hash }"]

let body_html : unit -> string = [%mel.raw "function () { return document.body.innerHTML }"]
let title : unit -> string = [%mel.raw "function () { return document.title }"]
let history_length : unit -> int = [%mel.raw "function () { return window.history.length }"]
let back : unit -> unit = [%mel.raw "function () { window.history.back() }"]
let forward : unit -> unit = [%mel.raw "function () { window.history.forward() }"]
let set_scroll : float -> unit = [%mel.raw "function (y) { window.scrollY = y }"]

let set_timeout : (unit -> unit) -> int -> unit =
  [%mel.raw "function (f, ms) { setTimeout(f, ms) }"]

let fail_hook : (exn -> unit) ref = ref raise

let tick f =
  set_timeout
    (fun () -> try f () with e -> !fail_hook e)
    5

let ints = string_of_int
let bools = string_of_bool
let page body = "<main>" ^ body ^ "</main>"
let doc title body = "<!doctype html><html><head><title>" ^ title ^ "</title></head><body>" ^ body ^ "</body></html>"
let plain_start () = render ~islands:(runtime_registry []) ()

let navigate_before_start finish =
  setup "";
  Browser.navigate "/early";
  check "falls back to a page load" "assign" (log_read ());
  check "no fetch" "0" (ints (calls ()));
  finish ()

let click_fetches finish =
  setup (page {|<a id="l" href="/issue/1"><span id="in">go</span></a>|});
  plain_start ();
  check "click on a child is intercepted" "true" (bools (click "#in" ""));
  check "one fetch" "1" (ints (calls ()));
  check "fetched url" "http://localhost/issue/1" (call_url 0);
  check "header" "-" (call_header 0);
  check "not pushed before the page loaded" "/start?x=1" (location_ ());
  check "body unchanged while loading" (page {|<a id="l" href="/issue/1"><span id="in">go</span></a>|}) (body_html ());
  resolve_call 0 (doc "Issue 1" (page "<p>one</p>")) "";
  tick (fun () ->
      check "body swapped" (page "<p>one</p>") (body_html ());
      check "title" "Issue 1" (title ());
      check "pushed" "/issue/1" (location_ ());
      finish ())

let not_intercepted finish =
  let cases =
    [
      ("ctrl", {|<a id="l" href="/a">x</a>|}, "ctrl");
      ("meta", {|<a id="l" href="/a">x</a>|}, "meta");
      ("shift", {|<a id="l" href="/a">x</a>|}, "shift");
      ("alt", {|<a id="l" href="/a">x</a>|}, "alt");
      ("middle button", {|<a id="l" href="/a">x</a>|}, "middle");
      ("target blank", {|<a id="l" href="/a" target="_blank">x</a>|}, "");
      ("download", {|<a id="l" href="/a" download>x</a>|}, "");
      ("data-yuka-reload", {|<a id="l" href="/a" data-yuka-reload>x</a>|}, "");
      ("other origin", {|<a id="l" href="http://example.com/a">x</a>|}, "");
      ("other protocol", {|<a id="l" href="mailto:a@b.c">x</a>|}, "");
      ("fragment only", {|<a id="l" href="#top">x</a>|}, "");
      ("same page with fragment", {|<a id="l" href="/start?x=1#sec">x</a>|}, "");
    ]
  in
  List.iter
    (fun (name, link, flags) ->
      setup (page link);
      plain_start ();
      let prevented = click "#l" flags in
      check (name ^ ": not prevented") "false" (bools prevented);
      check (name ^ ": no fetch") "0" (ints (calls ())))
    cases;
  setup (page {|<a id="l" href="/a">x</a><button id="b">b</button><a id="n">no href</a>|});
  plain_start ();
  prevent_on "#l";
  ignore (click "#l" "");
  check "already prevented: no fetch" "0" (ints (calls ()));
  ignore (click "#b" "");
  ignore (click "#n" "");
  check "not links: no fetch" "0" (ints (calls ()));
  setup (page {|<a id="l" href="/start?x=2#sec">x</a><a id="m" href="/a" target="_self">y</a>|});
  plain_start ();
  check "other query with fragment is intercepted" "true" (bools (click "#l" ""));
  check "target _self is intercepted" "true" (bools (click "#m" ""));
  finish ()

let probe_runs = State.make 0

let probe_entry =
  runtime_entry ~name:"Probe" (fun json ->
      Result.map
        (fun n () ->
          Effect.run (fun () ->
              log ("g" ^ ints (State.get probe_runs) ^ "/" ^ ints n));
          element "span" [] [ text "p" ])
        (Codec.decode Codec.int json))

let island n =
  {|<yuka-island data-name="Probe" data-id="i1" style="display:contents"><span>p</span></yuka-island><script type="application/json" data-yuka-props="i1">|}
  ^ ints n ^ "</script>"

let stop_then_start finish =
  State.set probe_runs 0;
  setup (page ({|<a id="l" href="/two">x</a>|} ^ island 1));
  render ~islands:(runtime_registry [ probe_entry ]) ();
  check "first island started" "g0/1" (log_g ());
  ignore (click "#l" "");
  resolve_call 0 (doc "Two" (page (island 2))) "";
  tick (fun () ->
      check "new island started once" "g0/1|g0/2" (log_g ());
      State.set probe_runs 1;
      check "old island stopped" "g0/1|g0/2|g1/2" (log_g ());
      finish ())

let history_and_popstate finish =
  setup (page {|<a id="a" href="/a">a</a>|});
  plain_start ();
  let start_length = history_length () in
  ignore (click "#a" "");
  resolve_call 0 (doc "A" (page {|<a id="b" href="/b">b</a>|})) "";
  tick (fun () ->
      check "at a" "/a" (location_ ());
      check "one entry added" (ints (start_length + 1)) (ints (history_length ()));
      ignore (click "#b" "");
      resolve_call 1 (doc "B" (page "<p>bee</p>")) "";
      tick (fun () ->
          check "at b" "/b" (location_ ());
          check "two entries added" (ints (start_length + 2)) (ints (history_length ()));
          back ();
          tick (fun () ->
              check "back fetches a" "3" (ints (calls ()));
              check "relative url" "/a" (call_url 2);
              check "header on back" "-" (call_header 2);
              check "location is a" "/a" (location_ ());
              resolve_call 2 (doc "A again" (page "<p>ay</p>")) "";
              tick (fun () ->
                  check "body of a" (page "<p>ay</p>") (body_html ());
                  check "title of a" "A again" (title ());
                  check "no push on popstate" (ints (start_length + 2)) (ints (history_length ()));
                  forward ();
                  tick (fun () ->
                      check "forward fetches b" "/b" (call_url 3);
                      resolve_call 3 (doc "B" (page "<p>bee</p>")) "";
                      tick (fun () ->
                          check "body of b" (page "<p>bee</p>") (body_html ());
                          check "still no push" (ints (start_length + 2)) (ints (history_length ()));
                          finish ()))))))

let scrolling finish =
  setup (page {|<a id="a" href="/a">a</a>|});
  plain_start ();
  set_scroll 300.;
  ignore (click "#a" "");
  resolve_call 0 (doc "A" (page {|<a id="b" href="/b">b</a>|})) "";
  tick (fun () ->
      check "top on new page" "scroll:0" (log_read ());
      set_scroll 50.;
      ignore (click "#b" "");
      resolve_call 1 (doc "B" (page "b")) "";
      tick (fun () ->
          log_clear ();
          back ();
          tick (fun () ->
              resolve_call 2 (doc "A" (page "a")) "";
              tick (fun () ->
                  check "restored on back" "scroll:50" (log_read ());
                  log_clear ();
                  back ();
                  tick (fun () ->
                      resolve_call 3 (doc "S" (page "s")) "";
                      tick (fun () ->
                          check "restored on second back" "scroll:300" (log_read ());
                          finish ()))))))

let fragment_scroll finish =
  setup (page {|<a id="a" href="/a#sec">a</a>|});
  plain_start ();
  ignore (click "#a" "");
  resolve_call 0 (doc "A" (page {|<h2 id="sec">s</h2>|})) "";
  tick (fun () ->
      check "scrolls to the fragment" "into:sec" (log_read ());
      check "fragment in location" "/a#sec" (location_ ());
      finish ())

let superseded finish =
  setup (page {|<a id="a" href="/a">a</a><a id="b" href="/b">b</a>|});
  plain_start ();
  ignore (click "#a" "");
  ignore (click "#b" "");
  check "two fetches" "2" (ints (calls ()));
  check "first aborted" "true" (bools (call_aborted 0));
  check "second not aborted" "false" (bools (call_aborted 1));
  resolve_call 0 (doc "A" (page "<p>aaa</p>")) "";
  resolve_call 1 (doc "B" (page "<p>bbb</p>")) "";
  tick (fun () ->
      check "only the second page" (page "<p>bbb</p>") (body_html ());
      check "location" "/b" (location_ ());
      finish ())

let superseded_late_response finish =
  setup (page {|<a id="a" href="/a">a</a><a id="b" href="/b">b</a>|});
  ignore_abort ();
  plain_start ();
  ignore (click "#a" "");
  ignore (click "#b" "");
  resolve_call 1 (doc "B" (page "<p>bbb</p>")) "";
  tick (fun () ->
      resolve_call 0 (doc "A" (page "<p>aaa</p>")) "";
      tick (fun () ->
          check "late response of an aborted request is dropped" (page "<p>bbb</p>") (body_html ());
          check "location" "/b" (location_ ());
          finish ()))

let failure_falls_back finish =
  setup (page {|<a id="a" href="/a">a</a>|});
  plain_start ();
  let before = body_html () in
  ignore (click "#a" "");
  reject_call 0;
  tick (fun () ->
      check "full page load" "assign" (log_read ());
      check "body kept" before (body_html ());
      check "not pushed" "/start?x=1" (location_ ());
      finish ())

let sync_failure_falls_back finish =
  setup (page {|<a id="a" href="/a">a</a>|});
  plain_start ();
  fail_sync ();
  ignore (click "#a" "");
  check "full page load" "assign" (log_read ());
  finish ()

let redirect finish =
  setup (page {|<a id="a" href="/a">a</a>|});
  plain_start ();
  ignore (click "#a" "");
  resolve_call 0 (doc "Login" (page "<p>login</p>")) "http://localhost/login?next=%2Fa";
  tick (fun () ->
      check "history shows the final url" "/login?next=%2Fa" (location_ ());
      log_clear ();
      Browser.navigate "/b";
      resolve_call 1 (doc "Away" (page "x")) "http://example.com/b";
      tick (fun () ->
          check "cross-origin redirect: full page load" "assign" (log_read ());
          check "location kept" "/login?next=%2Fa" (location_ ());
          finish ()))

let navigate_api finish =
  setup (page "<p>old</p>");
  plain_start ();
  Browser.navigate "/x?q=1";
  check "fetch" "/x?q=1" (call_url 0);
  check "header" "-" (call_header 0);
  resolve_call 0 (doc "X" (page "<p>new</p>")) "";
  tick (fun () ->
      check "body" (page "<p>new</p>") (body_html ());
      check "location" "/x?q=1" (location_ ());
      finish ())

let start_twice finish =
  setup (page {|<a id="a" href="/a">a</a>|});
  plain_start ();
  plain_start ();
  ignore (click "#a" "");
  resolve_call 0 (doc "A" (page "a")) "";
  tick (fun () ->
      back ();
      tick (fun () ->
          check "one fetch for the click and one for back" "2" (ints (calls ()));
          finish ()))

let browser_navigate finish =
  setup (page "<p>old</p>");
  plain_start ();
  Browser.navigate "/x";
  check "client navigation: fetch" "/x" (call_url 0);
  check "header" "-" (call_header 0);
  resolve_call 0 (doc "X" (page "<p>x</p>")) "";
  tick (fun () ->
      check "body" (page "<p>x</p>") (body_html ());
      Browser.navigate "/y";
      check "still client navigation after a navigation" "2" (ints (calls ()));
      check "no full load" "scroll:0" (log_read ());
      finish ())

let script_urls = [ " javascript:alert(1)"; "JavaScript:alert(1)"; "java\tscript:alert(1)"; "vbscript:x"; "data:text/html,x" ]

let navigate_refuses_scripts finish =
  setup (page "<p>old</p>");
  List.iter Browser.navigate script_urls;
  check "off: no page load" "" (log_read ());
  plain_start ();
  List.iter Browser.navigate script_urls;
  check "on: no fetch" "0" (ints (calls ()));
  check "on: no page load" "" (log_read ());
  Browser.navigate "/ok";
  check "a path still navigates" "/ok" (call_url 0);
  finish ()

let start_twice_listeners finish =
  setup (page "x");
  count_listeners ();
  plain_start ();
  let first = listeners () in
  plain_start ();
  let second = listeners () in
  check "second start adds no listener" first second;
  check "popstate once" "1" (List.nth (String.split_on_char ',' second) 1);
  finish ()

let mount_without_navigation finish =
  State.set probe_runs 0;
  setup (page ({|<a id="l" href="/two">x</a>|} ^ island 3));
  render ~islands:(runtime_registry [ probe_entry ]) ~navigation:false ();
  check "island started" "g0/3" (log_g ());
  check "click not intercepted" "false" (bools (click "#l" ""));
  check "no fetch" "0" (ints (calls ()));
  check "page not swapped" "/start?x=1" (location_ ());
  finish ()

let mount_with_navigation finish =
  State.set probe_runs 0;
  setup (page ({|<a id="l" href="/two">x</a>|} ^ island 4));
  render ~islands:(runtime_registry [ probe_entry ]) ();
  check "island started" "g0/4" (log_g ());
  check "click intercepted" "true" (bools (click "#l" ""));
  check "one fetch" "1" (ints (calls ()));
  finish ()

let popstate_to : string -> unit =
  [%mel.raw
    "function (url) { window.history.pushState(null, '', url); window.dispatchEvent(new window.PopStateEvent('popstate')) }"]

let unmount_stops_navigation finish =
  State.set probe_runs 0;
  setup (page ({|<a id="l" href="/two">x</a>|} ^ island 5));
  render ~islands:(runtime_registry [ probe_entry ]) ();
  check "island started" "g0/5" (log_g ());
  stop ();
  check "click not intercepted after stop" "false" (bools (click "#l" ""));
  popstate_to "/back";
  check "no fetch for a click or popstate" "0" (ints (calls ()));
  log_clear ();
  Browser.navigate "/x";
  check "Browser.navigate is a page load" "assign" (log_read ());
  check "still no fetch" "0" (ints (calls ()));
  State.set probe_runs 1;
  check "island stopped and not started again" "" (log_g ());
  finish ()

let unmount_cancels_in_flight finish =
  State.set probe_runs 0;
  setup (page ({|<a id="l" href="/two">x</a>|} ^ island 6));
  render ~islands:(runtime_registry [ probe_entry ]) ();
  ignore (click "#l" "");
  stop ();
  check "request aborted" "true" (bools (call_aborted 0));
  let before = body_html () in
  ignore_abort ();
  resolve_call 0 (doc "Two" (page (island 7))) "";
  tick (fun () ->
      check "body kept" before (body_html ());
      check "location kept" "/start?x=1" (location_ ());
      check "no island started after stop" "g0/6" (log_g ());
      finish ())

let mount_after_unmount finish =
  State.set probe_runs 0;
  setup (page ({|<a id="l" href="/two">x</a>|} ^ island 8));
  count_listeners ();
  render ~islands:(runtime_registry [ probe_entry ]) ();
  stop ();
  render ~islands:(runtime_registry [ probe_entry ]) ();
  check "island started twice" "g0/8|g0/8" (log_g ());
  check "click intercepted again" "true" (bools (click "#l" ""));
  check "one fetch for one click" "1" (ints (calls ()));
  popstate_to "/back";
  check "one fetch for one popstate" "2" (ints (calls ()));
  check "listeners added once per mount" "2,2" (listeners ());
  finish ()

let shown_in_place status finish =
  setup (page {|<a id="a" href="/a">a</a>|});
  plain_start ();
  ignore (click "#a" "");
  resolve_with 0 (doc "Err" (page "<p>err</p>")) "" status "text/html";
  tick (fun () ->
      check "no full load" "scroll:0" (log_read ());
      check "page shown" (page "<p>err</p>") (body_html ());
      check "pushed" "/a" (location_ ());
      finish ())

let island_at id n =
  {|<yuka-island data-name="Probe" data-id="|} ^ id
  ^ {|" style="display:contents"><span>p</span></yuka-island><script type="application/json" data-yuka-props="|}
  ^ id ^ "\">" ^ ints n ^ "</script>"

let set_body : string -> unit = [%mel.raw "function (h) { document.body.innerHTML = h }"]
let set_head : string -> unit = [%mel.raw "function (h) { document.head.innerHTML = h }"]
let attr : string -> string -> string =
  [%mel.raw "function (sel, name) { const e = document.querySelector(sel); return e ? String(e.getAttribute(name)) : 'none' }"]

let outlet_page () =
  set_head {|<title>start</title><meta name="yuka-build" content="b1">|};
  (set_body
       ({|<nav><a id="home" href="/start" aria-current="page">home</a><a id="two" href="/two">two</a><a id="step" href="/x" aria-current="step">x</a><a id="twoloc" href="/two" aria-current="location">2</a></nav>|}
       ^ island_at "i1" 1
       ^ {|<yuka-island data-name="Probe" data-id="i9" data-start="interaction" style="display:contents"><a id="isl" href="/two">i</a></yuka-island><script type="application/json" data-yuka-props="i9">9</script>|}
       ^ {|<yuka-outlet data-k="L0" style="display:contents"><p id="old">old</p>|}
       ^ island_at "i2" 2 ^ "</yuka-outlet>"))

let partial finish =
  State.set probe_runs 0;
  setup "";
  outlet_page ();
  render ~islands:(runtime_registry [ probe_entry ]) ();
  check "both islands started" "g0/1|g0/2" (log_g ());
  ignore (click "#two" "");
  check "keys sent" "L0" (call_header 0);
  resolve_headers 0
    ({|<p id="new">new</p><a id="inner" href="/two">two</a>|} ^ island_at "L0-i1" 3)
    200
    [| ("yuka-outlet", "L0"); ("yuka-title", "Caf%C3%A9"); ("yuka-build", "b1") |];
  tick (fun () ->
      check "outlet replaced" "none" (attr "#old" "id");
      check "new content" "new" (attr "#new" "id");
      check "layout kept" "/two" (attr "#two" "href");
      check "title" {js|Café|js} (title ());
      check "pushed" "/two" (location_ ());
      check "link of the new path marked" "page" (attr "#two" "aria-current");
      check "old mark removed" "null" (attr "#home" "aria-current");
      check "other value kept" "step" (attr "#step" "aria-current");
      check "links inside an island untouched" "null" (attr "#isl" "aria-current");
      check "another value on the new path is kept" "location" (attr "#twoloc" "aria-current");
      check "new island started, outer not again" "g0/1|g0/2|g0/3" (log_g ());
      log_clear ();
      State.set probe_runs 1;
      check "outer kept, inner stopped, new running" "g1/3|g1/1" (log_g ());
      finish ())

let attr_text : string -> string =
  [%mel.raw "function (sel) { const e = document.querySelector(sel); return e ? e.textContent : 'none' }"]
let document_session_set : string -> string -> unit =
  [%mel.raw "function (k, v) { document.defaultView.sessionStorage.setItem(k, v) }"]
let fire_load : unit -> unit =
  [%mel.raw "function () { document.defaultView.dispatchEvent(new document.defaultView.Event('load')) }"]

let sheets : string -> string =
  [%mel.raw
    {|function (where) {
  return Array.from(document.querySelectorAll(where + " link[data-yuka-css]")).map(function (l) { return l.getAttribute("href") }).join(",")
}|}]

let css_link href = {|<link rel="stylesheet" href="|} ^ href ^ {|" data-yuka-css>|}

let partial_css finish =
  setup "";
  outlet_page ();
  set_head ({|<title>start</title><meta name="yuka-build" content="b1">|} ^ css_link "/_yuka/css/a.css");
  plain_start ();
  ignore (click "#two" "");
  resolve_headers 0
    (css_link "/_yuka/css/a.css" ^ css_link "/_yuka/css/b.css" ^ {|<p id="new">new</p>|})
    200
    [| ("yuka-outlet", "L0"); ("yuka-build", "b1") |];
  tick (fun () ->
      check "new sheets moved to the head, no duplicate" "/_yuka/css/a.css,/_yuka/css/b.css" (sheets "head");
      check "none left in the body" "" (sheets "body");
      check "content swapped" "new" (attr "#new" "id");
      ignore (click "#home" "");
      resolve_headers 1 {|<p id="back">back</p>|} 200 [| ("yuka-outlet", "L0"); ("yuka-build", "b1") |];
      tick (fun () ->
          check "the sheets stay after the next swap" "/_yuka/css/a.css,/_yuka/css/b.css" (sheets "head");
          finish ()))

let first_load_css finish =
  setup "";
  set_head {|<title>start</title><meta name="yuka-build" content="b1">|};
  set_body
    ({|<nav><a id="two" href="/two">two</a></nav><yuka-outlet data-k="L0" style="display:contents">|}
    ^ css_link "/_yuka/css/a.css" ^ {|<p class="a_1">in</p></yuka-outlet><p class="a_1">out</p>|});
  plain_start ();
  check "moved to the head at start" "/_yuka/css/a.css" (sheets "head");
  ignore (click "#two" "");
  resolve_headers 0 {|<p id="new">new</p>|} 200 [| ("yuka-outlet", "L0"); ("yuka-build", "b1") |];
  tick (fun () ->
      check "content outside the outlet keeps its sheet" "/_yuka/css/a.css" (sheets "");
      finish ())

let full_swap_css finish =
  setup (page {|<a id="l" href="/issue/1">go</a>|});
  plain_start ();
  ignore (click "#l" "");
  resolve_call 0 (doc "Issue 1" (css_link "/_yuka/css/c.css" ^ page "<p>one</p>")) "";
  tick (fun () ->
      check "sheet of the new page in the head" "/_yuka/css/c.css" (sheets "head");
      check "body without it" (page "<p>one</p>") (body_html ());
      finish ())

let run_dev : string -> unit =
  [%mel.raw
    {|function (html) {
  var w = document.defaultView;
  w.EventSource = function (url) { globalThis.__es = this; this.url = url; };
  w.scrollTo = function (x, y) { globalThis.__log.push("scroll:" + y); };
  var code = html.replace(/^<script>/, "").replace(/<\/script>$/, "");
  new Function("window", "with (window) {" + code + "}")(w);
}|}]

let dev_send : string -> unit =
  [%mel.raw {|function (data) { globalThis.__es.onmessage({ data: data }) }|}]

let dev_url : unit -> string = [%mel.raw {|function () { return globalThis.__es.url }|}]
let session : string -> string =
  [%mel.raw {|function (k) { return String(document.defaultView.sessionStorage.getItem(k)) }|}]

let dev_page () =
  setup "";
  set_head
    ({|<link rel="stylesheet" href="/static/s.css"><link rel="stylesheet" href="/_yuka/css/a-1.css" data-yuka-css>|}
    ^ {|<link rel="stylesheet" href="https://cdn.example/x.css">|});
  set_body "<p>x</p>";
  run_dev (Private.dev_script {|{"session":"a","build":2,"page":1,"error":null}|})

let dev_reload finish =
  dev_page ();
  check "listens on /_yuka/dev" "/_yuka/dev" (dev_url ());
  dev_send {|{"session":"a","build":2,"page":1,"error":null}|};
  check "same build: nothing" "" (log_read ());
  dev_send {|{"session":"a","build":3,"page":3,"error":null}|};
  check "a new page build reloads" "assign" (log_read ());
  check "the scroll is kept for the next page" "0" (session "yuka-dev-scroll");
  finish ()

let dev_session finish =
  dev_page ();
  dev_send {|{"session":"b","build":1,"page":1,"error":null}|};
  check "a new yuka dev session reloads, also with lower numbers" "assign" (log_read ());
  finish ()

let dev_css finish =
  dev_page ();
  dev_send {|{"session":"a","build":3,"page":1,"error":null}|};
  check "no reload" "" (log_read ());
  check "the stylesheet gets the build" "http://localhost/static/s.css?v=3" (attr {|link[href*="/static/"]|} "href");
  check "another origin is left alone" "https://cdn.example/x.css" (attr {|link[href*="cdn"]|} "href");
  check "a /_yuka/css sheet is left alone" "/_yuka/css/a-1.css" (attr "link[data-yuka-css]" "href");
  finish ()

let dev_error finish =
  dev_page ();
  dev_send {|{"session":"a","build":2,"page":1,"error":"File a.ml: Error"}|};
  check "the overlay shows the error" "File a.ml: Error" (attr_text "#yuka-dev-error");
  check "no reload" "" (log_read ());
  dev_send {|{"session":"a","build":3,"page":3,"error":null}|};
  check "the overlay goes away" "none" (attr_text "#yuka-dev-error");
  check "then the reload" "assign" (log_read ());
  finish ()

let after_scroll finish =
  setup "";
  document_session_set "yuka-dev-scroll" "250";
  run_dev (Private.dev_script {|{"session":"a","build":1,"page":1,"error":null}|});
  fire_load ();
  check "the scroll position is restored on load" "scroll:250" (log_read ());
  check "and forgotten" "null" (session "yuka-dev-scroll");
  finish ()

let stale_build finish =
  setup "";
  outlet_page ();
  plain_start ();
  ignore (click "#two" "");
  resolve_headers 0 "<p>new</p>" 200 [| ("yuka-outlet", "L0"); ("yuka-build", "b2") |];
  tick (fun () ->
      check "full page load" "assign" (log_read ());
      check "outlet kept" "old" (attr "#old" "id");
      finish ())

let unknown_outlet finish =
  setup "";
  outlet_page ();
  plain_start ();
  ignore (click "#two" "");
  resolve_headers 0 "<p>part</p>" 200 [| ("yuka-outlet", "L9"); ("yuka-build", "b1") |];
  tick (fun () ->
      check "full page load" "assign" (log_read ());
      check "outlet kept" "old" (attr "#old" "id");
      check "not pushed" "/start?x=1" (location_ ());
      finish ())

let bad_title finish =
  setup "";
  outlet_page ();
  plain_start ();
  ignore (click "#two" "");
  resolve_headers 0 {|<p id="new">new</p>|} 200
    [| ("yuka-outlet", "L0"); ("yuka-title", "%E0%A4%A"); ("yuka-build", "b1") |];
  tick (fun () ->
      check "outlet replaced" "new" (attr "#new" "id");
      check "raw title" "%E0%A4%A" (title ());
      check "pushed" "/two" (location_ ());
      finish ())

let act = Action.mutation ~name:"act" ~input:Codec.string ~output:Codec.string

let actor_entry =
  runtime_entry ~name:"Actor" (fun json ->
      Result.map
        (fun (_ : int) () ->
          element "button"
            [ on "click" (fun _ -> ignore (Action.call act "go")) ]
            [ text "act" ])
        (Codec.decode Codec.int json))

let actions_of_stopped_islands finish =
  setup "";
  set_head {|<title>start</title><meta name="yuka-build" content="b1">|};
  set_body
    ({|<a id="two" href="/two">two</a>|}
    ^ {|<yuka-island data-name="Actor" data-id="i1" style="display:contents"><button id="outer">act</button></yuka-island><script type="application/json" data-yuka-props="i1">1</script>|}
    ^ {|<yuka-outlet data-k="L0" style="display:contents"><yuka-island data-name="Actor" data-id="i2" style="display:contents"><button id="inner">act</button></yuka-island><script type="application/json" data-yuka-props="i2">2</script></yuka-outlet>|});
  render ~islands:(runtime_registry [ actor_entry ]) ();
  ignore (click "#inner" "");
  ignore (click "#outer" "");
  check "two action calls" "2" (ints (calls ()));
  ignore (click "#two" "");
  let nav = calls () - 1 in
  resolve_headers nav "<p>new</p>" 200 [| ("yuka-outlet", "L0"); ("yuka-build", "b1") |];
  tick (fun () ->
      check "inner island action aborted" "true" (bools (call_aborted 0));
      check "outer island action still running" "false" (bools (call_aborted 1));
      finish ())

let rerender_entry =
  runtime_entry ~name:"Rerender" (fun json ->
      Result.map
        (fun (_ : int) () ->
          let n = State.make 0 in
          hole (fun () ->
              let v = State.get n in
              element "button"
                [ Yuka.attr "id" "b";
                  on "click" (fun _ ->
                      State.set n (v + 1);
                      ignore (Action.call act "go")) ]
                [ text (string_of_int v) ]))
        (Codec.decode Codec.int json))

let action_survives_own_render finish =
  setup "";
  set_head {|<title>start</title><meta name="yuka-build" content="b1">|};
  set_body
    {|<yuka-island data-name="Rerender" data-id="i1" style="display:contents"><!--[--><button id="b">0</button><!--]--></yuka-island><script type="application/json" data-yuka-props="i1">1</script>|};
  render ~islands:(runtime_registry [ rerender_entry ]) ();
  ignore (click "#b" "");
  tick (fun () ->
      check "the handler's write rendered its button again" "1" (attr_text "#b");
      check "one action call" "1" (ints (calls ()));
      check "the call is not aborted by that render" "false" (bools (call_aborted 0));
      finish ())

let not_a_page status type_ finish =
  setup (page {|<a id="a" href="/a">a</a>|});
  plain_start ();
  let before = body_html () in
  ignore (click "#a" "");
  resolve_with 0 (doc "Err" (page "<p>err</p>")) "" status type_;
  tick (fun () ->
      check "full page load" "assign" (log_read ());
      check "body kept" before (body_html ());
      check "not pushed" "/start?x=1" (location_ ());
      finish ())

let fire : string -> string -> unit =
  [%mel.raw
    "function (sel, name) { document.querySelector(sel).dispatchEvent(new window.MouseEvent(name, { bubbles: true })) }"]

let prefetch_header : int -> string =
  [%mel.raw "function (i) { return String(globalThis.__calls[i].init.headers['Yuka-Prefetch']) }"]

let advance : int -> unit = [%mel.raw "function (ms) { globalThis.__now += ms }"]

let save_data : unit -> unit =
  [%mel.raw "function () { Object.defineProperty(window.navigator, 'connection', { value: { saveData: true }, configurable: true }) }"]

let stub_observer : unit -> unit =
  [%mel.raw
    {|function () {
  const seen = globalThis.__observed = [];
  window.IntersectionObserver = function (cb) {
    this.cb = cb;
    this.observe = function (el) { seen.push({ el: el, cb: cb, o: this }); };
    this.unobserve = function () {};
    this.disconnect = function () { seen.length = 0; };
  };
}|}]

let observed : unit -> string =
  [%mel.raw "function () { return globalThis.__observed.map(function (x) { return x.el.id }).join(',') }"]

let intersect : string -> unit =
  [%mel.raw
    {|function (id) {
  const x = globalThis.__observed.find(function (x) { return x.el.id === id; });
  x.cb([{ isIntersecting: true, target: x.el }]);
}|}]

let stub_transition : unit -> unit =
  [%mel.raw
    {|function () {
  document.startViewTransition = function (cb) {
    globalThis.__log.push("vt:" + document.documentElement.getAttribute("data-yuka-nav"));
    cb();
    return { ready: Promise.reject(new Error("Transition was skipped")), finished: Promise.resolve() };
  };
}|}]

let nav_attr : unit -> string =
  [%mel.raw "function () { return String(document.documentElement.getAttribute('data-yuka-nav')) }"]

let prefetch_cache : int -> string =
  [%mel.raw "function (i) { return String(globalThis.__calls[i].init.cache) }"]

let wait ms f = set_timeout (fun () -> try f () with e -> !fail_hook e) ms
let links = page {|<a id="l" href="/two">two</a><a id="m" href="/three">three</a>|}
let cached text max_age = (text, [| ("cache-control", "private, max-age=" ^ ints max_age) |])

let hover_prefetch finish =
  setup links;
  plain_start ();
  fire "#l" "pointerover";
  wait 10 (fun () ->
      check "no fetch before 50 ms" "0" (ints (calls ()));
      wait 60 (fun () ->
          check "one prefetch" "1" (ints (calls ()));
          check "prefetch header" "1" (prefetch_header 0);
          check "a prefetch skips the HTTP cache" "no-store" (prefetch_cache 0);
          check "outlet keys" "-" (call_header 0);
          check "click is intercepted" "true" (bools (click "#l" ""));
          check "the click uses the prefetch" "1" (ints (calls ()));
          resolve_call 0 (doc "Two" (page "<p>two</p>")) "";
          tick (fun () ->
              check "page shown" (page "<p>two</p>") (body_html ());
              check "pushed" "/two" (location_ ());
              check "a navigation has no prefetch header" "1" (ints (calls ()));
              finish ())))

let hover_out finish =
  setup links;
  plain_start ();
  fire "#l" "pointerover";
  wait 20 (fun () ->
      fire "#l" "pointerout";
      wait 80 (fun () ->
          check "no prefetch after leaving" "0" (ints (calls ()));
          fire "#l" "focusin";
          wait 80 (fun () ->
              check "focus prefetches" "1" (ints (calls ()));
              finish ())))

let not_prefetched finish =
  List.iter
    (fun (name, link) ->
      setup (page link);
      plain_start ();
      fire "#l" "pointerdown";
      check (name ^ ": no prefetch") "0" (ints (calls ())))
    [ ("off", {|<a id="l" href="/a" data-yuka-prefetch="off">x</a>|});
      ("download", {|<a id="l" href="/a" download>x</a>|});
      ("other origin", {|<a id="l" href="http://example.com/a">x</a>|});
      ("target blank", {|<a id="l" href="/a" target="_blank">x</a>|});
      ("reload", {|<a id="l" href="/a" data-yuka-reload>x</a>|}) ];
  setup links;
  save_data ();
  plain_start ();
  fire "#l" "pointerdown";
  check "save data: no prefetch" "0" (ints (calls ()));
  setup links;
  render ~islands:(runtime_registry []) ~prefetch:`Off ();
  fire "#l" "pointerdown";
  check "prefetch off: no prefetch" "0" (ints (calls ()));
  check "prefetch off: click still navigates" "true" (bools (click "#l" ""));
  check "one navigation" "1" (ints (calls ()));
  setup links;
  plain_start ();
  fire "#l" "pointerdown";
  fire "#l" "touchstart";
  check "pointer down prefetches at once, once" "1" (ints (calls ()));
  finish ()

let visible finish =
  setup (page {|<a id="v" href="/two" data-yuka-prefetch="visible">v</a><a id="h" href="/three">h</a>|});
  stub_observer ();
  plain_start ();
  check "only marked links observed" "v" (observed ());
  intersect "v";
  check "a visible link prefetches" "1" (ints (calls ()));
  intersect "v";
  check "a link in flight is not prefetched again" "1" (ints (calls ()));
  setup (page {|<a id="v" href="/two">v</a><a id="o" href="/three" data-yuka-prefetch="off">o</a>|});
  stub_observer ();
  render ~islands:(runtime_registry []) ~prefetch:`Visible ();
  check "visible mode observes every link" "v,o" (observed ());
  intersect "o";
  check "off still wins" "0" (ints (calls ()));
  finish ()

let max_age_cache finish =
  setup links;
  plain_start ();
  ignore (click "#l" "");
  let text, headers = cached (doc "Two" (page {|<a id="m" href="/three">three</a><a id="l" href="/two">two</a>|})) 60 in
  resolve_headers 0 text 200 headers;
  tick (fun () ->
      ignore (click "#m" "");
      resolve_call 1 (doc "Three" (page {|<a id="l" href="/two">two</a>|})) "";
      tick (fun () ->
          advance 59000;
          ignore (click "#l" "");
          check "within max-age: no fetch" "2" (ints (calls ()));
          check "shown from the cache" "/two" (location_ ());
          check "title from the cache" "Two" (title ());
          ignore (click "#m" "");
          resolve_call 2 (doc "Three" (page {|<a id="l" href="/two">two</a>|})) "";
          tick (fun () ->
              advance 2000;
              ignore (click "#l" "");
              check "after max-age: one fetch" "4" (ints (calls ()));
              finish ())))

let back_forward_cache finish =
  setup links;
  plain_start ();
  ignore (click "#l" "");
  let text, headers = cached (doc "Two" (page "<p>two</p>")) 60 in
  resolve_headers 0 text 200 headers;
  tick (fun () ->
      back ();
      tick (fun () ->
          check "the start page is fetched" "2" (ints (calls ()));
          resolve_call 1 (doc "start" links) "";
          tick (fun () ->
              forward ();
              tick (fun () ->
                  check "forward uses the cache" "2" (ints (calls ()));
                  check "shown" (page "<p>two</p>") (body_html ());
                  finish ()))))

let no_store_once finish =
  setup links;
  plain_start ();
  fire "#l" "pointerdown";
  resolve_call 0 (doc "Two" (page {|<a id="m" href="/three">three</a><a id="l" href="/two">two</a>|})) "";
  tick (fun () ->
      advance 9000;
      ignore (click "#l" "");
      check "a prefetch is used within 10 s" "1" (ints (calls ()));
      ignore (click "#m" "");
      resolve_call 1 (doc "Three" (page {|<a id="l" href="/two">two</a>|})) "";
      tick (fun () ->
          ignore (click "#l" "");
          check "used once only" "3" (ints (calls ()));
          setup links;
          plain_start ();
          fire "#l" "pointerdown";
          resolve_call 0 (doc "Two" (page "<p>two</p>")) "";
          tick (fun () ->
              advance 11000;
              ignore (click "#l" "");
              check "an old prefetch is not used" "2" (ints (calls ()));
              finish ())))

let rerendered_call_aborted_by_outlet finish =
  setup "";
  set_head {|<title>start</title><meta name="yuka-build" content="b1">|};
  set_body
    ({|<a id="two" href="/two">two</a>|}
    ^ {|<yuka-outlet data-k="L0" style="display:contents"><yuka-island data-name="Rerender" data-id="i1" style="display:contents"><!--[--><button id="b">0</button><!--]--></yuka-island><script type="application/json" data-yuka-props="i1">1</script></yuka-outlet>|});
  render ~islands:(runtime_registry [ rerender_entry ]) ();
  ignore (click "#b" "");
  tick (fun () ->
      check "not aborted by the render" "false" (bools (call_aborted 0));
      ignore (click "#two" "");
      resolve_headers 1 "<p>new</p>" 200 [| ("yuka-outlet", "L0"); ("yuka-build", "b1") |];
      tick (fun () ->
          check "aborted when the outlet stops its island" "true" (bools (call_aborted 0));
          finish ()))

let leaver_entry =
  runtime_entry ~name:"Leaver" (fun json ->
      Result.map
        (fun (_ : int) () ->
          element "button"
            [ Yuka.attr "id" "go";
              on "click" (fun _ ->
                  ignore (Action.call act "go");
                  Browser.navigate "/two") ]
            [ text "go" ])
        (Codec.decode Codec.int json))

let call_then_navigate_aborted finish =
  setup "";
  set_head {|<title>start</title><meta name="yuka-build" content="b1">|};
  set_body
    ({|<a id="l" href="/two">two</a>|}
    ^ {|<yuka-outlet data-k="L0" style="display:contents"><yuka-island data-name="Leaver" data-id="i1" style="display:contents"><button id="go">go</button></yuka-island><script type="application/json" data-yuka-props="i1">1</script></yuka-outlet>|});
  render ~islands:(runtime_registry [ leaver_entry ]) ();
  fire "#l" "pointerdown";
  resolve_headers 0 "<p>new</p>" 200
    [| ("yuka-outlet", "L0"); ("yuka-build", "b1"); ("cache-control", "private, max-age=60") |];
  tick (fun () ->
      ignore (click "#go" "");
      let action = calls () - 1 in
      tick (fun () ->
          check "the page changed" "/two" (location_ ());
          check "the call of the stopped island is aborted" "true" (bools (call_aborted action));
          finish ()))

let set_outlet_key : string -> unit =
  [%mel.raw "function (k) { document.querySelector('yuka-outlet').setAttribute('data-k', k) }"]

let keys_miss finish =
  setup (page {|<a id="l" href="/two">two</a><yuka-outlet data-k="L0"><p>x</p></yuka-outlet>|});
  plain_start ();
  fire "#l" "pointerdown";
  check "prefetch keys" "L0" (call_header 0);
  set_outlet_key "L1";
  ignore (click "#l" "");
  check "other keys: a new fetch" "2" (ints (calls ()));
  check "new keys" "L1" (call_header 1);
  finish ()

let cached_stale_build finish =
  setup "";
  set_head {|<title>start</title><meta name="yuka-build" content="b1">|};
  set_body links;
  plain_start ();
  fire "#l" "pointerdown";
  resolve_headers 0 "<p>new</p>" 200 [| ("yuka-build", "b2") |];
  tick (fun () ->
      log_clear ();
      ignore (click "#l" "");
      check "no new fetch" "1" (ints (calls ()));
      tick (fun () ->
          check "another build is a full load" "assign" (log_read ());
          finish ()))

let action_clears finish =
  setup links;
  plain_start ();
  ignore (click "#l" "");
  let text, headers = cached (doc "Two" (page {|<a id="m" href="/three">three</a><a id="l" href="/two">two</a>|})) 60 in
  resolve_headers 0 text 200 headers;
  tick (fun () ->
      ignore (click "#m" "");
      resolve_call 1 (doc "Three" (page {|<a id="l" href="/two">two</a>|})) "";
      tick (fun () ->
          let failed = Action.call act "x" in
          resolve_with 2 {|{"error":"no"}|} "" 400 "application/json";
          tick (fun () ->
              check "failed action" "true" (bools (Async.status failed = Async.Done (Error (Status.Rejected "no"))));
              fire "#l" "pointerdown";
              check "a failed action keeps the cache" "3" (ints (calls ()));
              let ok = Action.call act "x" in
              resolve_with 3 {|{"ok":"y"}|} "" 200 "application/json";
              tick (fun () ->
                  check "action done" "true" (bools (Async.status ok = Async.Done (Ok "y")));
                  ignore (click "#l" "");
                  check "a successful action clears the cache" "5" (ints (calls ()));
                  finish ()))))

let waits_for_prefetch finish =
  setup links;
  plain_start ();
  fire "#l" "pointerdown";
  ignore (click "#l" "");
  ignore (click "#m" "");
  check "a newer navigation fetches" "2" (ints (calls ()));
  check "the prefetch is not aborted" "false" (bools (call_aborted 0));
  resolve_call 0 (doc "Two" (page "<p>two</p>")) "";
  tick (fun () ->
      check "the superseded navigation shows nothing" links (body_html ());
      resolve_call 1 (doc "Three" (page "<p>three</p>")) "";
      tick (fun () ->
          check "the last navigation wins" (page "<p>three</p>") (body_html ());
          finish ()))

let transitions_on finish =
  setup links;
  stub_transition ();
  render ~islands:(runtime_registry []) ~transitions:true ();
  ignore (click "#l" "");
  resolve_call 0 (doc "Two" (page "<p>two</p>")) "";
  tick (fun () ->
      check "one transition, push" "vt:push|scroll:0" (log_read ());
      check "shown" (page "<p>two</p>") (body_html ());
      back ();
      tick (fun () ->
          resolve_call 1 (doc "start" links) "";
          tick (fun () ->
              check "back" "vt:push|scroll:0|vt:back|scroll:0" (log_read ());
              check "attribute removed" "null" (nav_attr ());
              finish ())))

let transitions_off finish =
  setup links;
  stub_transition ();
  plain_start ();
  ignore (click "#l" "");
  resolve_call 0 (doc "Two" (page "<p>two</p>")) "";
  tick (fun () ->
      check "no transition by default" "scroll:0" (log_read ());
      setup links;
      render ~islands:(runtime_registry []) ~transitions:true ();
      ignore (click "#l" "");
      resolve_call 0 (doc "Two" (page "<p>two</p>")) "";
      tick (fun () ->
          check "no API: plain swap" (page "<p>two</p>") (body_html ());
          finish ()))

let down_cancels_hover finish =
  setup links;
  plain_start ();
  fire "#l" "pointerover";
  fire "#l" "pointerdown";
  ignore (click "#l" "");
  resolve_call 0 (doc "Two" (page {|<a id="l" href="/two">two</a>|})) "";
  wait 80 (fun () ->
      check "no second prefetch after the click" "1" (ints (calls ()));
      finish ())

let lookup_q = Action.query ~name:"lookup" ~input:Codec.string ~output:Codec.string

let remote_mutate_clears finish =
  setup links;
  plain_start ();
  ignore (click "#l" "");
  let text, headers = cached (doc "Two" (page {|<a id="m" href="/three">three</a><a id="l" href="/two">two</a>|})) 60 in
  resolve_headers 0 text 200 headers;
  tick (fun () ->
      ignore (click "#m" "");
      resolve_call 1 (doc "Three" (page {|<a id="l" href="/two">two</a>|})) "";
      tick (fun () ->
          let r, dispose = Yuka.owner (fun () -> Remote.use lookup_q (fun () -> "a")) in
          check "the query is sent" "3" (ints (calls ()));
          resolve_with 2 {|{"ok":"base"}|} "" 200 "application/json";
          tick (fun () ->
              fire "#l" "pointerdown";
              check "a query read keeps the cache" "3" (ints (calls ()));
              let failed = Remote.mutate r ~change:(fun d -> d ^ "!") (fun () -> Action.call act "x") in
              resolve_with 3 {|{"error":"no"}|} "" 400 "application/json";
              tick (fun () ->
                  check "mutate failed" "true" (bools (Async.status failed = Async.Done (Error (Status.Rejected "no"))));
                  fire "#l" "pointerdown";
                  check "a failed mutate keeps the cache" "4" (ints (calls ()));
                  let ok = Remote.mutate r ~change:(fun d -> d ^ "!") (fun () -> Action.call act "y") in
                  resolve_with 4 {|{"ok":"y"}|} "" 200 "application/json";
                  tick (fun () ->
                      check "mutate done" "true" (bools (Async.status ok = Async.Done (Ok "y")));
                      fire "#l" "pointerdown";
                      check "a successful mutate empties the cache" "6" (ints (calls ()));
                      dispose ();
                      finish ())))))

let fire_mouse : string -> string -> int -> bool -> unit =
  [%mel.raw
    "function (sel, name, button, ctrl) { document.querySelector(sel).dispatchEvent(new window.MouseEvent(name, { bubbles: true, cancelable: true, button: button, ctrlKey: ctrl })) }"]

let deferred_transitions : unit -> unit =
  [%mel.raw
    {|function () {
  const t = globalThis.__transitions = [];
  document.startViewTransition = function (cb) {
    let finish;
    const finished = new Promise(function (r) { finish = r; });
    t.push({ cb: cb, finish: finish });
    return { ready: Promise.resolve(), finished: finished };
  };
}|}]

let run_transition : int -> unit = [%mel.raw "function (i) { globalThis.__transitions[i].cb() }"]
let finish_transition : int -> unit = [%mel.raw "function (i) { globalThis.__transitions[i].finish() }"]
let transitions_count : unit -> int = [%mel.raw "function () { return globalThis.__transitions.length }"]
let scroll_throws : unit -> unit = [%mel.raw "function () { globalThis.__scrollThrows = true }"]

let raising_transition : unit -> unit =
  [%mel.raw
    {|function () {
  document.startViewTransition = function (cb) {
    try { cb(); } catch (e) { globalThis.__log.push("escaped:" + e.message); }
    return { ready: Promise.resolve(), finished: Promise.resolve() };
  };
}|}]

let action_after_navigation_started finish =
  setup links;
  plain_start ();
  ignore (click "#l" "");
  let _ = Action.call act "x" in
  resolve_with 1 {|{"ok":"y"}|} "" 200 "application/json";
  tick (fun () ->
      let text, headers = cached (doc "Two" (page {|<a id="m" href="/three">three</a><a id="l" href="/two">two</a>|})) 60 in
      resolve_headers 0 text 200 headers;
      tick (fun () ->
          check "shown" "/two" (location_ ());
          ignore (click "#m" "");
          resolve_call 2 (doc "Three" (page {|<a id="l" href="/two">two</a>|})) "";
          tick (fun () ->
              ignore (click "#l" "");
              check "an answer requested before the action is not kept" "4" (ints (calls ()));
              finish ())))

let clear_aborts_prefetch finish =
  setup links;
  plain_start ();
  fire "#l" "pointerdown";
  let _ = Action.call act "x" in
  resolve_with 1 {|{"ok":"y"}|} "" 200 "application/json";
  tick (fun () ->
      check "the dropped prefetch is aborted" "true" (bools (call_aborted 0));
      finish ())

let waiter_after_unmount finish =
  setup links;
  plain_start ();
  ignore_abort ();
  fire "#l" "pointerdown";
  ignore (click "#l" "");
  let _ = Action.call act "x" in
  resolve_with 1 {|{"ok":"y"}|} "" 200 "application/json";
  tick (fun () ->
      stop ();
      resolve_call 0 (doc "Two" (page "<p>two</p>")) "";
      tick (fun () ->
          check "no swap after stop" links (body_html ());
          check "no push" "/start?x=1" (location_ ());
          finish ()))

let popstate_cancels_waiter finish =
  setup links;
  plain_start ();
  fire "#l" "pointerdown";
  ignore (click "#l" "");
  popstate_to "/start?x=1";
  resolve_call 0 (doc "Two" (page "<p>two</p>")) "";
  tick (fun () ->
      check "a popstate to the shown page cancels the waiting navigation" links (body_html ());
      finish ())

let transition_token finish =
  setup links;
  deferred_transitions ();
  render ~islands:(runtime_registry []) ~transitions:true ();
  ignore (click "#l" "");
  resolve_call 0 (doc "Two" (page {|<a id="m" href="/three">three</a>|})) "";
  tick (fun () ->
      check "state is updated before the transition runs" "/two" (location_ ());
      check "the DOM waits for the callback" links (body_html ());
      run_transition 0;
      check "swapped in the callback" (page {|<a id="m" href="/three">three</a>|}) (body_html ());
      ignore (click "#m" "");
      resolve_call 1 (doc "Three" (page "<p>3</p>")) "";
      tick (fun () ->
          check "two transitions" "2" (ints (transitions_count ()));
          run_transition 1;
          finish_transition 0;
          tick (fun () ->
              check "an older transition does not remove the attribute" "push" (nav_attr ());
              finish_transition 1;
              tick (fun () ->
                  check "removed by the last one" "null" (nav_attr ());
                  finish ()))))

let transition_error finish =
  setup links;
  raising_transition ();
  render ~islands:(runtime_registry []) ~transitions:true ();
  ignore (click "#l" "");
  scroll_throws ();
  resolve_call 0 (doc "Two" (page "<p>two</p>")) "";
  tick (fun () ->
      wait 20 (fun () ->
          check "the error does not escape into the transition, it is reported"
            "jsdom:Uncaught [Error: scroll failed]" (log_read ());
          finish ()))

let eviction finish =
  let ids = List.init 31 (fun i -> "p" ^ ints i) in
  setup (page (String.concat "" (List.map (fun id -> {|<a id="|} ^ id ^ {|" href="/|} ^ id ^ {|">x</a>|}) ids)));
  plain_start ();
  List.iter (fun id -> fire ("#" ^ id) "pointerdown") ids;
  check "an evicted prefetch in flight is aborted" "true" (bools (call_aborted 0));
  check "the others are not" "false" (bools (call_aborted 1));
  finish ()

let replace_keeps_others finish =
  let ids = List.init 29 (fun i -> "p" ^ ints i) in
  setup (page ({|<a id="x" href="/x">x</a>|} ^ String.concat "" (List.map (fun id -> {|<a id="|} ^ id ^ {|" href="/|} ^ id ^ {|">x</a>|}) ids)));
  plain_start ();
  List.iter (fun id -> fire ("#" ^ id) "pointerdown") ids;
  Browser.navigate "/x";
  fire "#x" "pointerdown";
  check "30 entries" "31" (ints (calls ()));
  let text, headers = cached (doc "X" (page "<p>x</p>")) 60 in
  resolve_headers 29 text 200 headers;
  tick (fun () ->
      Browser.navigate "/p0";
      check "replacing an entry evicts nothing: the oldest is still used" "31" (ints (calls ()));
      finish ())

let pointer_buttons finish =
  setup links;
  plain_start ();
  fire_mouse "#l" "pointerdown" 1 false;
  fire_mouse "#l" "pointerdown" 0 true;
  check "middle button or a modifier: no prefetch" "0" (ints (calls ()));
  fire "#l" "touchstart";
  check "touch prefetches" "1" (ints (calls ()));
  fire_mouse "#m" "pointerdown" 0 false;
  check "primary button prefetches" "2" (ints (calls ()));
  finish ()

let not_cacheable finish =
  let rec go = function
    | [] -> finish ()
    | (name, value, expected) :: rest ->
        setup links;
        plain_start ();
        ignore (click "#l" "");
        resolve_headers 0 (doc "Two" (page {|<a id="m" href="/three">three</a><a id="l" href="/two">two</a>|})) 200
          [| ("cache-control", value) |];
        tick (fun () ->
            ignore (click "#m" "");
            resolve_call 1 (doc "Three" (page {|<a id="l" href="/two">two</a>|})) "";
            tick (fun () ->
                ignore (click "#l" "");
                check name expected (ints (calls ()));
                go rest))
  in
  go
    [ ("no-cache is not kept", "private, no-cache, max-age=60", "3");
      ("no-store is not kept", "no-store, max-age=60", "3");
      ("must-revalidate is kept within max-age", "max-age=60, must-revalidate", "2") ]

let thirty_entries finish =
  let ids = List.init 31 (fun i -> "p" ^ ints i) in
  setup (page (String.concat "" (List.map (fun id -> {|<a id="|} ^ id ^ {|" href="/|} ^ id ^ {|">x</a>|}) ids)));
  plain_start ();
  List.iter (fun id -> fire ("#" ^ id) "pointerdown") ids;
  check "31 prefetches" "31" (ints (calls ()));
  List.iteri (fun i _ -> resolve_call i (doc "P" (page "<p>p</p>")) "") ids;
  tick (fun () ->
      ignore (click "#p0" "");
      check "the oldest was dropped" "32" (ints (calls ()));
      Browser.navigate "/p1";
      check "the next one is kept" "32" (ints (calls ()));
      finish ())

let unmount_clears finish =
  setup links;
  plain_start ();
  fire "#l" "pointerdown";
  stop ();
  check "prefetch aborted" "true" (bools (call_aborted 0));
  plain_start ();
  ignore (click "#l" "");
  check "a new fetch after stop" "2" (ints (calls ()));
  finish ()

let all =
  [
    ("navigate before start", navigate_before_start);
    ("click fetches and swaps", click_fetches);
    ("dev: a new page build reloads and keeps the scroll", dev_reload);
    ("dev: a css build swaps the stylesheets", dev_css);
    ("dev: a new session reloads", dev_session);
    ("dev: a build error shows an overlay", dev_error);
    ("dev: the scroll position comes back after the reload", after_scroll);
    ("css: sheets of a partial navigation move to the head", partial_css);
    ("css: sheets of a full swap move to the head", full_swap_css);
    ("css: sheets of the first page move to the head at start", first_load_css);
    ("links that are not intercepted", not_intercepted);
    ("stop then start", stop_then_start);
    ("history and popstate", history_and_popstate);
    ("scroll top and restore", scrolling);
    ("scroll to fragment", fragment_scroll);
    ("superseded navigation aborts", superseded);
    ("late response of an aborted request", superseded_late_response);
    ("fetch failure falls back", failure_falls_back);
    ("fetch throwing falls back", sync_failure_falls_back);
    ("redirects", redirect);
    ("navigate", navigate_api);
    ("start twice", start_twice);
    ("Browser.navigate", browser_navigate);
    ("Browser.navigate refuses script URLs, navigation off and on", navigate_refuses_scripts);
    ("start twice adds listeners once", start_twice_listeners);
    ("mount starts islands, navigation off", mount_without_navigation);
    ("mount starts islands, navigation on", mount_with_navigation);
    ("stop stops navigation", unmount_stops_navigation);
    ("stop cancels a navigation in flight", unmount_cancels_in_flight);
    ("mount after stop", mount_after_unmount);
    ("404 is shown in place", shown_in_place 404);
    ("500 is shown in place", shown_in_place 500);
    ("partial response replaces the outlet", partial);
    ("another build is a full load", stale_build);
    ("unknown outlet is a full load", unknown_outlet);
    ("a bad title still navigates", bad_title);
    ("stop_within aborts the actions of the islands it stops", actions_of_stopped_islands);
    ("an action call survives the render that its handler's writes cause", action_survives_own_render);
    ("that call is still aborted when its island stops", rerendered_call_aborted_by_outlet);
    ("an action call then a navigation in one handler: the call is aborted", call_then_navigate_aborted);
    ("302 not followed is a full load", not_a_page 302 "text/html");
    ("json is a full load", not_a_page 200 "application/json");
    ("no content type is a full load", not_a_page 200 "");
    ("prefetch on hover, the click uses it", hover_prefetch);
    ("leaving before 50 ms sends nothing; focus prefetches", hover_out);
    ("links and settings that do not prefetch", not_prefetched);
    ("visible links prefetch", visible);
    ("max-age reuses a page", max_age_cache);
    ("back and forward use the cache", back_forward_cache);
    ("no-store: a prefetch is used once within 10 s", no_store_once);
    ("other outlet keys miss", keys_miss);
    ("a cached answer of another build is a full load", cached_stale_build);
    ("a successful action clears the cache", action_clears);
    ("a navigation waits for the prefetch in flight", waits_for_prefetch);
    ("view transitions when enabled", transitions_on);
    ("no view transition by default or without the API", transitions_off);
    ("stop aborts prefetches and clears the cache", unmount_clears);
    ("a navigation cancels the hover timer", down_cancels_hover);
    ("at most 30 entries, the oldest goes first", thirty_entries);
    ("Remote.mutate empties the cache when it succeeds", remote_mutate_clears);
    ("an answer requested before an action is not kept", action_after_navigation_started);
    ("emptying the cache aborts its prefetches", clear_aborts_prefetch);
    ("a waiting navigation does not swap after stop", waiter_after_unmount);
    ("a popstate to the shown page cancels a waiting navigation", popstate_cancels_waiter);
    ("transitions: state first, one attribute owner", transition_token);
    ("transitions: an error in the update is reported", transition_error);
    ("an evicted prefetch is aborted", eviction);
    ("replacing an entry evicts nothing", replace_keeps_others);
    ("pointer down prefetches only for the primary button", pointer_buttons);
    ("no-cache and no-store are not kept", not_cacheable);
  ]

let set_exit_code : int -> unit = [%mel.raw "function (c) { process.exitCode = c }"]
let on_exit : (unit -> unit) -> unit = [%mel.raw "function (f) { process.on('exit', f) }"]
let failures = ref 0
let finished = ref false

let report name = function
  | None -> print_endline ("ok " ^ name)
  | Some e ->
      incr failures;
      print_endline ("FAIL " ^ name ^ ": " ^ Printexc.to_string e)

let rec run = function
  | [] ->
      finished := true;
      Printf.printf "%d cases, %d failures\n" (List.length all) !failures;
      if !failures > 0 then set_exit_code 1
  | (name, case) :: rest ->
      let settled = ref false in
      let next result =
        if not !settled then begin
          settled := true;
          report name result;
          run rest
        end
      in
      fail_hook := (fun e -> next (Some e));
      (try case (fun () -> next None) with e -> next (Some e))

let () =
  on_exit (fun () ->
      if not !finished then begin
        print_endline "cases did not finish";
        set_exit_code 1
      end);
  run all
