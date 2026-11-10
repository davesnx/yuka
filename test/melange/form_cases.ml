open Yuka
open Forms_shared.Entry

let check = Cases.check

let setup_fetch : unit -> unit =
  [%mel.raw
    {|function () {
  globalThis.__fcalls = [];
  globalThis.fetch = function (url, init) {
    const call = { url: url, body: init.body };
    globalThis.__fcalls.push(call);
    return new Promise(function (resolve) {
      call.respond = function (status, body) {
        resolve({ status: status, text: function () { return Promise.resolve(body); } });
      };
    });
  };
}|}]

let fetches : unit -> int = [%mel.raw "function () { return globalThis.__fcalls.length }"]
let fetch_body : int -> string = [%mel.raw "function (i) { return globalThis.__fcalls[i].body }"]
let respond : int -> int -> string -> unit =
  [%mel.raw "function (i, status, body) { globalThis.__fcalls[i].respond(status, body) }"]

let set_body : string -> unit = [%mel.raw "function (h) { document.body.innerHTML = h }"]
let body_html : unit -> string = [%mel.raw "function () { return document.body.innerHTML }"]

let set_input : string -> string -> unit =
  [%mel.raw "function (name, v) { document.querySelector('input[name=' + name + ']').value = v }"]

let submit : unit -> bool =
  [%mel.raw
    {|function () {
  const f = document.querySelector('form');
  const e = new window.Event('submit', { bubbles: true, cancelable: true });
  f.dispatchEvent(e);
  return e.defaultPrevented;
}|}]

let remove_input : string -> unit =
  [%mel.raw "function (name) { document.querySelector('input[name=' + name + ']').remove() }"]

let text_of : string -> string =
  [%mel.raw "function (sel) { const e = document.querySelector(sel); return e ? e.textContent : 'none' }"]

let input_value : string -> string =
  [%mel.raw "function (name) { return document.querySelector('input[name=' + name + ']').value }"]

let after_ms : int -> (unit -> unit) -> unit =
  [%mel.raw "function (ms, f) { setTimeout(function () { f() }, ms) }"]

let ok_value : int option ref = ref None

let view () =
  Form.make ~action:jot
    ~on_ok:(fun n -> ok_value := Some n)
    ~children:(fun form ->
      fragment
        [
          lower "input" [ attr "name" "body"; attr "value" (Form.value form Body) ] [];
          lower "i" [] [ hole (fun () -> text (if Form.pending form then "pending" else "idle")) ];
          Form.error_view form Body (fun m -> lower "b" [] [ text m ]);
          Form.form_error_view form (fun m -> lower "u" [] [ text m ]);
        ])
    ()

let entry = Client.entry ~name:"F" (fun json -> Result.map (fun () () -> view ()) (Codec.decode Codec.unit json))
let island () = Client.island ~name:"F" ~props:`Null view

let start html =
  Yuka.unmount ();
  setup_fetch ();
  ok_value := None;
  set_body html;
  Yuka.mount ~islands:(Client.registry [ entry ]) ~navigation:false ()

let async =
  [
    ( "form: a decode error shows at once, with no request",
      fun finish ->
        start (Server.to_string island);
        remove_input "body";
        let prevented = submit () in
        finish (fun () ->
            check "prevented" "true" (string_of_bool prevented);
            check "no fetch" "0" (string_of_int (fetches ()));
            check "field error" "Missing" (text_of "b");
            Yuka.unmount ()) );
    ( "form: pending until the answer, then on_ok",
      fun finish ->
        start (Server.to_string island);
        set_input "body" "hello";
        ignore (submit ());
        let during = text_of "i" in
        let sent = if fetches () > 0 then fetch_body 0 else "none" in
        respond 0 200 {|{"ok":{"value":5}}|};
        after_ms 10 (fun () ->
            finish (fun () ->
                check "posted the encoded input" {|[["body","hello"]]|} sent;
                check "pending" "pending" during;
                check "idle after" "idle" (text_of "i");
                check "on_ok" "5" (match !ok_value with Some n -> string_of_int n | None -> "none");
                Yuka.unmount ())) );
    ( "form: a 400 from the server shows its message",
      fun finish ->
        start (Server.to_string island);
        set_input "body" "x";
        ignore (submit ());
        respond 0 400 {|{"error":"Refused"}|};
        after_ms 10 (fun () ->
            finish (fun () ->
                check "form error" "Refused" (text_of "u");
                check "idle" "idle" (text_of "i");
                Yuka.unmount ())) );
    ( "form: field errors from the server",
      fun finish ->
        start (Server.to_string island);
        set_input "body" "x";
        ignore (submit ());
        respond 0 200 {|{"ok":{"errors":[["body","Too short"]]}}|};
        after_ms 10 (fun () ->
            finish (fun () ->
                check "field error" "Too short" (text_of "b");
                Yuka.unmount ())) );
    ( "form: a 422 page hydrates with the sent values and errors",
      fun finish ->
        let html =
          Private.print
            (let s = Private.session ~streaming:false ~islands_only:true in
             Private.set_form s ("jot", [ ("body", "sent") ], `List [ `List [ `String "body"; `String "Too short" ] ]);
             s)
            (fun () -> Private.node (island ()))
        in
        start html;
        let after = body_html () in
        finish (fun () ->
            check "value kept" "sent" (input_value "body");
            check "error kept" "Too short" (text_of "b");
            check "same markup after hydration" html after;
            Yuka.unmount ()) );
  ]
