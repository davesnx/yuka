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

let attribute : string -> string -> string =
  [%mel.raw
    {|function (sel, name) { const e = document.querySelector(sel); return e ? (e.getAttribute(name) ?? "none") : "missing" }|}]

let focused_name : unit -> string =
  [%mel.raw "function () { const e = document.activeElement; return (e && e.getAttribute('name')) || 'none' }"]

let set_field : string -> string -> unit =
  [%mel.raw "function (sel, v) { document.querySelector(sel).value = v }"]

let attribute_nth : int -> string -> string -> string =
  [%mel.raw
    {|function (i, sel, name) { const e = document.querySelectorAll('form')[i].querySelector(sel); return e ? (e.getAttribute(name) ?? "none") : "missing" }|}]

let set_input_nth : int -> string -> unit =
  [%mel.raw "function (i, v) { document.querySelectorAll('form')[i].querySelector('input[name=body]').value = v }"]

let submit_nth : int -> unit =
  [%mel.raw
    {|function (i) {
  document.querySelectorAll('form')[i].dispatchEvent(new window.Event('submit', { bubbles: true, cancelable: true }));
}|}]

let focused_form : unit -> int =
  [%mel.raw
    "function () { const f = document.activeElement && document.activeElement.closest('form'); return f ? [].indexOf.call(document.querySelectorAll('form'), f) : -1 }"]

let focused_alert : unit -> bool =
  [%mel.raw "function () { const e = document.activeElement; return !!e && e.getAttribute('role') === 'alert' }"]

let record_console : unit -> unit =
  [%mel.raw
    "function () { globalThis.__error = globalThis.__error || console.error; globalThis.__errors = []; console.error = function (m) { globalThis.__errors.push(String(m)) } }"]

let restore_console : unit -> unit = [%mel.raw "function () { if (globalThis.__error) console.error = globalThis.__error }"]

let console_errors : unit -> string =
  [%mel.raw "function () { return (globalThis.__errors || []).join(' | ') }"]

let after_ms : int -> (unit -> unit) -> unit =
  [%mel.raw "function (ms, f) { setTimeout(function () { f() }, ms) }"]

let ok_value : int option ref = ref None

let view () =
  Form.make ~action:jot
    ~on_ok:(fun n -> ok_value := Some n)
    ~children:(fun form ->
      fragment
        [
          element "input" [ attr "name" "body"; attr "value" (Form.value form `Body) ] [];
          element "i" [] [ hole (fun () -> text (if State.get (Form.pending form) then "pending" else "idle")) ];
          Form.field_error_view form `Body (fun ~id m -> element "b" [ attr "id" id ] [ text m ]);
          Form.form_errors_view form (fun m -> element "u" [] [ text m ]);
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
          element "input" [ attr "name" "body"; attr "value" (Form.value form `Body) ] [];
          Form.field_error_view form `Body (fun ~id m -> element "b" [ attr "id" id ] [ text m ]);
        ])
    ()

let redirect_view () =
  Form.make ~action:jot ~key:"r"
    ~children:(fun form ->
      fragment
        [
          element "input" [ attr "name" "body"; attr "value" (Form.value form `Body) ] [];
          Form.form_errors_view form (fun m -> element "u" [] [ text m ]);
        ])
    ()

let author_view () =
  Form.make ~action:jot ~key:"au"
    ~children:(fun form ->
      fragment
        [
          element "input" [ attr "name" "body"; attr "value" (Form.value form `Body) ] [];
          element "input" [ attr "name" "note"; attr "aria-invalid" "true" ] [];
          Form.field_error_view form `Body (fun ~id m -> element "b" [ attr "id" id ] [ text m ]);
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
    entry_of "First" (plain_view "a");
    entry_of "Second" (plain_view "b");
    entry_of "Btn" button_view;
    entry_of "Redirect" redirect_view;
    entry_of "Author" author_view;
    entry_of "Toggled" toggled_view;
    entry_of "Invalid" Forms_shared.Invalid.view;
  ]

let island_of name view = runtime_island ~name ~props:`Null view

let record_navigation () =
  navigated := [];
  Private.platform := { !Private.platform with navigate = (fun ~replace:_ ~keep_scroll:_ u -> navigated := !navigated @ [ u ]) }

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

let entry = runtime_entry ~name:"Form" (fun json -> Result.map (fun () () -> view ()) (Codec.decode Codec.unit json))
let island () = runtime_island ~name:"Form" ~props:`Null view

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
        start (Server.to_string (fun () -> fragment [ island_of "First" (plain_view "a"); island_of "Second" (plain_view "b") ]));
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
        start (Server.to_string (fun () -> island_of "Redirect" redirect_view));
        record_console ();
        let answers =
          [ "javascript:alert(1)"; " JavaScript:alert(1)"; "https://evil.example/"; "//evil.example/x"; "data:text/html,x" ]
        in
        let rec go i = function
          | [] ->
              finish (fun () ->
                  check "not followed" "" (String.concat "," !navigated);
                  check "shown" "protocol error: refused a redirect" (text_of "u");
                  check "the URL in the console" "true"
                    (string_of_bool (Js.String.includes ~search:"data:text/html,x" (console_errors ())));
                  restore_console ();
                  Yuka.stop ())
          | l :: rest ->
              set_input_in "r" "x";
              submit_in "r";
              respond i 200 (Printf.sprintf {|{"ok":{"value":1,"redirect":%S}}|} l);
              after_ms 10 (fun () -> go (i + 1) rest)
        in
        go 0 answers );
    ( "form: two forms of one action and key: only the submitted form is marked and focused",
      fun finish ->
        record_console ();
        start (Server.to_string (fun () -> fragment [ island_of "First" (plain_view "a"); island_of "First" (plain_view "a") ]));
        set_input_nth 1 "x";
        submit_nth 1;
        respond 0 200 {|{"ok":{"errors":[["body","Too short"]]}}|};
        after_ms 10 (fun () ->
            finish (fun () ->
                check "the other form is not marked" "none" (attribute_nth 0 "input[name=body]" "aria-invalid");
                check "the submitted form is marked" "true" (attribute_nth 1 "input[name=body]" "aria-invalid");
                check "focus in the submitted form" "1" (string_of_int (focused_form ()));
                check "dev warning" "true"
                  (string_of_bool (Js.String.includes ~search:"two forms on this page" (console_errors ())));
                restore_console ();
                Yuka.stop ())) );
    ( "form: an aria-invalid that the author set stays",
      fun finish ->
        start (Server.to_string (fun () -> island_of "Author" author_view));
        set_input_in "au" "x";
        submit_in "au";
        respond 0 200 {|{"ok":{"errors":[["body","Too short"]]}}|};
        after_ms 10 (fun () ->
            finish (fun () ->
                check "the field with an error" "true" (attribute "input[name=body]" "aria-invalid");
                check "the author's aria-invalid" "true" (attribute "input[name=note]" "aria-invalid");
                Yuka.stop ())) );
    ( "form: an error for the whole form is in an alert and takes the focus",
      fun finish ->
        start (Server.to_string island);
        set_input "body" "x";
        ignore (submit ());
        respond 0 400 {|{"error":"Refused"}|};
        after_ms 10 (fun () ->
            finish (fun () ->
                check "in the alert" "Refused" (text_of "[role=alert] u");
                check "focusable" "-1" (attribute "[role=alert]" "tabindex");
                check "focus on the alert" "true" (string_of_bool (focused_alert ()));
                Yuka.stop ())) );
    ( "form: a 422 with only an error for the whole form hydrates with the same markup",
      fun finish ->
        let html =
          Private.print
            (let s = Private.session ~streaming:false ~islands_only:true in
             Private.set_form s ("jot", "", [ ("body", "sent") ], [ (None, "Whole form") ]);
             s)
            (fun () -> Private.node (island ()))
        in
        start html;
        let after = body_html () in
        finish (fun () ->
            check "server autofocus on the alert" "" (attribute "[role=alert]" "autofocus");
            check "no autofocus on the field" "none" (attribute "input[name=body]" "autofocus");
            check "error shown" "Whole form" (text_of "[role=alert] u");
            check "same markup after hydration" html after;
            Yuka.stop ()) );
    ( "form: the answer of a form that is gone does not navigate",
      fun finish ->
        start (Server.to_string (fun () -> island_of "Toggled" toggled_view));
        set_input "body" "x";
        ignore (submit ());
        State.update tick succ;
        respond 0 200 {|{"ok":{"value":1,"redirect":"/gone"}}|};
        after_ms 10 (fun () ->
            finish (fun () ->
                check "not followed" "" (String.concat "," !navigated);
                Yuka.stop ())) );
    ( "form: with no redirect and no on_ok, reload the page URL",
      fun finish ->
        start (Server.to_string (fun () -> island_of "First" (plain_view "a")));
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
            (fun () -> Private.node (island_of "Toggled" toggled_view))
        in
        start html;
        let first = text_of "b" in
        State.update tick succ;
        let remounted = (text_of "b", input_value "body") in
        let remounted_marks = (attribute "input[name=body]" "aria-invalid", attribute "input[name=body]" "aria-describedby") in
        set_input "body" "longer";
        ignore (submit ());
        State.update tick succ;
        finish (fun () ->
            check "shown at hydration" "Too short" first;
            check "kept after a new render" "Too short" (fst remounted);
            check "value kept after a new render" "sent" (snd remounted);
            check "aria-invalid after a new render" "true" (fst remounted_marks);
            check "aria-describedby after a new render" "jot-body-error" (snd remounted_marks);
            check "gone after a client submit" "none" (text_of "b");
            check "aria-invalid gone after a client submit" "none" (attribute "input[name=body]" "aria-invalid");
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
            check "server aria-invalid" "true" (attribute "input[name=body]" "aria-invalid");
            check "server aria-describedby" "jot-body-error" (attribute "input[name=body]" "aria-describedby");
            check "error id" "jot-body-error" (attribute "b" "id");
            check "server autofocus" "" (attribute "input[name=body]" "autofocus");
            check "hydration moves no focus" "none" (focused_name ());
            check "same markup after hydration" html after;
            Yuka.stop ()) );
      ( "form: field errors from the server mark the field and take the focus, a valid submit clears them",
      fun finish ->
        start (Server.to_string island);
        let before = (attribute "input[name=body]" "aria-invalid", attribute "input[name=body]" "aria-describedby") in
        set_input "body" "x";
        ignore (submit ());
        respond 0 200 {|{"ok":{"errors":[["body","Too short"]]}}|};
        after_ms 10 (fun () ->
            let invalid = attribute "input[name=body]" "aria-invalid" in
            let described = attribute "input[name=body]" "aria-describedby" in
            let error_id = attribute "b" "id" in
            let focus = focused_name () in
            set_input "body" "longer";
            ignore (submit ());
            let during = attribute "input[name=body]" "aria-invalid" in
            respond 1 200 {|{"ok":{"value":5}}|};
            after_ms 10 (fun () ->
                finish (fun () ->
                    check "no aria-invalid before" "none" (fst before);
                    check "no aria-describedby before" "none" (snd before);
                    check "aria-invalid" "true" invalid;
                    check "aria-describedby" "jot-body-error" described;
                    check "the error has the id" "jot-body-error" error_id;
                    check "focus on the field" "body" focus;
                    check "cleared at the next submit" "none" during;
                    check "no aria-invalid after" "none" (attribute "input[name=body]" "aria-invalid");
                    check "no aria-describedby after" "none" (attribute "input[name=body]" "aria-describedby");
                    Yuka.stop ()))) );
    ( "form: a decode error in the browser marks the first wrong field and focuses it",
      fun finish ->
        start (Server.to_string (fun () -> island_of "Invalid" Forms_shared.Invalid.view));
        set_field "input[name=count]" "x3";
        ignore (submit ());
        after_ms 10 (fun () ->
            let marks =
              ( attribute "input[name=count]" "aria-invalid",
                attribute "input[name=count]" "aria-describedby",
                attribute "input[name=title]" "aria-invalid",
                attribute "input[name=title]" "aria-describedby" )
            in
            let focus = focused_name () in
            let count_error = text_of "#save_entry-k-count-error" in
            set_field "input[name=count]" "3";
            ignore (submit ());
            after_ms 10 (fun () ->
                finish (fun () ->
                    let count_invalid, count_described, title_invalid, title_described = marks in
                    check "count invalid" "true" count_invalid;
                    check "count described by its error" "save_entry-k-count-error" count_described;
                    check "count error element" "Not a whole number" count_error;
                    check "title valid" "none" title_invalid;
                    check "title keeps its own describedby" "hint" title_described;
                    check "focus on count" "count" focus;
                    check "count valid again" "none" (attribute "input[name=count]" "aria-invalid");
                    check "count describedby gone" "none" (attribute "input[name=count]" "aria-describedby");
                    check "title describedby kept" "hint" (attribute "input[name=title]" "aria-describedby");
                    Yuka.stop ()))) );
    ( "form: a 422 with several fields hydrates with the server marks and the author's describedby",
      fun finish ->
        let html =
          Private.print
            (let s = Private.session ~streaming:false ~islands_only:true in
             Private.set_form s Forms_shared.Invalid.sent;
             s)
            (fun () -> Private.node (island_of "Invalid" Forms_shared.Invalid.view))
        in
        start html;
        let after = body_html () in
        finish (fun () ->
            check "title" "hint save_entry-k-title-error" (attribute "input[name=title]" "aria-describedby");
            check "count" "save_entry-k-count-error" (attribute "input[name=count]" "aria-describedby");
            check "level" "true" (attribute "select[name=level]" "aria-invalid");
            check "tags valid" "none" (attribute "textarea[name=tags]" "aria-invalid");
            check "count error element" "Not a whole number" (text_of "#save_entry-k-count-error");
            check "same markup after hydration" html after;
            Yuka.stop ()) );
  ]
