open Yuka

type node

let () =
  [%mel.raw
    {|(function () {
  const { JSDOM } = require("jsdom");
  const dom = new JSDOM("<!doctype html><html><body></body></html>", { url: "http://localhost/" });
  globalThis.window = dom.window;
  globalThis.document = dom.window.document;
  globalThis.fetch = function () { return new Promise(function () {}); };
  globalThis.__warnings = [];
  console.warn = function (m) { globalThis.__warnings.push(String(m)); };
})()|}]

let set_exit_code : int -> unit = [%mel.raw "function (c) { process.exitCode = c }"]
let warnings : unit -> string =
  [%mel.raw "function () { const w = globalThis.__warnings.join('|'); globalThis.__warnings = []; return w }"]
let container : unit -> node =
  [%mel.raw "function () { const c = document.createElement('div'); document.body.appendChild(c); return c }"]
let nodes : node -> node array =
  [%mel.raw "function (c) { const out = []; const w = document.createTreeWalker(c, 133); let n; while ((n = w.nextNode())) out.push(n); return out }"]

external html : node -> string = "innerHTML" [@@mel.get]
external set_html : node -> string -> unit = "innerHTML" [@@mel.set]
external as_container : node -> Client.container = "%identity"

let failures = ref 0

let check name expected got =
  if expected <> got then begin
    incr failures;
    print_endline ("FAIL " ^ name ^ "\n  expected: " ^ expected ^ "\n  got:      " ^ got)
  end
  else print_endline ("ok " ^ name)

let render view =
  let c = container () in
  let dispose = Private.render (as_container c) view in
  (c, dispose)

let server view = Private.render_html (fun () -> Private.node (view ()))

let hydrate name view expected =
  let c = container () in
  let printed = server view in
  check (name ^ ": server html") expected printed;
  set_html c printed;
  let before = nodes c in
  let dispose = Private.hydrate (as_container c) view in
  let after = nodes c in
  check (name ^ ": html after hydrate") printed (html c);
  check (name ^ ": nodes adopted") "true"
    (string_of_bool
       (Array.length before = Array.length after
       && Array.for_all2 (fun a b -> a == b) before after));
  check (name ^ ": no mismatch") "" (warnings ());
  (c, dispose)

let () =
  let c, dispose = render Holes_cases.remote_view in
  check "remote status child: first" "<b>status: <!--[-->idle<!--]--></b>" (html c);
  State.set Holes_cases.enabled true;
  check "remote status child: after a write" "<b>status: <!--[-->loading<!--]--></b>" (html c);
  State.set Holes_cases.enabled false;
  dispose ()

let () =
  let c, dispose = render Holes_cases.helper_view in
  check "helper child: first" "<p>name: <!--[-->a<!--]--></p>" (html c);
  State.set Holes_cases.name "b";
  check "helper child: after a write" "<p>name: <!--[-->b<!--]--></p>" (html c);
  State.set Holes_cases.name "a";
  dispose ()

let () =
  let c, dispose = render Holes_cases.explicit_static_view in
  check "a hole that reads no State: markers in the browser" "<p>a<!--[-->hi<!--]--><i></i></p>" (html c);
  dispose ();
  let c, dispose = render Holes_cases.static_list_view in
  check "a constant list: the list owns the element" "<ul><li>x</li><li>y</li></ul>" (html c);
  dispose ();
  let c, dispose = render Holes_cases.constant_view in
  check "constant expressions and a local helper: no hole" "<p title=\"hi!\"><b class=\"n2\">many</b><i>x</i><i>y</i></p>"
    (html c);
  dispose ()

let () =
  let _, dispose = hydrate "static expression" Holes_cases.static_view "<p>a<!---->hi<i></i></p>" in
  dispose ();
  let _, dispose =
    hydrate "constant expressions" Holes_cases.constant_view "<p title=\"hi!\"><b class=\"n2\">many</b><i>x</i><i>y</i></p>"
  in
  dispose ();
  let _, dispose = hydrate "explicit hole" Holes_cases.explicit_static_view "<p>a<!--[-->hi<!--]--><i></i></p>" in
  dispose ();
  let _, dispose = hydrate "static list" Holes_cases.static_list_view "<ul><li>x</li><li>y</li></ul>" in
  dispose ();
  let c, dispose = hydrate "dynamic hole" Holes_cases.dynamic_view "<p>a<!--[-->a<!--]--><i></i></p>" in
  State.set Holes_cases.name "b";
  check "dynamic hole: after a write" "<p>a<!--[-->b<!--]--><i></i></p>" (html c);
  State.set Holes_cases.name "a";
  dispose ();
  let _, dispose =
    hydrate "conditional read, not read" (Holes_cases.conditional_view ~read:false) "<p>a<!--[-->none<!--]--><i></i></p>"
  in
  dispose ();
  let c, dispose =
    hydrate "conditional read, read" (Holes_cases.conditional_view ~read:true) "<p>a<!--[-->a<!--]--><i></i></p>"
  in
  State.set Holes_cases.name "b";
  check "conditional read, read: after a write" "<p>a<!--[-->b<!--]--><i></i></p>" (html c);
  State.set Holes_cases.name "a";
  dispose ()

let () =
  let c, dispose = render Holes_cases.component_view in
  let runs = !Holes_cases.Body.runs and calls = !Holes_cases.calls in
  State.set Holes_cases.name "b";
  check "component tag: an outer hole does not run the body again" (string_of_int runs)
    (string_of_int !Holes_cases.Body.runs);
  check "plain call: tracked" (string_of_int (calls + 1)) (string_of_int !Holes_cases.calls);
  check "plain call: text updated" "<p><!--[--><i>0</i><!--]--><span>b</span></p>" (html c);
  State.set Holes_cases.name "a";
  dispose ()

let install_fetch : unit -> unit =
  [%mel.raw
    {|function () {
  globalThis.__calls = [];
  globalThis.fetch = function (url, init) {
    return new Promise(function (resolve) {
      globalThis.__calls.push(function (status, body) {
        resolve({ status: status, text: function () { return Promise.resolve(body); } });
      });
    });
  };
}|}]

let respond : int -> int -> string -> unit = [%mel.raw "function (i, s, b) { globalThis.__calls[i](s, b) }"]
let after : (unit -> unit) -> unit = [%mel.raw "function (f) { setTimeout(function () { f() }, 0) }"]

let rec steps = function
  | [] -> if !failures > 0 then set_exit_code 1 else print_endline "hole cases: ok"
  | step :: rest ->
      step ();
      after (fun () -> steps rest)

let () =
  install_fetch ();
  let c, dispose = render Holes_cases.state_view in
  let remote = Option.get !Holes_cases.fetched in
  let shows name expected () = check ("Remote.state in markup: " ^ name) ("<b>" ^ expected ^ "</b>") (html c) in
  let rollback = ref (fun (_ : (string, Status.error) result) -> ()) in
  steps
    [
      shows "first" "loading";
      (fun () -> respond 0 200 {|{"ok":"x"}|});
      shows "fetch done" "ready x";
      (fun () ->
        Remote.refetch remote;
        shows "refetch" "loading x" ());
      (fun () -> respond 1 503 "");
      shows "fetch failed" "failed server error x";
      (fun () ->
        Remote.refetch remote;
        respond 2 200 {|{"ok":"y"}|});
      shows "refetch done" "ready y";
      (fun () ->
        let _ =
          Remote.optimistic remote ~change:(fun d -> d ^ "!") (fun () ->
              let result, resolve, _ = Async.make () in
              rollback := resolve;
              result)
        in
        shows "optimistic change" "ready y!" ());
      (fun () -> !rollback (Error Status.Server));
      shows "optimistic rollback" "ready y";
      dispose;
    ]
