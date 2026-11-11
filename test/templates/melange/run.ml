open Yuka

type node

let () =
  [%mel.raw
    {|(function () {
  const { JSDOM } = require("jsdom");
  const dom = new JSDOM("<!doctype html><html><body></body></html>");
  globalThis.window = dom.window;
  globalThis.document = dom.window.document;
  globalThis.__templates = 0;
  const create = document.createElement;
  document.createElement = function (t) {
    if (String(t).toLowerCase() === "template") globalThis.__templates++;
    return create.apply(document, arguments);
  };
})()|}]

let set_exit_code : int -> unit = [%mel.raw "function (c) { process.exitCode = c }"]
let templates_created : unit -> int = [%mel.raw "function () { return globalThis.__templates }"]
let container : unit -> node =
  [%mel.raw "function () { const c = document.createElement('div'); document.body.appendChild(c); return c }"]

external html : node -> string = "innerHTML" [@@mel.get]
external set_html : node -> string -> unit = "innerHTML" [@@mel.set]
external as_container : node -> Client.container = "%identity"

let failures = ref 0

let check name expected got =
  if expected <> got then begin
    incr failures;
    print_endline ("FAIL " ^ name ^ "\n  expected: " ^ expected ^ "\n  got:      " ^ got)
  end

let control_value : node -> string =
  [%mel.raw
    "function (c) { const e = c.querySelector('select, textarea, input'); return e ? e.value : '' }"]

let render_with_value tree =
  let c = container () in
  let dispose = Private.render (as_container c) tree in
  let out = (html c, control_value c) in
  dispose ();
  out

let render tree = fst (render_with_value tree)

let hydrate tree =
  let c = container () in
  set_html c (Private.render_html (fun () -> Private.node (tree ())));
  let parsed = html c in
  let dispose = Client.hydrate (as_container c) tree in
  let out = html c in
  dispose ();
  (parsed, out)

let () =
  List.iter
    (fun (name, tree) ->
      match Private.node (tree ()) with
      | Private.Template { template; parts = _ } ->
          let again = Private.recompile template in
          check (name ^ ": ppx html is the run-time html")
            (Private.template_html again) (Private.template_html template);
          check (name ^ ": ppx paths are the run-time paths")
            (Js.Json.stringify (Obj.magic (Private.template_plan again)))
            (Js.Json.stringify (Obj.magic (Private.template_plan template)));
          let by_tree () =
            match Private.node (tree ()) with
            | Private.Template { template; parts } ->
                Private.element (Private.expand template parts)
            | n -> Private.element n
          in
          let before = templates_created () in
          let cloned = render tree in
          let parsed = templates_created () - before in
          check (name ^ ": the template is parsed once") "1" (string_of_int parsed);
          let again = render tree in
          check (name ^ ": no parse on the second render") "0"
            (string_of_int (templates_created () - before - parsed));
          check (name ^ ": second render") cloned again;
          let tree_html, tree_value = render_with_value by_tree in
          let _, cloned_value = render_with_value tree in
          check (name ^ ": clone has the value of the node tree") tree_value cloned_value;
          if not (List.mem name Template_cases.value_properties) then
            check (name ^ ": clone is the node tree") tree_html cloned;
          if List.mem name Template_cases.parser_changes then
            check (name ^ ": fallback prints the server html")
              (Private.to_html (Private.node (tree ())))
              cloned
          else begin
            let parsed, hydrated = hydrate tree in
            check (name ^ ": hydrate keeps the server html") parsed hydrated
          end
      | _ -> check name "a template" "not a template")
    Template_cases.cases;
  if !failures > 0 then set_exit_code 1
  else print_endline (string_of_int (List.length Template_cases.cases) ^ " template cases: ok")
