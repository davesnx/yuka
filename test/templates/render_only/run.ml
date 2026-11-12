open Yuka

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

let namespaces : node -> string =
  [%mel.raw
    {|function (c) {
  const out = [];
  const prefix = { "http://www.w3.org/2000/svg": "svg", "http://www.w3.org/1999/xhtml": "html" };
  c.querySelectorAll("*").forEach(function (e) { out.push(prefix[e.namespaceURI] + ":" + e.localName); });
  return out.join(" ");
}|}]

let attribute : node -> string -> string -> string =
  [%mel.raw
    {|function (c, selector, name) { const e = c.querySelector(selector); return e ? String(e.getAttribute(name)) : "no element"; }|}]

let capture_warnings : unit -> unit =
  [%mel.raw
    {|function () { globalThis.__warnings = []; globalThis.__warn = console.warn; console.warn = function (m) { globalThis.__warnings.push(m); }; }|}]

let warnings : unit -> string =
  [%mel.raw {|function () { console.warn = globalThis.__warn; return globalThis.__warnings.join("|"); }|}]

external html : node -> string = "innerHTML" [@@mel.get]
external text_content : node -> string = "textContent" [@@mel.get]
external as_container : node -> Client.container = "%identity"

let failures = ref 0

let check name expected got =
  if expected <> got then begin
    incr failures;
    print_endline ("FAIL " ^ name ^ "\n  expected: " ^ expected ^ "\n  got:      " ^ got)
  end

let mount tree f =
  let c = container () in
  match Private.render (as_container c) tree with
  | dispose ->
      let out = f c in
      dispose ();
      out
  | exception e -> "raised " ^ Printexc.to_string e

let render tree = mount tree html

let serialized : string -> string =
  [%mel.raw
    {|function (s) { return s.replace(/="([^"]*)"/g, function (m, v) { return '="' + v.replace(/>/g, "&gt;") + '"'; }); }|}]

let server tree = serialized (Private.to_html (Private.node (tree ())))

let kind tree =
  match Private.node (tree ()) with Private.Template _ -> "a template" | _ -> "lowered"

let () =
  List.iter
    (fun (name, tree) ->
      let lowered = List.mem name Template_cases.parser_changes in
      check (name ^ ": kind") (if lowered then "lowered" else "a template") (kind tree);
      if not (List.mem name Template_cases.value_properties) then
        check (name ^ ": render-only mount prints the server html") (server tree) (render tree))
    Template_cases.cases;
  check "div inside p: render-only mount keeps the div in the p" "<p><div>x</div></p>"
    (render (List.assoc "div inside p" Template_cases.cases));
  List.iter
    (fun (name, tree) ->
      check (name ^ ": render-only mount prints the server html") (server tree) (render tree))
    (List.filter (fun (n, _) -> String.length n < 5 || String.sub n 0 5 <> "param") Template_cases.regressions);
  List.iter
    (fun (name, text, elements) ->
      let tree = List.assoc name Template_cases.regressions in
      check (name ^ ": render-only mount has the text (innerHTML prints param as void)") text
        (mount tree text_content);
      check (name ^ ": render-only mount has the elements") elements (mount tree namespaces))
    [ ("param with a text and a part", "xz", "html:object html:param html:b");
      ("param at the root of a component", "x", "html:div html:param") ];
  let case name = List.assoc name Template_cases.regressions in
  List.iter
    (fun (sink, selector, name, value) ->
      let kept = case (sink ^ " in a kept template") and lowered = case (sink ^ " in a lowered template") in
      check (sink ^ ": kept template") "a template" (kind kept);
      check (sink ^ ": lowered template") "lowered" (kind lowered);
      check (sink ^ ": lowered prints as the kept template") ("<p>" ^ server kept ^ "</p>") (server lowered);
      check (sink ^ ": kept template mounts the literal") value (mount kept (fun c -> attribute c selector name));
      check (sink ^ ": lowered template mounts the literal") value
        (mount lowered (fun c -> attribute c selector name)))
    [ ("srcdoc", "iframe", "srcdoc", "<b>hi</b>"); ("base href", "base", "href", "/app/") ];
  List.iter
    (fun (name, tree, expected, spaces) ->
      if List.mem name Template_cases.svg_clones then begin
        check (name ^ ": render-only mount") expected (render tree);
        check (name ^ ": namespaces") spaces (mount tree namespaces)
      end
      else begin
        let prefix = "raised Failure(Yuka: the HTML parser would change this template here; only a hydrating app builds it node by node: <a href=\"#\">" in
        let r = render tree in
        check (name ^ ": render-only mount is a clear error") prefix
          (if String.length r > String.length prefix then String.sub r 0 (String.length prefix) else r)
      end)
    Template_cases.svg_cases;
  let reparsed =
    runtime_template "\x01table\x02\x01tr\x02\x06\x06" ~html:"<table><tr></tr></table>" ~walk:[||]
      ~kids:[||] ~attrs:[||] ~values:[||] ~clones:1
  in
  capture_warnings ();
  ignore (render (fun () -> runtime_instance reparsed [||]));
  check "dev build: a coded template that the parser changes is reported"
    "yuka: hydration mismatch in island ? at root: expected the tree of the template <table><tr></tr></table>, found <table>"
    (warnings ());
  if !failures > 0 then set_exit_code 1 else print_endline "render-only templates: ok"
