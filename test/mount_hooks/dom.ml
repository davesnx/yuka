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
let start_islands () = Yuka.render ~islands:(Yuka.runtime_registry []) ~navigation:false ()

let url_cases =
  [ ("a", "href", "/ok", {|<a href="/ok"></a>|});
    ("a", "href", "javascript:alert(1)", {|<a href="about:blank#blocked"></a>|});
    ("a", "href", " \t\001JaVa\nScRiPt:alert(1)", {|<a href="about:blank#blocked"></a>|});
    ("a", "HREF", "vbscript:msgbox(1)", {|<a href="about:blank#blocked"></a>|});
    ("a", "href", "data:text/html,<b>x</b>", {|<a href="about:blank#blocked"></a>|});
    ("form", "action", "javascript:alert(1)", {|<form action="about:blank#blocked"></form>|});
    ("img", "src", "data:image/png;base64,AAAA", {|<img src="data:image/png;base64,AAAA">|});
    ("img", "src", "javascript:alert(1)", {|<img src="about:blank#blocked">|});
    ("iframe", "srcdoc", "<script>alert(1)</script>", {|<iframe srcdoc=""></iframe>|});
    ("base", "href", "/x", {|<base href="">|}) ]

let void tag = tag = "img" || tag = "base"

let code_str s =
  String.concat ""
    (List.map
       (fun c -> if Char.code c < 0x10 then "\x0f" ^ String.make 1 (Char.chr (Char.code c + 0x40)) else String.make 1 c)
       (List.of_seq (String.to_seq s)))

let one_part tag =
  Yuka.runtime_template
    ("\x01" ^ tag ^ "\x05\x02\x06")
    ~html:(if void tag then "<" ^ tag ^ ">" else "<" ^ tag ^ "></" ^ tag ^ ">")
    ~walk:[||] ~kids:[||] ~attrs:[| 0; 0; 2 |] ~values:[||] ~clones:1

let fixed_code tag name value = "\x01" ^ tag ^ "\x03" ^ code_str name ^ "\x04" ^ code_str value ^ "\x02\x06"

let check_urls path build =
  List.iter
    (fun (tag, name, value, expected) ->
      let c, dispose = mount (fun () -> build tag name value) in
      check (path ^ ": " ^ tag ^ " " ^ name ^ "=" ^ String.escaped value) expected (html c);
      dispose ())
    url_cases
