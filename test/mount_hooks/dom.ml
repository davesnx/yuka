type node

let () =
  [%mel.raw
    {|(function () {
  const { JSDOM } = require("jsdom");
  const dom = new JSDOM("<!doctype html><html><body></body></html>");
  globalThis.window = dom.window;
  globalThis.document = dom.window.document;
})()|}]

let set_exit_code : int -> unit = [%mel.raw "function (c) { process.exitCode = c }"]

let container : unit -> node =
  [%mel.raw "function () { const c = document.createElement('div'); document.body.appendChild(c); return c }"]

external html : node -> string = "innerHTML" [@@mel.get]
external as_container : node -> Yuka.Client.container = "%identity"

let failures = ref 0

let check name expected got =
  if expected <> got then begin
    incr failures;
    print_endline ("FAIL " ^ name ^ "\n  expected: " ^ expected ^ "\n  got:      " ^ got)
  end

let mount tree =
  let c = container () in
  match Yuka.Private.render (as_container c) tree with
  | dispose -> (c, dispose)
  | exception e ->
      incr failures;
      print_endline ("FAIL mount raised " ^ Printexc.to_string e);
      (c, ignore)

let finish name = if !failures > 0 then set_exit_code 1 else print_endline (name ^ ": ok")

let stub_fetch : unit -> unit = [%mel.raw "function () { globalThis.fetch = function () { return new Promise(function () {}) } }"]
let start_islands () = Yuka.render ~islands:(Yuka.Client.registry []) ~navigation:false ()
