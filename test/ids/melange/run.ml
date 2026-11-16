open Yuka

type node

let () =
  [%mel.raw
    {|(function () {
  const { JSDOM } = require("jsdom");
  const dom = new JSDOM("<!doctype html><html><body></body></html>");
  globalThis.window = dom.window;
  globalThis.document = dom.window.document;
  globalThis.__errors = [];
  console.error = function (m) { globalThis.__errors.push(String(m)); };
})()|}]

let read : int -> string = [%mel.raw {|function (i) { return require("fs").readFileSync(process.argv[i + 2], "utf8") }|}]
let set_exit_code : int -> unit = [%mel.raw "function (c) { process.exitCode = c }"]
let errors : unit -> string = [%mel.raw {|function () { const e = globalThis.__errors.join(" | "); globalThis.__errors = []; return e }|}]
let set_body : string -> unit = [%mel.raw {|function (h) { document.body.innerHTML = h }|}]
let append_html : string -> unit =
  [%mel.raw {|function (h) { const d = document.createElement("div"); d.innerHTML = h; document.body.appendChild(d) }|}]
let inputs : unit -> node array = [%mel.raw {|function () { return Array.from(document.querySelectorAll("input")) }|}]
let input_ids : unit -> string array = [%mel.raw {|function () { return Array.from(document.querySelectorAll("input"), function (e) { return e.id }) }|}]
let click_add : int -> unit =
  [%mel.raw {|function (i) { document.querySelectorAll("button")[i].dispatchEvent(new window.MouseEvent("click", { bubbles: true })) }|}]
let new_container : unit -> Client.container =
  [%mel.raw {|function () { const c = document.createElement("div"); document.body.appendChild(c); return c }|}]

let unlinked : unit -> string =
  [%mel.raw
    {|function () {
  const bad = [];
  document.querySelectorAll("label").forEach(function (l) {
    const i = document.getElementById(l.htmlFor);
    if (!i || i.localName !== "input" || i.previousElementSibling !== l) bad.push(l.htmlFor);
  });
  document.querySelectorAll("input").forEach(function (i) {
    const h = document.getElementById(i.getAttribute("aria-describedby"));
    if (!h || h.previousElementSibling !== i) bad.push(i.id + " hint");
  });
  return bad.join(" ");
}|}]

let duplicates : unit -> string =
  [%mel.raw
    {|function () {
  const seen = new Set(), dup = [];
  document.querySelectorAll("[id]").forEach(function (e) { if (seen.has(e.id)) dup.push(e.id); seen.add(e.id); });
  return dup.join(" ");
}|}]

let failures = ref 0

let check name expected got =
  if expected <> got then begin
    incr failures;
    print_endline ("FAIL " ^ name ^ "\n  expected: " ^ expected ^ "\n  got:      " ^ got)
  end

let words l = String.concat " " l
let client_async = ref (Async.return "done")

let registry () =
  runtime_registry
    [
      runtime_entry ~name:"Form" (fun _ -> Ok (fun () -> Ids_cases.form_view !client_async));
      runtime_entry ~name:"Slotted" (fun _ -> Ok (fun () -> Ids_cases.slot_view None));
    ]

let start () = Yuka.render ~islands:(registry ()) ~navigation:false ()
let not_page id = String.length id < 2 || String.sub id 0 2 <> "p-"
let island_ids () = List.filter not_page (Array.to_list (input_ids ()))

let page_is_sound name =
  check (name ^ ": no duplicate id") "" (duplicates ());
  check (name ^ ": every label and hint linked") "" (unlinked ())

let hydrates name html async =
  Yuka.stop ();
  set_body html;
  client_async := async;
  ignore (Ids_cases.take_seen ());
  let before = inputs () in
  let expected = island_ids () in
  start ();
  check (name ^ ": console") "" (errors ());
  check (name ^ ": the browser gives the ids of the server") (words expected) (words (Ids_cases.take_seen ()));
  check (name ^ ": inputs adopted") "true"
    (string_of_bool (Array.length before = Array.length (inputs ()) && Array.for_all2 ( == ) before (inputs ())));
  page_is_sound name

let () =
  Ids_cases.doomed := false;
  hydrates "filled" (read 0) (Async.return "done");
  click_add 0;
  check "new row: a browser id" "c-" (String.sub (List.hd (Ids_cases.take_seen ())) 0 2);
  page_is_sound "new row";
  append_html (read 2);
  start ();
  check "answer: console" "" (errors ());
  check "answer: the browser gives the ids of the server"
    (words (List.map (fun n -> "L1/x-i1-" ^ n) [ "1"; "2"; "3-1"; "3-2"; "4"; "5"; "6"; "7" ]))
    (words (Ids_cases.take_seen ()));
  page_is_sound "answer";
  let dispose = Private.render (new_container ()) (fun () -> Ids_cases.form_view (Async.return "x")) in
  page_is_sound "client render";
  dispose ();
  let async, resolve, _ = Async.make () in
  hydrates "shell" (read 1) async;
  resolve "late";
  check "late value: browser ids" "c- c- c- c-"
    (words (List.map (fun id -> String.sub id 0 2) (Ids_cases.take_seen ())));
  page_is_sound "late value";
  if !failures > 0 then set_exit_code 1 else print_endline "ids: all passed"
