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

let capture : unit -> unit =
  [%mel.raw
    {|function () {
  globalThis.__logs = [];
  if (!globalThis.__console) globalThis.__console = { error: console.error, warn: console.warn };
  console.error = function (m) { globalThis.__logs.push(String(m)); };
  console.warn = function (m) { globalThis.__logs.push(String(m)); };
}|}]

let logs : unit -> string = [%mel.raw {|function () { return globalThis.__logs.join("|") }|}]

let remember : unit -> unit =
  [%mel.raw
    {|function () { globalThis.__pre = Array.from(document.querySelectorAll("button[id$='-add']")).map(function (b) { return [b.id, b, b.parentElement] }) }|}]

let replaced : unit -> string =
  [%mel.raw
    {|function () { return globalThis.__pre.filter(function (p) { const now = document.getElementById(p[0]); return now !== p[1] || now.parentElement !== p[2] }).map(function (p) { return p[0] }).join(",") }|}]

let run_idle : unit -> unit =
  [%mel.raw "function () { const l = globalThis.__idle; globalThis.__idle = []; l.forEach(function (f) { f() }) }"]

let click : string -> unit = [%mel.raw "function (id) { document.getElementById(id + '-add').click() }"]
let text : string -> string = [%mel.raw "function (id) { return document.getElementById(id).textContent }"]

let link name = Printf.sprintf {|<link rel="modulepreload" href="/js/Reg_islands.%s.js">|} name

let counter n id initial =
  Printf.sprintf
    {|<yuka-island data-name="Reg_islands.Counter" data-id="i%d" style="display:contents"><div><span id="%s"><!--[-->%d<!--]--></span><button id="%s-add">+</button></div></yuka-island><script type="application/json" data-yuka-props="i%d">{"id":"%s","initial":%d}</script>|}
    n id initial id n id initial

let wrap ?(start = "") n id inner =
  Printf.sprintf
    {|<yuka-island data-name="Reg_islands.Wrap" data-id="i%d" style="display:contents"%s><section><span id="%s"><!--[-->0<!--]--></span><button id="%s-add">+</button><!--[$-->%s<!--]--></section></yuka-island><script type="application/json" data-yuka-props="i%d">{"id":"%s","children":null}</script>|}
    n start id id inner n id

let top_level = link "Counter" ^ counter 1 "a" 1

let side_by_side =
  "<div>" ^ link "Counter" ^ counter 1 "a" 1 ^ link "Wrap"
  ^ wrap 2 "b" "<p>s</p>"
  ^ counter 3 "c" 3 ^ "</div>"

let nested = link "Wrap" ^ wrap 1 "w" (counter 2 "n" 5) ^ link "Counter"

let in_slot =
  link "Wrap"
  ^ wrap 1 "w"
      ("<p>x</p>"
      ^ wrap ~start:{| data-start="idle"|} 2 "v" (counter 3 "n" 5)
      ^ counter 4 "m" 6)
  ^ link "Counter"

let link_inside = link "Wrap" ^ wrap 1 "w" (link "Counter" ^ counter 2 "n" 5)

let failures = ref 0
let total = ref 0

let check name expected actual =
  incr total;
  if expected = actual then print_endline ("ok " ^ name)
  else begin
    incr failures;
    print_endline (Printf.sprintf "FAIL %s: expected %S, got %S" name expected actual)
  end

let start html =
  Yuka.unmount ();
  setup html;
  capture ();
  remember ();
  Yuka.mount ()

let cases :
    (string * string * (unit -> unit) * (unit -> unit) option) list =
  [
    ( "top-level island with a link",
      top_level,
      (fun () ->
        click "a";
        check "top-level: event updates" "2" (text "a")),
      None );
    ( "two islands side by side",
      side_by_side,
      (fun () ->
        click "a";
        click "b";
        click "c";
        check "side by side: a" "2" (text "a");
        check "side by side: b" "1" (text "b");
        check "side by side: c" "4" (text "c")),
      None );
    ( "island nested in a slot, link after the outer island",
      nested,
      (fun () ->
        click "w";
        click "n";
        check "nested: outer" "1" (text "w");
        check "nested: inner" "6" (text "n")),
      None );
    ( "islands in a slot, one idle",
      in_slot,
      (fun () ->
        click "w";
        click "m";
        click "n";
        check "slot: outer" "1" (text "w");
        check "slot: sibling" "7" (text "m");
        check "slot: inner" "6" (text "n")),
      Some
        (fun () ->
          click "v";
          check "slot: idle island after trigger" "1" (text "v");
          click "n";
          check "slot: inner still live" "7" (text "n")) );
    ( "link inside an island (old placement)",
      link_inside,
      (fun () ->
        click "w";
        click "n";
        check "inside: outer" "1" (text "w");
        check "inside: inner" "6" (text "n")),
      None );
  ]

let rec run = function
  | [] ->
      Printf.printf "%d cases, %d failures\n" !total !failures;
      if !failures > 0 then set_exit_code 1
  | (name, html, step, after_idle) :: rest ->
      start html;
      set_timeout
        (fun () ->
          step ();
          let finish () =
            check (name ^ ": no logs") "" (logs ());
            check (name ^ ": server nodes adopted, none replaced") "" (replaced ());
            run rest
          in
          match after_idle with
          | None -> finish ()
          | Some f ->
              run_idle ();
              set_timeout (fun () -> f (); finish ()) 50)
        50

let () = run cases
