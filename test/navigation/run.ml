open Yuka

type m

external import : string -> m runtime_promise = "import"
external router : m -> runtime_router = "router" [@@mel.get]

let runtime_registry entries =
  runtime_registry ~navigation:(fun () -> runtime_promise_map router (import "yuka/navigation.js")) entries

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
          Effect.after (fun () ->
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

let malformed_fragment finish =
  setup (page {|<a id="a" href="/a#100%">a</a>|});
  plain_start ();
  ignore (click "#a" "");
  resolve_call 0 (doc "A" (page {|<h2 id="100%">s</h2><a id="b" href="/b#%E0%A4%A">b</a>|})) "";
  tick (fun () ->
      check "scrolls to the undecoded fragment" "into:100%" (log_read ());
      check "fragment in location" "/a#100%" (location_ ());
      log_clear ();
      ignore (click "#b" "");
      resolve_call 1 (doc "B" (page {|<p id="b">b</p>|})) "";
      tick (fun () ->
          check "no element: scrolls to the top" "scroll:0" (log_read ());
          check "page shown" (page {|<p id="b">b</p>|}) (body_html ());
          finish ()))

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

let navigating () = bools (State.peek Browser.navigating)

let navigating_flag finish =
  setup (page {|<a id="a" href="/a">a</a><a id="b" href="/b">b</a>|});
  plain_start ();
  check "not navigating at start" "false" (navigating ());
  ignore (click "#a" "");
  check "navigating while the page loads" "true" (navigating ());
  ignore (click "#b" "");
  check "a newer navigation keeps it" "true" (navigating ());
  resolve_call 1 (doc "B" (page {|<a id="c" href="/c">c</a><a id="d" href="/d">d</a>|})) "";
  tick (fun () ->
      check "not navigating once the page is shown" "false" (navigating ());
      log_clear ();
      ignore (click "#c" "");
      check "navigating again" "true" (navigating ());
      reject_call 2;
      tick (fun () ->
          check "a failed request is a full load" "assign" (log_read ());
          check "not navigating after the failure" "false" (navigating ());
          ignore (click "#d" "");
          check "navigating before stop" "true" (navigating ());
          stop ();
          check "not navigating after stop" "false" (navigating ());
          finish ()))

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
  const gone = globalThis.__unobserved = [];
  globalThis.__observeCount = 0;
  window.IntersectionObserver = function (cb, options) {
    globalThis.__observerMargin = options && options.rootMargin;
    this.cb = cb;
    this.observe = function (el) { globalThis.__observeCount++; seen.push({ el: el, cb: cb, o: this }); };
    this.unobserve = function (el) { gone.push(el.id); };
    this.disconnect = function () { seen.length = 0; };
  };
}|}]

let observed : unit -> string =
  [%mel.raw "function () { return globalThis.__observed.map(function (x) { return x.el.id }).join(',') }"]

let observe_count : unit -> int = [%mel.raw "function () { return globalThis.__observeCount }"]
let unobserved : unit -> string = [%mel.raw "function () { return globalThis.__unobserved.join(',') }"]
let observer_margin : unit -> string = [%mel.raw "function () { return String(globalThis.__observerMargin) }"]

let crossing : string -> bool -> unit =
  [%mel.raw
    {|function (id, inside) {
  const x = globalThis.__observed.find(function (x) { return x.el.id === id; });
  x.cb([{ isIntersecting: inside, target: x.el }]);
}|}]

let intersect id = crossing id true
let leave id = crossing id false

let call_priority : int -> string =
  [%mel.raw "function (i) { return String(globalThis.__calls[i].init.priority) }"]

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
let level l = {|<meta name="yuka-prefetch" content="|} ^ l ^ {|">|}
let cached text max_age = (text, [| ("cache-control", "private, max-age=" ^ ints max_age) |])

let hover_prefetch finish =
  setup links;
  plain_start ();
  fire "#l" "pointerover";
  wait 10 (fun () ->
      check "no fetch before 50 ms" "0" (ints (calls ()));
      wait 60 (fun () ->
          check "one prefetch" "1" (ints (calls ()));
          check "prefetch header" "hover" (prefetch_header 0);
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
  setup (level "off" ^ links);
  plain_start ();
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
  check "below Visible no link is observed, data-yuka-prefetch=visible included" "" (observed ());
  check "and nothing is fetched" "0" (ints (calls ()));
  setup (level "visible" ^ page {|<a id="v" href="/two">v</a><a id="o" href="/three" data-yuka-prefetch="off">o</a>|});
  stub_observer ();
  plain_start ();
  check "visible mode observes every link" "v,o" (observed ());
  intersect "o";
  check "off still wins" "0" (ints (calls ()));
  intersect "v";
  check "a visible link prefetches" "1" (ints (calls ()));
  check "a visible prefetch names its trigger" "visible" (prefetch_header 0);
  intersect "v";
  check "a link in flight is not prefetched again" "1" (ints (calls ()));
  finish ()

let numbered n = List.init n (fun i -> "p" ^ ints i)

let visible_page ids =
  setup (level "visible" ^ page (String.concat "" (List.map (fun id -> {|<a id="|} ^ id ^ {|" href="/|} ^ id ^ {|">x</a>|}) ids)));
  stub_observer ();
  plain_start ();
  List.iter intersect ids

let urls from = String.concat "," (List.init (calls () - from) (fun i -> call_url (from + i)))

let visible_limit finish =
  visible_page (numbered 6);
  check "a 200px margin" "200px" (observer_margin ());
  check "4 requests open" "http://localhost/p0,http://localhost/p1,http://localhost/p2,http://localhost/p3" (urls 0);
  check "started links are no longer observed, waiting ones are" "p0,p1,p2,p3" (unobserved ());
  resolve_call 0 (doc "P0" (page "")) "";
  tick (fun () ->
      check "a settled prefetch starts the newest waiting link" "http://localhost/p5" (urls 4);
      check "observed until its request starts" "p0,p1,p2,p3,p5" (unobserved ());
      reject_call 1;
      tick (fun () ->
          check "a failed prefetch starts the next" "http://localhost/p4" (urls 5);
          finish ()))

let visible_leaves finish =
  visible_page (numbered 6);
  leave "p5";
  resolve_call 0 (doc "P0" (page "")) "";
  tick (fun () ->
      check "a link that left the view is not fetched" "http://localhost/p4" (urls 4);
      resolve_call 1 (doc "P1" (page "")) "";
      tick (fun () ->
          check "nothing else waits" "5" (ints (calls ()));
          finish ()))

let visible_no_eviction finish =
  visible_page (numbered 34);
  check "4 requests open" "4" (ints (calls ()));
  check "waiting links evict nothing" "false" (bools (call_aborted 0));
  finish ()

let intent_skips_limit finish =
  setup (level "visible" ^ page ({|<a id="x" href="/x">x</a>|} ^ String.concat "" (List.map (fun id -> {|<a id="|} ^ id ^ {|" href="/|} ^ id ^ {|">x</a>|}) (numbered 4))));
  stub_observer ();
  plain_start ();
  List.iter intersect (numbered 4);
  fire "#x" "pointerdown";
  check "an intent prefetch starts with 4 open" "http://localhost/x" (urls 4);
  check "a visible request has low priority" "low" (call_priority 0);
  check "an intent request has none" "undefined" (call_priority 4);
  ignore (click "#p0" "");
  ignore (click "#x" "");
  Browser.navigate "/y";
  check "a navigation has none" "undefined" (call_priority 5);
  finish ()

let hover_queued finish =
  visible_page (numbered 6);
  fire "#p4" "pointerover";
  wait 60 (fun () ->
      check "a hover starts a waiting link at once" "http://localhost/p4" (urls 4);
      check "at intent priority" "undefined" (call_priority 4);
      check "and it is no longer observed" "p0,p1,p2,p3,p4" (unobserved ());
      reject_call 4;
      tick (fun () ->
          resolve_call 0 (doc "P0" (page "")) "";
          resolve_call 1 (doc "P1" (page "")) "";
          tick (fun () ->
              check "it left the queue: a failed hover request is not sent again" "http://localhost/p5" (urls 5);
              resolve_call 2 (doc "P2" (page "")) "";
              tick (fun () ->
                  check "no second request" "6" (ints (calls ()));
                  finish ()))))

let click_queued finish =
  visible_page (numbered 6);
  ignore (click "#p5" "");
  check "the click fetches" "http://localhost/p5" (urls 4);
  check "as a navigation" "undefined" (prefetch_header 4);
  resolve_call 0 (doc "P0" (page "")) "";
  tick (fun () ->
      check "the clicked link left the queue" "http://localhost/p4" (urls 5);
      resolve_call 4 (doc "P5" (page "<p>five</p>")) "";
      tick (fun () ->
          check "shown" "/p5" (location_ ());
          check "one request for the click" "6" (ints (calls ()));
          finish ()))

let action_rewatches finish =
  visible_page (numbered 6);
  let _ = Action.call act "x" in
  resolve_with 4 {|{"ok":"y"}|} "" 200 "application/json";
  tick (fun () ->
      check "the links are observed again" "12" (ints (observe_count ()));
      List.iter intersect (numbered 6);
      check "4 new requests" "http://localhost/p0,http://localhost/p1,http://localhost/p2,http://localhost/p3" (urls 5);
      resolve_call 5 (doc "P0" (page "")) "";
      tick (fun () ->
          check "2 wait, the newest starts next" "http://localhost/p5" (urls 9);
          finish ()))

let page_level finish =
  List.iter
    (fun (meta, expected) ->
      setup (meta ^ page {|<a id="v" href="/two">v</a><a id="h" href="/three">h</a>|});
      stub_observer ();
      plain_start ();
      check (meta ^ ": observed") expected (observed ()))
    [ ("", ""); (level "hover", ""); (level "eager", ""); (level "visible", "v,h"); (level "off", "") ];
  finish ()

let refusal level = [| ("yuka-prefetch", level) |]

let refused_then_click finish =
  setup links;
  plain_start ();
  fire "#l" "pointerdown";
  resolve_headers 0 "" 204 (refusal "off");
  tick (fun () ->
      check "a refusal is not shown and loads nothing" "/start?x=1|" (location_ () ^ "|" ^ log_read ());
      ignore (click "#l" "");
      check "the click fetches" "2" (ints (calls ()));
      check "as a navigation" "undefined" (prefetch_header 1);
      resolve_call 1 (doc "Two" (page "<p>two</p>")) "";
      tick (fun () ->
          check "shown" "/two" (location_ ());
          check "body" (page "<p>two</p>") (body_html ());
          check "a client navigation, no full load" "scroll:0" (log_read ());
          finish ()))

let refused_while_waiting finish =
  setup links;
  plain_start ();
  fire "#l" "pointerdown";
  ignore (click "#l" "");
  check "the click waits for the prefetch" "1" (ints (calls ()));
  resolve_headers 0 "" 204 (refusal "off");
  tick (fun () ->
      check "then fetches as a navigation" "2|undefined" (ints (calls ()) ^ "|" ^ prefetch_header 1);
      resolve_call 1 (doc "Two" (page "<p>two</p>")) "";
      tick (fun () ->
          check "shown" "/two" (location_ ());
          check "a client navigation, no full load" "scroll:0" (log_read ());
          finish ()))

let refused_off finish =
  setup links;
  plain_start ();
  fire "#l" "pointerdown";
  resolve_headers 0 "" 204 (refusal "off");
  tick (fun () ->
      fire "#l" "pointerdown";
      fire "#l" "focusin";
      wait 60 (fun () ->
          check "no trigger fetches an off URL again" "1" (ints (calls ()));
          fire "#m" "pointerdown";
          check "another URL still prefetches" "http://localhost/three" (urls 1);
          let _ = Action.call act "x" in
          resolve_with 2 {|{"ok":"y"}|} "" 200 "application/json";
          tick (fun () ->
              fire "#l" "pointerdown";
              check "also after an action" "3" (ints (calls ()));
              finish ())))

let refused_visible finish =
  setup (level "visible" ^ links);
  stub_observer ();
  plain_start ();
  intersect "l";
  resolve_headers 0 "" 204 (refusal "hover");
  tick (fun () ->
      intersect "l";
      check "no visible prefetch above the level" "1" (ints (calls ()));
      fire "#l" "pointerdown";
      check "a press at the level fetches" "2|hover" (ints (calls ()) ^ "|" ^ prefetch_header 1);
      finish ())

let refused_pumps finish =
  visible_page (numbered 6);
  resolve_headers 0 "" 204 (refusal "hover");
  tick (fun () ->
      check "a refusal starts the newest waiting link" "http://localhost/p5" (urls 4);
      finish ())

let refused_kept_after_action finish =
  setup (level "visible" ^ links);
  stub_observer ();
  plain_start ();
  intersect "l";
  resolve_headers 0 "" 204 (refusal "hover");
  tick (fun () ->
      let _ = Action.call act "x" in
      resolve_with 1 {|{"ok":"y"}|} "" 200 "application/json";
      tick (fun () ->
          intersect "l";
          check "after an action the refused link is not fetched again" "2" (ints (calls ()));
          finish ()))

let refused_kept_across_outlets finish =
  setup (level "visible" ^ links);
  stub_observer ();
  plain_start ();
  intersect "l";
  resolve_headers 0 "" 204 (refusal "hover");
  tick (fun () ->
      ignore (click "#m" "");
      resolve_call 1 (doc "Three" {|<yuka-outlet data-k="L0"><a id="l" href="/two">two</a></yuka-outlet>|}) "";
      tick (fun () ->
          intersect "l";
          check "the refused link is not fetched again" "2" (ints (calls ()));
          fire "#l" "pointerdown";
          check "a press still fetches, with the new outlet keys" "3|L0" (ints (calls ()) ^ "|" ^ call_header 2);
          finish ()))

let refused_bound finish =
  let ids = List.init 201 (fun i -> "q" ^ ints i) in
  setup (page (String.concat "" (List.map (fun id -> {|<a id="|} ^ id ^ {|" href="/|} ^ id ^ {|">x</a>|}) ids)));
  plain_start ();
  let rec refuse i = function
    | [] ->
        fire "#q0" "pointerdown";
        check "after 200 remembered levels the table starts again" "http://localhost/q0" (urls 201);
        finish ()
    | id :: rest ->
        fire ("#" ^ id) "pointerdown";
        resolve_headers i "" 204 (refusal "off");
        tick (fun () -> refuse (i + 1) rest)
  in
  refuse 0 ids

let empty_204 finish =
  setup links;
  plain_start ();
  fire "#m" "pointerdown";
  resolve_headers 0 "" 204 [||];
  tick (fun () ->
      fire "#l" "pointerdown";
      ignore (click "#l" "");
      resolve_headers 1 "" 204 [||];
      tick (fun () ->
          check "a 204 with no level: the waiting click fetches as a navigation" "3|undefined" (ints (calls ()) ^ "|" ^ prefetch_header 2);
          resolve_call 2 (doc "Two" (page "<p>two</p>")) "";
          tick (fun () ->
              check "shown, no full load" "/two|scroll:0" (location_ () ^ "|" ^ log_read ());
              Browser.navigate "/three";
              check "a 204 with no level is not kept" "4|undefined" (ints (calls ()) ^ "|" ^ prefetch_header 3);
              finish ())))

let warmed : unit -> string =
  [%mel.raw
    {|function () {
  return Array.from(document.head.querySelectorAll("link[rel=modulepreload], link[rel=prefetch]"), function (l) {
    return l.rel + ":" + l.getAttribute("href");
  }).join(",");
}|}]

let assets links = doc "Page" (page (String.concat "" links ^ "<p>x</p>"))
let preload href = {|<link rel="modulepreload" href="|} ^ href ^ {|">|}
let sheet href = {|<link rel="stylesheet" href="|} ^ href ^ {|" data-yuka-css>|}

let intent_warms finish =
  setup links;
  plain_start ();
  fire "#l" "pointerdown";
  resolve_call 0 (assets [ preload "/a.js?x=1&amp;y=2"; preload "/b.js"; sheet "/s.css" ]) "";
  tick (fun () ->
      check "an intent answer warms its chunks and sheets"
        "modulepreload:http://localhost/a.js?x=1&y=2,modulepreload:http://localhost/b.js,prefetch:http://localhost/s.css"
        (warmed ());
      fire "#m" "pointerdown";
      resolve_call 1 (assets [ preload "/b.js"; preload "/c.js"; sheet "/s.css" ]) "";
      tick (fun () ->
          check "a URL is warmed once"
            "modulepreload:http://localhost/a.js?x=1&y=2,modulepreload:http://localhost/b.js,prefetch:http://localhost/s.css,modulepreload:http://localhost/c.js"
            (warmed ());
          finish ()))

let nothing_to_warm finish =
  setup links;
  plain_start ();
  fire "#l" "pointerdown";
  fire "#m" "pointerdown";
  resolve_call 0 (assets []) "";
  reject_call 1;
  tick (fun () ->
      check "an answer with no links and a failed prefetch warm nothing" "" (warmed ());
      finish ())

let warm_unescapes finish =
  setup links;
  plain_start ();
  fire "#l" "pointerdown";
  resolve_call 0 (assets [ preload "/e.js?a=&lt;&quot;&amp;lt;" ]) "";
  tick (fun () ->
      check "each entity is decoded once" "modulepreload:http://localhost/e.js?a=%3C%22&lt;" (warmed ());
      finish ())

let warm_relative finish =
  setup (page {|<a id="d" href="/dir/page">d</a>|});
  plain_start ();
  fire "#d" "pointerdown";
  resolve_call 0 (assets [ preload "x.js" ]) "";
  tick (fun () ->
      check "a relative href is resolved against the answer URL" "modulepreload:http://localhost/dir/x.js" (warmed ());
      finish ())

let warm_skips_page_links finish =
  setup links;
  set_head ({|<title>start</title>|} ^ sheet "/s.css");
  plain_start ();
  fire "#l" "pointerdown";
  resolve_call 0 (assets [ sheet "/s.css"; preload "/a.js" ]) "";
  tick (fun () ->
      check "a sheet already in the page is not warmed" "modulepreload:http://localhost/a.js" (warmed ());
      finish ())

let warm_only_shown finish =
  setup "";
  set_head {|<title>start</title><meta name="yuka-build" content="b1">|};
  set_body (page {|<a id="a" href="/a">a</a><a id="b" href="/b">b</a><a id="c" href="/c">c</a>|});
  plain_start ();
  fire "#a" "pointerdown";
  fire "#b" "pointerdown";
  fire "#c" "pointerdown";
  let text = assets [ preload "/x.js" ] in
  resolve_with 0 text "" 200 "text/plain";
  resolve_with 1 text "" 302 "text/html";
  resolve_headers 2 text 200 [| ("yuka-build", "b2") |];
  tick (fun () ->
      check "text/plain, 302 and another build warm nothing" "" (warmed ());
      finish ())

let warm_bad_href finish =
  setup links;
  plain_start ();
  fire "#m" "pointerdown";
  resolve_call 0 (assets [ preload "http://["; preload "/ok.js" ]) "";
  tick (fun () ->
      check "a bad href is skipped, the others warm" "modulepreload:http://localhost/ok.js" (warmed ());
      fire "#l" "pointerdown";
      ignore (click "#l" "");
      resolve_call 1 (doc "Two" (page {|<link rel="modulepreload" href="http://["><p>two</p>|})) "";
      tick (fun () ->
          check "a click that waits on an answer with a bad href completes" "/two" (location_ ());
          finish ()))

let press_then_click finish =
  setup links;
  plain_start ();
  fire "#l" "pointerdown";
  ignore (click "#l" "");
  resolve_call 0 (assets [ preload "/a.js"; sheet "/s.css" ]) "";
  tick (fun () ->
      check "the click completes" "/two" (location_ ());
      check "a waited answer is not warmed" "" (warmed ());
      finish ())

let visible_warms_on_intent finish =
  setup (level "visible" ^ links);
  stub_observer ();
  plain_start ();
  intersect "l";
  intersect "m";
  resolve_call 0 (assets [ preload "/a.js" ]) "";
  tick (fun () ->
      check "a visible answer warms nothing" "" (warmed ());
      fire "#l" "pointerdown";
      check "an intent on an answered visible prefetch warms at once" "modulepreload:http://localhost/a.js" (warmed ());
      fire "#m" "pointerdown";
      check "no new request" "2" (ints (calls ()));
      resolve_call 1 (assets [ preload "/b.js" ]) "";
      tick (fun () ->
          check "an intent on a visible prefetch in flight warms when it arrives"
            "modulepreload:http://localhost/a.js,modulepreload:http://localhost/b.js" (warmed ());
          finish ()))

let waiting_save_data finish =
  visible_page (numbered 6);
  save_data ();
  resolve_call 0 (doc "P0" (page "")) "";
  tick (fun () ->
      check "a waiting link does not start under saveData" "4" (ints (calls ()));
      finish ())

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

let remote_optimistic_clears finish =
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
              let failed = Remote.optimistic r ~change:(fun d -> d ^ "!") (fun () -> Action.call act "x") in
              resolve_with 3 {|{"error":"no"}|} "" 400 "application/json";
              tick (fun () ->
                  check "optimistic failed" "true" (bools (Async.status failed = Async.Done (Error (Status.Rejected "no"))));
                  fire "#l" "pointerdown";
                  check "a failed optimistic call keeps the cache" "4" (ints (calls ()));
                  let ok = Remote.optimistic r ~change:(fun d -> d ^ "!") (fun () -> Action.call act "y") in
                  resolve_with 4 {|{"ok":"y"}|} "" 200 "application/json";
                  tick (fun () ->
                      check "optimistic done" "true" (bools (Async.status ok = Async.Done (Ok "y")));
                      fire "#l" "pointerdown";
                      check "a successful optimistic call empties the cache" "6" (ints (calls ()));
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

let race_page body n = page ({|<a id="l" href="/two">two</a><a id="m" href="/three">three</a>|} ^ body ^ island n)

let race_start () =
  State.set probe_runs 0;
  setup (race_page "<p>start</p>" 1);
  deferred_transitions ();
  render ~islands:(runtime_registry [ probe_entry ]) ~transitions:true ();
  set_scroll 300.;
  ignore (click "#l" "");
  resolve_call 0 (doc "Two" (page ("<p>two</p>" ^ island 2))) ""

let back_before_transition finish =
  race_start ();
  let start = race_page "<p>start</p>" 1 in
  tick (fun () ->
      check "the URL of the page that waits for its transition" "/two" (location_ ());
      log_clear ();
      back ();
      tick (fun () ->
          run_transition 0;
          check "the abandoned page is never put in the DOM" start (body_html ());
          check "location" "/start?x=1" (location_ ());
          check "title" "start" (title ());
          check "the shown page is not fetched again" "1" (ints (calls ()));
          check "scroll of the entry restored, no island started" "scroll:300" (log_read ());
          check "not navigating" "false" (navigating ());
          finish_transition 0;
          tick (fun () ->
              check "attribute removed" "null" (nav_attr ());
              forward ();
              tick (fun () ->
                  check "forward loads the abandoned entry" "/two" (call_url 1);
                  resolve_call 1 (doc "Two" (page ("<p>two</p>" ^ island 2))) "";
                  tick (fun () ->
                      run_transition 1;
                      tick (fun () ->
                          check "shown" (page ("<p>two</p>" ^ island 2)) (body_html ());
                          check "an entry that was never shown starts at the top, its island starts"
                            "scroll:300|scroll:0|g0/2" (log_read ());
                          finish ()))))))

let newer_before_transition fetched (start_newer : unit -> unit) finish =
  race_start ();
  tick (fun () ->
      log_clear ();
      start_newer ();
      check "the newer navigation fetches" fetched (call_url 1);
      run_transition 0;
      check "the abandoned page is never put in the DOM" (race_page "<p>start</p>" 1) (body_html ());
      check "still navigating" "true" (navigating ());
      check "no scroll, no island started" "" (log_read ());
      resolve_call 1 (doc "Three" (page ("<p>three</p>" ^ island 3))) "";
      tick (fun () ->
          check "one transition per shown navigation" "2" (ints (transitions_count ()));
          run_transition 1;
          tick (fun () ->
              check "the newer page" (page ("<p>three</p>" ^ island 3)) (body_html ());
              check "location" "/three" (location_ ());
              check "title" "Three" (title ());
              check "scrolled to the top, its island started" "scroll:0|g0/3" (log_read ());
              check "not navigating" "false" (navigating ());
              finish_transition 0;
              finish_transition 1;
              tick (fun () ->
                  check "attribute removed" "null" (nav_attr ());
                  log_clear ();
                  back ();
                  tick (fun () ->
                      check "back to the abandoned entry loads it" "/two" (call_url 2);
                      resolve_call 2 (doc "Two" (page ("<p>two</p>" ^ island 2))) "";
                      tick (fun () ->
                          run_transition 2;
                          tick (fun () ->
                              check "shown" (page ("<p>two</p>" ^ island 2)) (body_html ());
                              check "an entry that was never shown starts at the top" "scroll:0|g0/2" (log_read ());
                              finish ())))))))

let stop_before_transition finish =
  race_start ();
  tick (fun () ->
      log_clear ();
      stop ();
      run_transition 0;
      check "no swap after stop" (race_page "<p>start</p>" 1) (body_html ());
      check "not navigating" "false" (navigating ());
      tick (fun () ->
          check "no scroll, no island started" "" (log_read ());
          finish ()))

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

let router_loaded : unit -> bool =
  [%mel.raw
    {|function () { return Object.keys(require.cache).some(function (k) { return k.endsWith("/yuka/navigation.js") }) }|}]

let marked_link_loads_nothing finish =
  setup (page {|<a id="l" href="/two" data-yuka-prefetch="visible">x</a>|});
  plain_start ();
  wait 30 (fun () ->
      check "a data-yuka-prefetch=visible link does not load the navigation code at start" "false" (bools (router_loaded ()));
      finish ())

let rec until name cond f n =
  tick (fun () -> if cond () then f () else if n = 0 then check name "true" "false" else until name cond f (n - 1))

let navigation_off_loads_nothing finish =
  setup (page {|<a id="l" href="/two">x</a>|});
  render ~islands:(runtime_registry []) ~navigation:false ();
  fire "#l" "pointerover";
  fire "#l" "pointerdown";
  check "click not intercepted" "false" (bools (click "#l" ""));
  popstate_to "/other";
  wait 30 (fun () ->
      check "no navigation code" "false" (bools (router_loaded ()));
      check "no fetch" "0" (ints (calls ()));
      finish ())

let cold_click finish =
  setup (page {|<a id="l" href="/issue/1">go</a>|});
  plain_start ();
  check "no navigation code at start" "false" (bools (router_loaded ()));
  check "first click prevented at once" "true" (bools (click "#l" ""));
  check "no fetch before the code loads" "0" (ints (calls ()));
  until "the click fetches once the code loads" (fun () -> calls () > 0)
    (fun () ->
      check "navigation code loaded" "true" (bools (router_loaded ()));
      check "one fetch" "1" (ints (calls ()));
      check "fetched url" "http://localhost/issue/1" (call_url 0);
      resolve_call 0 (doc "Issue 1" (page "<p>one</p>")) "";
      tick (fun () ->
          check "body swapped" (page "<p>one</p>") (body_html ());
          check "pushed" "/issue/1" (location_ ());
          check "scrolled to the top, no full page load" "scroll:0" (log_read ());
          finish ()))
    100

let history_entries : unit -> unit =
  [%mel.raw
    {|function () {
  window.history.replaceState({ yukaKey: "1-1" }, "", "/first");
  window.history.pushState({ yukaKey: "2-1" }, "", "/second");
}|}]

let cold_back_forward finish =
  setup (page "<p>second</p>");
  history_entries ();
  plain_start ();
  let length = history_length () in
  check "no navigation code at start" "false" (bools (router_loaded ()));
  back ();
  until "back fetches once the code loads" (fun () -> calls () > 0)
    (fun () ->
      check "back fetches the first page" "/first" (call_url 0);
      resolve_call 0 (doc "First" (page "<p>first</p>")) "";
      tick (fun () ->
          check "first shown" (page "<p>first</p>") (body_html ());
          check "at first" "/first" (location_ ());
          forward ();
          until "forward fetches" (fun () -> calls () > 1)
            (fun () ->
              check "forward fetches the second page" "/second" (call_url 1);
              resolve_call 1 (doc "Second" (page "<p>second again</p>")) "";
              tick (fun () ->
                  check "second shown" (page "<p>second again</p>") (body_html ());
                  check "no push" (ints length) (ints (history_length ()));
                  check "scroll restored, no full page load" "scroll:0|scroll:0" (log_read ());
                  finish ()))
            100))
    100

let history_state_key : unit -> string =
  [%mel.raw "function () { const s = window.history.state; return (s && s.yukaKey) || '' }"]

let replace_url finish =
  setup (page {|<a id="a" href="/a">a</a>|});
  plain_start ();
  let length = history_length () and key = history_state_key () in
  Browser.replace_url "/start?q=router&label=bug";
  check "url replaced" "/start?q=router&label=bug" (location_ ());
  check "no new entry" (ints length) (ints (history_length ()));
  check "history key kept" key (history_state_key ());
  check "no fetch, no page load" "0," (ints (calls ()) ^ "," ^ log_read ());
  List.iter Browser.replace_url ("https://other.example/x" :: script_urls);
  check "another origin and script URLs do nothing" "/start?q=router&label=bug" (location_ ());
  popstate_to "/start?x=1";
  until "a popstate to the URL before the replace loads it" (fun () -> calls () > 0)
    (fun () ->
      check "fetches the first URL" "/start?x=1" (call_url 0);
      finish ())
    100

let replace_url_back finish =
  setup (page {|<a id="a" href="/a">a</a>|});
  plain_start ();
  Browser.replace_url "/start?q=router";
  ignore (click "#a" "");
  until "the click fetches" (fun () -> calls () > 0)
    (fun () ->
      resolve_call 0 (doc "A" (page "<p>a</p>")) "";
      tick (fun () ->
          back ();
          until "back fetches" (fun () -> calls () > 1)
            (fun () ->
              check "back loads the replaced URL" "/start?q=router" (call_url 1);
              finish ())
            100))
    100

let fire_touch : string -> string -> unit =
  [%mel.raw
    "function (sel, name) { document.querySelector(sel).dispatchEvent(new window.Event(name, { bubbles: true })) }"]

let events_off_links_load_nothing finish =
  setup (page {|<button id="b">b</button><input id="i"><a id="l" href="/two">x</a>|});
  plain_start ();
  List.iter (fire "#b") [ "pointerover"; "pointerdown"; "pointerout" ];
  fire_touch "#b" "touchstart";
  List.iter (fire_touch "#i") [ "focusin"; "focusout" ];
  wait 30 (fun () ->
      check "no navigation code after events off links" "false" (bools (router_loaded ()));
      finish ())

let hover_loads_and_prefetches finish =
  setup (page {|<a id="l" href="/two">x</a>|});
  plain_start ();
  fire "#l" "pointerover";
  until "a hover on a link loads the navigation code" router_loaded
    (fun () ->
      wait 80 (fun () ->
          check "the hover prefetches once the code loads" "1" (ints (calls ()));
          check "prefetch header" "hover" (prefetch_header 0);
          finish ()))
    100

let block_router : string -> unit =
  [%mel.raw
    {|function (mode) {
  const { MessageChannel } = require("node:worker_threads");
  const channel = new MessageChannel();
  globalThis.__imports = 0;
  channel.port1.on("message", function () { globalThis.__imports++; });
  channel.port1.unref();
  const hook = "let port, mode; export function initialize(d) { port = d.port; mode = d.mode; }" +
    " export async function resolve(s, c, next) { if (s === 'yuka/navigation.js') { port.postMessage(1);" +
    " if (mode === 'stall') return new Promise(function (r) { setTimeout(r, 600000); }); throw new Error('blocked'); }" +
    " return next(s, c); }";
  require("node:module").register("data:text/javascript," + encodeURIComponent(hook),
    { data: { port: channel.port2, mode: mode }, transferList: [channel.port2] });
  globalThis.__errors = [];
  console.error = function (m) { globalThis.__errors.push(String(m)); };
}|}]

let imports : unit -> int = [%mel.raw "function () { return globalThis.__imports }"]

let load_errors : unit -> int =
  [%mel.raw
    "function () { return globalThis.__errors.filter(function (m) { return m.indexOf('cannot load navigation') >= 0 }).length }"]

let fire_window : string -> unit =
  [%mel.raw "function (name) { window.dispatchEvent(new window.Event(name)) }"]

let stop_during_stall finish =
  setup (page {|<a id="l" href="/two">x</a><a id="m" href="/three">y</a>|});
  plain_start ();
  ignore (click "#l" "");
  wait 1000 (fun () ->
      stop ();
      plain_start ();
      wait 2500 (fun () ->
          check "no give-up after a stop and a new render" "" (log_read ());
          check "no error" "0" (ints (load_errors ()));
          check "a click is still taken" "true" (bools (click "#m" ""));
          stop ();
          finish ()))

let leaving_drops_waiting finish =
  setup (page {|<a id="l" href="/two">x</a>|});
  plain_start ();
  ignore (click "#l" "");
  fire_window "beforeunload";
  wait 3200 (fun () ->
      check "a page that is leaving gets no late location.assign" "" (log_read ());
      check "no error" "0" (ints (load_errors ()));
      stop ();
      finish ())

let stalled_import finish =
  setup (level "visible" ^ page {|<a id="l" href="/two">x</a><a id="m" href="/three">y</a>|});
  plain_start ();
  wait 1000 (fun () ->
      check "the click is prevented while the code loads" "true" (bools (click "#l" ""));
      check "navigating while the code loads" "true" (navigating ());
      wait 2500 (fun () ->
          check "no full load 2.5 s after the click (the timer starts at the click)" "" (log_read ());
          wait 700 (fun () ->
              check "3.2 s after the click the waiting click is a full page load" "assign" (log_read ());
              check "not navigating after the full load starts" "false" (navigating ());
              check "one error" "1" (ints (load_errors ()));
              check "a later click is not prevented" "false" (bools (click "#m" ""));
              finish ())))

let failed_import finish =
  setup (page {|<a id="l" href="/two">x</a><a id="m" href="/three">y</a>|});
  plain_start ();
  fire "#l" "pointerover";
  wait 100 (fun () ->
      check "one import" "1" (ints (imports ()));
      check "one error" "1" (ints (load_errors ()));
      check "a click after the failure is not prevented" "false" (bools (click "#m" ""));
      fire "#m" "pointerover";
      fire "#l" "pointerdown";
      Browser.navigate "/four";
      wait 100 (fun () ->
          check "no new import" "1" (ints (imports ()));
          check "no new error" "1" (ints (load_errors ()));
          check "clicks and Browser.navigate are full loads" "assign|assign" (log_read ());
          finish ()))

let throwing_scroll : unit -> unit =
  [%mel.raw
    {|function () {
  Object.defineProperty(window, "scrollY", { get: function () { throw new Error("scrollY broken"); }, configurable: true });
  globalThis.__errors = [];
  console.error = function (m) { globalThis.__errors.push(String(m)); };
}|}]

let replay_errors : unit -> string =
  [%mel.raw
    "function () { return globalThis.__errors.map(function (m) { return m.indexOf('cannot load') >= 0 ? 'load' : 'replay' }).join(',') }"]

let replay_error finish =
  setup (page {|<a id="l" href="/two">x</a><a id="m" href="/three">y</a>|});
  throwing_scroll ();
  plain_start ();
  ignore (click "#l" "");
  ignore (click "#m" "");
  until "the code loads" router_loaded
    (fun () ->
      wait 30 (fun () ->
          check "each waiting click that throws is a full load" "assign|assign" (log_read ());
          check "reported as replay errors, not a load failure" "replay,replay" (replay_errors ());
          finish ()))
    100

let all =
  [
    ("navigate before start", navigate_before_start);
    ("navigation off loads no navigation code", navigation_off_loads_nothing);
    ("pointer, focus and touch off links load no navigation code", events_off_links_load_nothing);
    ("the first click loads the navigation code and is not lost", cold_click);
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
    ("a fragment that does not decode", malformed_fragment);
    ("superseded navigation aborts", superseded);
    ("late response of an aborted request", superseded_late_response);
    ("fetch failure falls back", failure_falls_back);
    ("Browser.navigating follows the navigation in flight", navigating_flag);
    ("fetch throwing falls back", sync_failure_falls_back);
    ("redirects", redirect);
    ("navigate", navigate_api);
    ("start twice", start_twice);
    ("Browser.navigate", browser_navigate);
    ("Browser.navigate refuses script URLs, navigation off and on", navigate_refuses_scripts);
    ("Browser.replace_url", replace_url);
    ("back to an entry loads its replaced URL", replace_url_back);
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
    ("the page gives the level", page_level);
    ("a refused prefetch is not kept; the click fetches", refused_then_click);
    ("a click that waits for a refused prefetch fetches", refused_while_waiting);
    ("after a refusal with off no trigger fetches, also after an action", refused_off);
    ("after a refused visible prefetch a press fetches", refused_visible);
    ("a refusal settles the queue", refused_pumps);
    ("a refused level is kept after an action", refused_kept_after_action);
    ("a refused level is kept when the outlet keys change", refused_kept_across_outlets);
    ("at most 200 remembered levels", refused_bound);
    ("a 204 with no level is not kept; a waiting click fetches", empty_204);
    ("visible: 4 open, the newest waiting link starts when one settles", visible_limit);
    ("visible: a waiting link that leaves the view is not fetched", visible_leaves);
    ("visible: waiting links are not in the cache", visible_no_eviction);
    ("intent starts at once with 4 open; only visible requests are low priority", intent_skips_limit);
    ("a hover on a waiting link starts it once", hover_queued);
    ("a click on a waiting link navigates with one request", click_queued);
    ("after an action the visible links are observed and prefetched again", action_rewatches);
    ("a waiting link does not start under saveData", waiting_save_data);
    ("an intent prefetch answer warms its chunks and sheets once", intent_warms);
    ("an answer with no links or a failed prefetch warms nothing", nothing_to_warm);
    ("a visible prefetch warms only after an intent on its link", visible_warms_on_intent);
    ("warm: entities decoded once each", warm_unescapes);
    ("warm: a relative href resolves against the answer URL", warm_relative);
    ("warm: a link already in the page is not warmed again", warm_skips_page_links);
    ("warm: an answer that is not swapped in warms nothing", warm_only_shown);
    ("warm: a bad href is skipped and a waiting click completes", warm_bad_href);
    ("warm: press then click before the answer warms nothing", press_then_click);
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
    ("Remote.optimistic empties the cache when it succeeds", remote_optimistic_clears);
    ("an answer requested before an action is not kept", action_after_navigation_started);
    ("emptying the cache aborts its prefetches", clear_aborts_prefetch);
    ("a waiting navigation does not swap after stop", waiter_after_unmount);
    ("a popstate to the shown page cancels a waiting navigation", popstate_cancels_waiter);
    ("transitions: state first, one attribute owner", transition_token);
    ("transitions: an error in the update is reported", transition_error);
    ("transitions: back before the update runs keeps the shown page", back_before_transition);
    ("transitions: a click before the update runs drops the older page", newer_before_transition "http://localhost/three" (fun () -> ignore (click "#m" "")));
    ("transitions: a popstate before the update runs drops the older page", newer_before_transition "/three" (fun () -> popstate_to "/three"));
    ("transitions: stop before the update runs drops the page", stop_before_transition);
    ("an evicted prefetch is aborted", eviction);
    ("replacing an entry evicts nothing", replace_keeps_others);
    ("pointer down prefetches only for the primary button", pointer_buttons);
    ("no-cache and no-store are not kept", not_cacheable);
  ]

let set_exit_code : int -> unit = [%mel.raw "function (c) { process.exitCode = c }"]
let on_exit : (unit -> unit) -> unit = [%mel.raw "function (f) { process.on('exit', f) }"]
let argument : unit -> string = [%mel.raw "function () { return process.argv[2] || '' }"]
let exit_now : unit -> unit = [%mel.raw "function () { process.exit() }"]
let failures = ref 0
let ran = ref 0
let finished = ref false

let report name = function
  | None -> print_endline ("ok " ^ name)
  | Some e ->
      incr failures;
      print_endline ("FAIL " ^ name ^ ": " ^ Printexc.to_string e)

let rec run = function
  | [] ->
      finished := true;
      Printf.printf "%d cases, %d failures\n" !ran !failures;
      if !failures > 0 then set_exit_code 1;
      if argument () = "stall" then exit_now ()
  | (name, case) :: rest ->
      incr ran;
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
  run
    (match argument () with
    | "back" -> [ ("back and forward before the navigation code loads", cold_back_forward) ]
    | "hover" ->
        [ ("a data-yuka-prefetch=visible link does not load the navigation code", marked_link_loads_nothing);
          ("a hover on a link loads the navigation code", hover_loads_and_prefetches) ]
    | "replay" -> [ ("an error while the waiting events run", replay_error) ]
    | "stall" ->
        block_router "stall";
        [
          ("a stop during a slow load does not turn navigation off", stop_during_stall);
          ("a page that is leaving drops the waiting navigations", leaving_drops_waiting);
          ("an import with no answer: a full load 3 s after the click", stalled_import);
        ]
    | "fail" ->
        block_router "fail";
        [ ("a failed import: full loads, no retry, one error", failed_import) ]
    | _ -> all)
