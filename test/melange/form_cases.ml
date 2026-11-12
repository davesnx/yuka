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
          element "input" [ attr "name" "body"; attr "value" (Form.value form Body) ] [];
          element "i" [] [ hole (fun () -> text (if Form.pending form then "pending" else "idle")) ];
          Form.error_view form Body (fun m -> element "b" [] [ text m ]);
          Form.errors_view form (fun m -> element "u" [] [ text m ]);
        ])
    ()

let navigated = ref []
let here : unit -> string = [%mel.raw "function () { return window.location.pathname + window.location.search }"]
let use_on_ok = ref true

let plain_view key () =
  Form.make ~action:jot ~key
    ~children:(fun form ->
      fragment
        [
          element "input" [ attr "name" "body"; attr "value" (Form.value form Body) ] [];
          Form.error_view form Body (fun m -> element "b" [] [ text m ]);
        ])
    ()

let redirect_view () =
  Form.make ~action:jot ~key:"r"
    ~children:(fun form ->
      fragment
        [
          element "input" [ attr "name" "body"; attr "value" (Form.value form Body) ] [];
          Form.errors_view form (fun m -> element "u" [] [ text m ]);
        ])
    ()

let button_view () =
  Form.make ~action:jot
    ~on_ok:(fun n -> ok_value := Some n)
    ~children:(fun _ -> element "button" [ attr "type" "submit"; attr "name" "body"; attr "value" "from-button" ] [ text "go" ])
    ()

let tick = State.make 0

let toggled_view () =
  hole (fun () ->
      ignore (State.get tick);
      plain_view "" ())

let entry_of name view =
  runtime_entry ~name (fun json -> Result.map (fun () () -> view ()) (Codec.decode Codec.unit json))

let entries =
  [
    entry_of "A" (plain_view "a");
    entry_of "B" (plain_view "b");
    entry_of "Btn" button_view;
    entry_of "R" redirect_view;
    entry_of "T" toggled_view;
  ]

let island_of name view = runtime_island ~name ~props:`Null view

let record_navigation () =
  navigated := [];
  Private.platform := { !Private.platform with navigate = (fun u -> navigated := !navigated @ [ u ]) }

let submit_in : string -> unit =
  [%mel.raw
    {|function (key) {
  const f = document.querySelector('form[data-yuka-key="' + key + '"]');
  f.dispatchEvent(new window.Event('submit', { bubbles: true, cancelable: true }));
}|}]

let submit_with_button : unit -> bool =
  [%mel.raw
    {|function () {
  const f = document.querySelector('form');
  const b = f.querySelector('button');
  const SE = document.defaultView.SubmitEvent;
  const e = SE ? new SE('submit', { bubbles: true, cancelable: true, submitter: b }) : new window.Event('submit', { bubbles: true, cancelable: true });
  if (!SE) Object.defineProperty(e, 'submitter', { value: b });
  f.dispatchEvent(e);
  return e.defaultPrevented;
}|}]

let set_input_in : string -> string -> unit =
  [%mel.raw "function (key, v) { document.querySelector('form[data-yuka-key=\"' + key + '\"] input[name=body]').value = v }"]

let entry = runtime_entry ~name:"F" (fun json -> Result.map (fun () () -> view ()) (Codec.decode Codec.unit json))
let island () = runtime_island ~name:"F" ~props:`Null view

let start html =
  Yuka.stop ();
  setup_fetch ();
  ok_value := None;
  set_body html;
  Yuka.render ~islands:(runtime_registry (entry :: entries)) ~navigation:false ();
  record_navigation ()

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
            Yuka.stop ()) );
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
                Yuka.stop ())) );
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
                Yuka.stop ())) );
    ( "form: field errors from the server",
      fun finish ->
        start (Server.to_string island);
        set_input "body" "x";
        ignore (submit ());
        respond 0 200 {|{"ok":{"errors":[["body","Too short"]]}}|};
        after_ms 10 (fun () ->
            finish (fun () ->
                check "field error" "Too short" (text_of "b");
                Yuka.stop ())) );
    ( "form: two pending forms each follow their own redirect",
      fun finish ->
        start (Server.to_string (fun () -> fragment [ island_of "A" (plain_view "a"); island_of "B" (plain_view "b") ]));
        set_input_in "a" "one";
        set_input_in "b" "two";
        submit_in "a";
        submit_in "b";
        respond 1 200 {|{"ok":{"value":2,"redirect":"/b"}}|};
        after_ms 10 (fun () ->
            respond 0 200 {|{"ok":{"value":1,"redirect":"/a"}}|};
            after_ms 10 (fun () ->
                finish (fun () ->
                    check "each its own" "/b,/a" (String.concat "," !navigated);
                    Yuka.stop ()))) );
    ( "form: a redirect to another site is refused",
      fun finish ->
        start (Server.to_string (fun () -> island_of "R" redirect_view));
        let answers =
          [ "javascript:alert(1)"; " JavaScript:alert(1)"; "https://evil.example/"; "//evil.example/x"; "data:text/html,x" ]
        in
        let rec go i = function
          | [] ->
              finish (fun () ->
                  check "not followed" "" (String.concat "," !navigated);
                  check "shown" "Yuka: refused a redirect to another site: data:text/html,x" (text_of "u");
                  Yuka.stop ())
          | l :: rest ->
              set_input_in "r" "x";
              submit_in "r";
              respond i 200 (Printf.sprintf {|{"ok":{"value":1,"redirect":%S}}|} l);
              after_ms 10 (fun () -> go (i + 1) rest)
        in
        go 0 answers );
    ( "form: with no redirect and no on_ok, reload the page URL",
      fun finish ->
        start (Server.to_string (fun () -> island_of "A" (plain_view "a")));
        set_input_in "a" "x";
        submit_in "a";
        respond 0 200 {|{"ok":{"value":1}}|};
        after_ms 10 (fun () ->
            finish (fun () ->
                check "client navigation to the page URL" (here ()) (String.concat "," !navigated);
                Yuka.stop ())) );
    ( "form: the submit button's name and value are sent",
      fun finish ->
        start (Server.to_string (fun () -> island_of "Btn" button_view));
        ignore (submit_with_button ());
        finish (fun () ->
            check "posted" {|[["body","from-button"]]|} (if fetches () > 0 then fetch_body 0 else "none");
            Yuka.stop ()) );
    ( "form: a 422 state lasts until a client submit on that form",
      fun finish ->
        let html =
          Private.print
            (let s = Private.session ~streaming:false ~islands_only:true in
             Private.set_form s ("jot", "", [ ("body", "sent") ], [ (Some "body", "Too short") ]);
             s)
            (fun () -> Private.node (island_of "T" toggled_view))
        in
        start html;
        let first = text_of "b" in
        State.update tick succ;
        let remounted = (text_of "b", input_value "body") in
        set_input "body" "longer";
        ignore (submit ());
        State.update tick succ;
        finish (fun () ->
            check "shown at hydration" "Too short" first;
            check "kept after a new render" "Too short" (fst remounted);
            check "value kept after a new render" "sent" (snd remounted);
            check "gone after a client submit" "none" (text_of "b");
            check "value gone after a client submit" "" (input_value "body");
            Yuka.stop ()) );
    ( "form: unknown field names from the server are form errors",
      fun finish ->
        start (Server.to_string island);
        set_input "body" "x";
        ignore (submit ());
        respond 0 200 {|{"ok":{"errors":[["nope","Bad"]]}}|};
        after_ms 10 (fun () ->
            finish (fun () ->
                check "form error" "Bad" (text_of "u");
                check "idle" "idle" (text_of "i");
                Yuka.stop ())) );
    ( "form: a bad data-yuka-sent is ignored",
      fun finish ->
        let html =
          Private.print
            (let s = Private.session ~streaming:false ~islands_only:true in
             Private.set_form s ("jot", "", [ ("body", "sent") ], [ (Some "body", "Too short") ]);
             s)
            (fun () -> Private.node (island ()))
        in
        let marker = "data-yuka-sent=\"" in
        let at = Js.String.indexOf ~search:marker html + String.length marker in
        let stop = Js.String.indexOf ~search:"\"" ~start:at html in
        start (String.sub html 0 at ^ "{bad" ^ String.sub html stop (String.length html - stop));
        set_input "body" "hello";
        ignore (submit ());
        let during = text_of "i" in
        finish (fun () ->
            check "no error shown" "none" (text_of "b");
            check "the form still sends" "1" (string_of_int (fetches ()));
            check "pending" "pending" during;
            Yuka.stop ()) );
    ( "form: a 422 page hydrates with the sent values and errors",
      fun finish ->
        let html =
          Private.print
            (let s = Private.session ~streaming:false ~islands_only:true in
             Private.set_form s ("jot", "", [ ("body", "sent") ], [ (Some "body", "Too short") ]);
             s)
            (fun () -> Private.node (island ()))
        in
        start html;
        let after = body_html () in
        finish (fun () ->
            check "value kept" "sent" (input_value "body");
            check "error kept" "Too short" (text_of "b");
            check "same markup after hydration" html after;
            Yuka.stop ()) );
  ]
