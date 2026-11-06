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
  const vc = new VirtualConsole();
  vc.on("jsdomError", function (e) {
    log.push(e.message.indexOf("navigation") >= 0 ? "assign" : "jsdom:" + e.message);
  });
  const dom = new JSDOM("<!doctype html><html><head><title>start</title></head><body>" + html + "</body></html>", { url: "http://localhost/start?x=1", virtualConsole: vc });
  const w = dom.window;
  globalThis.window = w;
  globalThis.document = w.document;
  Object.defineProperty(w, "scrollY", { value: 0, writable: true, configurable: true });
  w.scrollTo = function (x, y) { log.push("scroll:" + y); };
  w.Element.prototype.scrollIntoView = function () { log.push("into:" + this.id); };
  globalThis.fetch = function (url, init) {
    if (globalThis.__failSync) throw new Error("sync");
    const call = { url: url, init: init };
    globalThis.__calls.push(call);
    return new Promise(function (res, rej) {
      call.resolve = function (text, finalUrl, status, type) {
        res({
          url: finalUrl,
          status: status,
          headers: { get: function (n) { return n.toLowerCase() === "content-type" ? type : null; } },
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
let plain_start () = mount ~islands:(Client.registry []) ()

let navigate_before_start finish =
  setup "";
  Router.navigate "/early";
  check "falls back to a page load" "assign" (log_read ());
  check "no fetch" "0" (ints (calls ()));
  finish ()

let click_fetches finish =
  setup (page {|<a id="l" href="/issue/1"><span id="in">go</span></a>|});
  plain_start ();
  check "click on a child is intercepted" "true" (bools (click "#in" ""));
  check "one fetch" "1" (ints (calls ()));
  check "fetched url" "http://localhost/issue/1" (call_url 0);
  check "header" "1" (call_header 0);
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
  Client.entry ~name:"Probe" (fun json ->
      Result.map
        (fun n () ->
          Effect.run (fun () ->
              log ("g" ^ ints (State.get probe_runs) ^ "/" ^ ints n));
          lower "span" [] [ text "p" ])
        (Codec.decode Codec.int json))

let island n =
  {|<yuka-island data-name="Probe" data-id="i1" style="display:contents"><span>p</span></yuka-island><script type="application/json" data-yuka-props="i1">|}
  ^ ints n ^ "</script>"

let stop_then_start finish =
  State.set probe_runs 0;
  setup (page ({|<a id="l" href="/two">x</a>|} ^ island 1));
  mount ~islands:(Client.registry [ probe_entry ]) ();
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
              check "header on back" "1" (call_header 2);
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
      Router.navigate "/b";
      resolve_call 1 (doc "Away" (page "x")) "http://example.com/b";
      tick (fun () ->
          check "cross-origin redirect: full page load" "assign" (log_read ());
          check "location kept" "/login?next=%2Fa" (location_ ());
          finish ()))

let navigate_api finish =
  setup (page "<p>old</p>");
  plain_start ();
  Router.navigate "/x?q=1";
  check "fetch" "/x?q=1" (call_url 0);
  check "header" "1" (call_header 0);
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
  check "header" "1" (call_header 0);
  resolve_call 0 (doc "X" (page "<p>x</p>")) "";
  tick (fun () ->
      check "body" (page "<p>x</p>") (body_html ());
      Browser.navigate "/y";
      check "still client navigation after a navigation" "2" (ints (calls ()));
      check "no full load" "scroll:0" (log_read ());
      finish ())

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
  mount ~islands:(Client.registry [ probe_entry ]) ~navigation:false ();
  check "island started" "g0/3" (log_g ());
  check "click not intercepted" "false" (bools (click "#l" ""));
  check "no fetch" "0" (ints (calls ()));
  check "page not swapped" "/start?x=1" (location_ ());
  finish ()

let mount_with_navigation finish =
  State.set probe_runs 0;
  setup (page ({|<a id="l" href="/two">x</a>|} ^ island 4));
  mount ~islands:(Client.registry [ probe_entry ]) ();
  check "island started" "g0/4" (log_g ());
  check "click intercepted" "true" (bools (click "#l" ""));
  check "one fetch" "1" (ints (calls ()));
  finish ()

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

let all =
  [
    ("navigate before start", navigate_before_start);
    ("click fetches and swaps", click_fetches);
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
    ("start twice adds listeners once", start_twice_listeners);
    ("mount starts islands, navigation off", mount_without_navigation);
    ("mount starts islands, navigation on", mount_with_navigation);
    ("404 is a full load", not_a_page 404 "text/html");
    ("500 is a full load", not_a_page 500 "text/html");
    ("302 not followed is a full load", not_a_page 302 "text/html");
    ("json is a full load", not_a_page 200 "application/json");
    ("no content type is a full load", not_a_page 200 "");
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
