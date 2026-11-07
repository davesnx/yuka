external set_timeout : (unit -> unit) -> int -> unit = "setTimeout"
let set_exit_code : int -> unit = [%mel.raw "function (c) { process.exitCode = c }"]

let setup : string -> unit =
  [%mel.raw
    {|function (html) {
  const { JSDOM } = require("jsdom");
  const dom = new JSDOM("<!doctype html><html><body>" + html + "</body></html>", { runScripts: "outside-only", url: "http://localhost/" });
  globalThis.window = dom.window;
  globalThis.document = dom.window.document;
  globalThis.__idle = [];
  dom.window.requestIdleCallback = function (f) { globalThis.__idle.push(f); return globalThis.__idle.length - 1; };
  dom.window.cancelIdleCallback = function () {};
}|}]

let run_idle : unit -> unit =
  [%mel.raw "function () { const l = globalThis.__idle; globalThis.__idle = []; l.forEach(function (f) { f() }) }"]

let click : string -> unit =
  [%mel.raw "function (id) { document.getElementById(id).click() }"]

let text : string -> string =
  [%mel.raw "function (id) { return document.getElementById(id).textContent }"]

let loaded : string -> bool =
  [%mel.raw
    {|function (stem) { return Object.keys(require.cache).some(function (k) { return k.endsWith("/islands/" + stem + ".js") }) }|}]

let html =
  {|<main><yuka-island data-name="Reg_islands.Load_island" data-id="i1" style="display:contents"><div><span id="load"><!--[-->5<!--]--></span><button id="load-add">+</button></div></yuka-island><script type="application/json" data-yuka-props="i1">{"initial":5}</script><yuka-island data-name="Reg_islands.Idle_island" data-id="i2" style="display:contents" data-start="idle"><div><span id="idle"><!--[-->7<!--]--></span><button id="idle-add">+</button></div></yuka-island><script type="application/json" data-yuka-props="i2">{"initial":7}</script></main>|}

let failures = ref 0
let total = ref 0

let check name expected actual =
  incr total;
  if expected = actual then print_endline ("ok " ^ name)
  else begin
    incr failures;
    print_endline (Printf.sprintf "FAIL %s: expected %S, got %S" name expected actual)
  end

let finish () =
  Printf.printf "%d cases, %d failures\n" !total !failures;
  if !failures > 0 then set_exit_code 1

let () =
  setup html;
  Yuka.mount ();
  click "load-add";
  check "idle chunk is not imported before its trigger" "false" (string_of_bool (loaded "idle_island"));
  check "click before the import resolves changes nothing yet" "5" (text "load");
  set_timeout
    (fun () ->
      check "load island imported at mount" "true" (string_of_bool (loaded "load_island"));
      check "click before the import is replayed" "6" (text "load");
      click "load-add";
      check "load island hydrates" "7" (text "load");
      check "idle island waits for its trigger" "7" (text "idle");
      check "idle chunk still not imported" "false" (string_of_bool (loaded "idle_island"));
      run_idle ();
      set_timeout
        (fun () ->
          check "idle chunk imported at the trigger" "true" (string_of_bool (loaded "idle_island"));
          click "idle-add";
          check "idle island hydrates" "8" (text "idle");
          check "load island is still live" "7" (text "load");
          finish ())
        50)
    50
