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

let html =
  {|<main><yuka-island data-name="Reg_islands.Eager" data-id="i1" style="display:contents"><div><span id="eager"><!--[-->5<!--]--></span><button id="eager-add">+</button></div></yuka-island><script type="application/json" data-yuka-props="i1">{"initial":5}</script><yuka-island data-name="Reg_islands.Lazy_one" data-id="i2" style="display:contents" data-start="idle"><div><span id="lazy"><!--[-->7<!--]--></span><button id="lazy-add">+</button></div></yuka-island><script type="application/json" data-yuka-props="i2">{"initial":7}</script></main>|}

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
  click "eager-add";
  check "eager island hydrates" "6" (text "eager");
  check "lazy island waits for its start strategy" "7" (text "lazy");
  run_idle ();
  set_timeout
    (fun () ->
      click "lazy-add";
      check "lazy island loads its chunk and hydrates" "8" (text "lazy");
      check "eager island is still live" "6" (text "eager");
      finish ())
    50
