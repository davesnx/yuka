open Yuka

type node

let () =
  [%mel.raw
    {|(function () {
  const { JSDOM } = require("jsdom");
  const dom = new JSDOM("<!doctype html><html><body></body></html>", { url: "http://localhost/" });
  globalThis.window = dom.window;
  globalThis.document = dom.window.document;
})()|}]

let dev : bool = [%mel.raw {|globalThis.__YUKA_DEV__ !== false|}]
let set_exit_code : int -> unit = [%mel.raw "function (c) { process.exitCode = c }"]

let take : unit -> string array =
  [%mel.raw
    {|function () { const e = globalThis.__errors; globalThis.__errors = []; return e.map(function (x) { return x.message + (x.stack ? " +stack" : " -stack"); }) }|}]

let container : unit -> node =
  [%mel.raw "function () { const c = document.createElement('div'); document.body.appendChild(c); return c }"]

let click : node -> unit = [%mel.raw "function (c) { c.querySelector('button').click() }"]

external as_container : node -> Client.container = "%identity"

let failures = ref 0

let message =
  "[yuka] State.get with nothing tracking it, during the render of a component.\n\
  \  It reads one time and never updates. Read it in markup, a memo or an effect,\n\
  \  or use State.peek for one read. +stack"

let check name ~fires =
  let errors = take () in
  let expected = if fires && dev then [| message |] else [||] in
  if errors <> expected then begin
    incr failures;
    print_endline
      ("FAIL " ^ name ^ "\n  expected: [" ^ String.concat " | " (Array.to_list expected) ^ "]\n  got:      ["
     ^ String.concat " | " (Array.to_list errors) ^ "]")
  end
  else print_endline ("ok " ^ name)

let render view =
  let c = container () in
  (c, Private.render (as_container c) view)

let () = check "module top level" ~fires:false

let () =
  let _, dispose = render Dev_check_cases.body_read in
  check "a read in a same-file helper called in a component body" ~fires:true;
  dispose ()

let () =
  let _, dispose = render Dev_check_cases.helper_read in
  check "a read in a helper of another module, called in a body" ~fires:true;
  dispose ()

let () =
  let _, dispose = render Dev_check_cases.body_read_in_hole in
  check "a component in a hole, not shown" ~fires:false;
  State.set Dev_check_cases.show true;
  check "a read in the body of a component that a hole shows" ~fires:true;
  State.set Dev_check_cases.show false;
  dispose ()

let () =
  let c, dispose = render Dev_check_cases.handler_read in
  check "render of a handler" ~fires:false;
  click c;
  check "a read in an event handler" ~fires:false;
  dispose ()

let () =
  let _, dispose = render Dev_check_cases.effect_read in
  State.set Dev_check_cases.count 2;
  check "a read in an effect and in on_change" ~fires:false;
  dispose ()

let () =
  let _, dispose = render Dev_check_cases.memo_read in
  State.set Dev_check_cases.count 3;
  check "a read in a memo" ~fires:false;
  dispose ()

let () =
  let _, dispose = render Dev_check_cases.hole_read in
  State.set Dev_check_cases.count 4;
  check "a read in markup" ~fires:false;
  dispose ()

let () =
  let _, dispose = render Dev_check_cases.peek_read in
  check "State.peek in a body" ~fires:false;
  dispose ()

let () =
  let _, dispose = render Dev_check_cases.untrack_read in
  check "State.untrack in a body" ~fires:false;
  dispose ()

let () =
  let _, dispose = render Dev_check_cases.each_cleanup_read in
  check "render of an each with an effect cleanup per row" ~fires:false;
  State.set Dev_check_cases.items [| 1 |];
  check "a read in the effect cleanup of a removed each row" ~fires:false;
  dispose ()

let () =
  ignore (State.get Dev_check_cases.count);
  check "a read outside a render" ~fires:false

let () =
  if !failures > 0 then set_exit_code 1
  else print_endline (if dev then "dev check (dev build): ok" else "dev check (__YUKA_DEV__ = false): ok")
