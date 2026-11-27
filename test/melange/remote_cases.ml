open Yuka

let check = Cases.check

let setup_fetch : bool -> unit =
  [%mel.raw
    {|function (ignoreAbort) {
  globalThis.__rcalls = [];
  globalThis.fetch = function (url, init) {
    const call = { url: url, body: init.body, aborted: false };
    globalThis.__rcalls.push(call);
    return new Promise(function (resolve, reject) {
      call.respond = function (status, body) {
        resolve({ status: status, text: function () { return Promise.resolve(body); } });
      };
      init.signal.addEventListener("abort", function () {
        call.aborted = true;
        if (!ignoreAbort) reject(new Error("aborted"));
      });
    });
  };
}|}]

let fetches : unit -> int = [%mel.raw "function () { return globalThis.__rcalls.length }"]
let fetch_body : int -> string = [%mel.raw "function (i) { return globalThis.__rcalls[i].body }"]
let aborted : int -> bool = [%mel.raw "function (i) { return globalThis.__rcalls[i].aborted }"]
let respond : int -> int -> string -> unit =
  [%mel.raw "function (i, status, body) { globalThis.__rcalls[i].respond(status, body) }"]

let set_body : string -> unit = [%mel.raw "function (h) { document.body.innerHTML = h }"]
let append_html : string -> unit =
  [%mel.raw "function (h) { document.body.insertAdjacentHTML('beforeend', h) }"]

let shown : unit -> string =
  [%mel.raw "function () { const b = document.querySelector('yuka-island b'); return b ? b.textContent : 'none' }"]

let shown_all : unit -> string =
  [%mel.raw "function () { return Array.from(document.querySelectorAll('yuka-island b'), function (b) { return b.textContent }).join(',') }"]

let set_ready : string -> unit =
  [%mel.raw
    "function (v) { Object.defineProperty(document, 'readyState', { configurable: true, get: function () { return v } }) }"]

let clear_ready : unit -> unit = [%mel.raw "function () { delete document.readyState }"]

let dispatch_ready : unit -> unit =
  [%mel.raw "function () { document.dispatchEvent(new window.Event('DOMContentLoaded')) }"]

let capture_warnings : unit -> unit =
  [%mel.raw
    {|function () { globalThis.__warns = []; globalThis.__warn = console.warn; console.warn = function (m) { globalThis.__warns.push(String(m)); }; }|}]

let warnings : unit -> string =
  [%mel.raw {|function () { console.warn = globalThis.__warn; return globalThis.__warns.join("|"); }|}]

let after_ms : int -> (unit -> unit) -> unit =
  [%mel.raw "function (ms, f) { setTimeout(function () { f() }, ms) }"]

let query = Action.query ~name:"q" ~input:Codec.string ~output:Codec.string
let input = State.make "a"
let handle : string Remote.t option ref = ref None
let retry = ref Remote.default_retry

let show (s : string Status.t) =
  match s with
  | Status.Idle -> "idle"
  | Status.Loading None -> "loading"
  | Status.Loading (Some d) -> "loading " ^ d
  | Status.Ready { data; _ } -> "ready " ^ data
  | Status.Failed { error; _ } -> "failed " ^ Status.error_to_string error

let view () =
  let r = Remote.make ~retry:!retry query (fun () -> State.get input) in
  handle := Some r;
  element "b" [] [ hole (fun () -> text (show (State.get (Remote.state r)))) ]

let later = State.make false

let late_entry =
  runtime_entry ~name:"Late" (fun json ->
      Result.map
        (fun () () ->
          element "i" []
            [
              hole (fun () ->
                  if State.get later then (
                    let r = Remote.make query (fun () -> "late") in
                    element "u" [] [ hole (fun () -> text (show (State.get (Remote.state r)))) ])
                  else empty);
            ])
        (Codec.decode Codec.unit json))

let shown_late : unit -> string =
  [%mel.raw "function () { const u = document.querySelector('yuka-island u'); return u ? u.textContent : 'none' }"]

let entry =
  runtime_entry ~name:"Query" (fun json -> Result.map (fun () () -> view ()) (Codec.decode Codec.unit json))

let start () = Yuka.render ~islands:(runtime_registry [ entry ]) ~navigation:false ()

let island_html ?(shown = "loading") ?answer () =
  {|<yuka-island data-name="Query" data-id="i1" style="display:contents"><b>|} ^ shown ^ {|</b></yuka-island>|}
  ^ Option.value answer ~default:""
  ^ {|<script type="application/json" data-yuka-props="i1">null</script>|}

let answer_for value json =
  {|<script type="application/json" data-yuka-answer="r:q &quot;|} ^ value ^ {|&quot;">|} ^ json ^ "</script>"

let pending_for value =
  {|<script type="application/json" data-yuka-answer="r:q &quot;|} ^ value ^ {|&quot;" data-pending></script>|}

let fresh ?(ignore_abort = false) ?(value = "a") ?shown ?answer ?(attempts = Remote.default_retry) () =
  Yuka.stop ();
  setup_fetch ignore_abort;
  State.set input value;
  retry := attempts;
  set_body (island_html ?shown ?answer ())

let mutation = Action.mutation ~name:"m" ~input:Codec.string ~output:Codec.string
let pick = State.make "a"

let call_text = function
  | Async.Done (Ok v) -> v
  | Async.Done (Error e) -> "error " ^ Status.error_to_string e
  | Async.Failed m -> "failed " ^ m
  | Async.Pending -> "pending"

let fresh_calls ?(ignore_abort = false) () =
  Yuka.stop ();
  setup_fetch ignore_abort;
  set_body "";
  Yuka.render ~islands:(runtime_registry []) ~navigation:false ()

let in_effect call =
  let result = ref (Async.return (Error (Status.Network "not called"))) in
  let (), dispose = with_owner (fun () -> Effect.after (fun () -> result := call ())) in
  (result, dispose)

let async =
  [
    ( "action: a query call in Effect.after whose input changes twice: only the latest answer is written",
      fun finish ->
        fresh_calls ();
        State.set pick "a";
        let written = ref [] in
        let (), dispose =
          with_owner (fun () ->
              Effect.after (fun () ->
                  Async.on_settled (Action.call query (State.get pick)) (fun st ->
                      written := call_text st :: !written)))
        in
        State.set pick "b";
        State.set pick "c";
        after_ms 10 (fun () ->
            respond 2 200 {|{"ok":"C"}|};
            after_ms 10 (fun () ->
                finish (fun () ->
                    check "three fetches" "3" (string_of_int (fetches ()));
                    check "first aborted" "true" (string_of_bool (aborted 0));
                    check "second aborted" "true" (string_of_bool (aborted 1));
                    check "third not aborted" "false" (string_of_bool (aborted 2));
                    check "written" "C" (String.concat "," (List.rev !written));
                    dispose ();
                    Yuka.stop ()))) );
    ( "action: disposing the owner aborts a query call, which stays pending",
      fun finish ->
        fresh_calls ();
        let result, dispose = in_effect (fun () -> Action.call query "x") in
        dispose ();
        after_ms 10 (fun () ->
            finish (fun () ->
                check "aborted" "true" (string_of_bool (aborted 0));
                check "pending" "pending" (call_text (Async.status !result));
                Yuka.stop ())) );
    ( "action: disposing the owner does not abort a mutation call",
      fun finish ->
        fresh_calls ();
        let result, dispose = in_effect (fun () -> Action.call mutation "x") in
        dispose ();
        after_ms 10 (fun () ->
            respond 0 200 {|{"ok":"M"}|};
            after_ms 10 (fun () ->
                finish (fun () ->
                    check "not aborted" "false" (string_of_bool (aborted 0));
                    check "answer" "M" (call_text (Async.status !result));
                    Yuka.stop ()))) );
    ( "action: the abort of start stops a mutation call, which stays pending",
      fun finish ->
        fresh_calls ~ignore_abort:true ();
        let result, abort = Action.start mutation "x" in
        abort ();
        respond 0 200 {|{"ok":"M"}|};
        after_ms 10 (fun () ->
            finish (fun () ->
                check "aborted" "true" (string_of_bool (aborted 0));
                check "pending" "pending" (call_text (Async.status result));
                Yuka.stop ())) );
    ( "remote: a key change aborts the request in flight",
      fun finish ->
        fresh ();
        start ();
        let first = fetches () in
        State.set input "b";
        finish (fun () ->
            check "one fetch at start" "1" (string_of_int first);
            check "first body" {|"a"|} (fetch_body 0);
            check "first aborted" "true" (string_of_bool (aborted 0));
            check "second sent" {|"b"|} (fetch_body 1);
            Yuka.stop ()) );
    ( "remote: only the latest request writes the status",
      fun finish ->
        fresh ~ignore_abort:true ();
        start ();
        State.set input "b";
        respond 1 200 {|{"ok":"B"}|};
        after_ms 10 (fun () ->
            respond 0 200 {|{"ok":"A"}|};
            after_ms 10 (fun () ->
                finish (fun () ->
                    check "status" "ready B" (shown ());
                    Yuka.stop ()))) );
    ( "remote: 503 then 200 is Ready after one retry",
      fun finish ->
        fresh ~attempts:(Remote.retry ~attempts:2 ~delay_ms:(fun _ -> 0)) ();
        start ();
        respond 0 503 "";
        after_ms 20 (fun () ->
            respond 1 200 {|{"ok":"A"}|};
            after_ms 10 (fun () ->
                finish (fun () ->
                    check "two fetches" "2" (string_of_int (fetches ()));
                    check "ready" "ready A" (shown ());
                    Yuka.stop ()))) );
    ( "remote: 400 fails at once",
      fun finish ->
        fresh ~attempts:(Remote.retry ~attempts:2 ~delay_ms:(fun _ -> 0)) ();
        start ();
        respond 0 400 {|{"error":"bad title"}|};
        after_ms 20 (fun () ->
            finish (fun () ->
                check "one fetch" "1" (string_of_int (fetches ()));
                check "rejected" "failed bad title" (shown ());
                Yuka.stop ())) );
    ( "action: disposing the owner aborts a query call from a handler in a hole that reads nothing",
      fun finish ->
        fresh_calls ();
        let c = Dom_cases.container "" in
        let dispose =
          Private.render (Dom_cases.as_element c) (fun () ->
              element "div" []
                [
                  hole (fun () ->
                      element "button" [ attr "id" "sx"; on "click" (fun _ -> ignore (Action.call query "x")) ] []);
                ])
        in
        Dom_cases.click (Dom_cases.query c "#sx");
        dispose ();
        after_ms 10 (fun () ->
            finish (fun () ->
                check "aborted" "true" (string_of_bool (aborted 0));
                Yuka.stop ())) );
    ( "remote: stop aborts",
      fun finish ->
        fresh ();
        start ();
        Yuka.stop ();
        finish (fun () -> check "aborted" "true" (string_of_bool (aborted 0))) );
    ( "remote: an embedded answer is read on hydration, with no fetch",
      fun finish ->
        fresh ~shown:"ready A" ~answer:(answer_for "a" {|{"ok":"A"}|}) ();
        capture_warnings ();
        start ();
        let logged = warnings () in
        finish (fun () ->
            check "no fetch" "0" (string_of_int (fetches ()));
            check "ready" "ready A" (shown ());
            check "no mismatch" "" logged;
            Yuka.stop ()) );
    ( "remote: each island reads the answer of its render, not an older one of the same key",
      fun finish ->
        Yuka.stop ();
        setup_fetch false;
        State.set input "a";
        retry := Remote.default_retry;
        let island id answer =
          {|<yuka-island data-name="Query" data-id="|} ^ id ^ {|" style="display:contents"><b>ready NEW</b></yuka-island>|}
          ^ answer ^ {|<script type="application/json" data-yuka-props="|} ^ id ^ {|">null</script>|}
        in
        (* The answer of a layout that a client navigation kept, then the new
           page: i1 printed the answer, and i2, of the same render, has none. *)
        set_body (answer_for "a" {|{"ok":"OLD"}|} ^ island "i1" (answer_for "a" {|{"ok":"NEW"}|}) ^ island "i2" "");
        start ();
        finish (fun () ->
            check "no fetch" "0" (string_of_int (fetches ()));
            check "both read the new answer" "ready NEW,ready NEW" (shown_all ());
            Yuka.stop ()) );
    ( "remote: an embedded error is read too",
      fun finish ->
        fresh ~attempts:Remote.no_retry ~shown:"failed server error"
          ~answer:(answer_for "a" {|{"error":{"kind":"server"}}|}) ();
        start ();
        finish (fun () ->
            check "no fetch" "0" (string_of_int (fetches ()));
            check "failed" "failed server error" (shown ());
            Yuka.stop ()) );
    ( "remote: a pending answer, then the full one, gives no fetch",
      fun finish ->
        fresh ~answer:(pending_for "a") ();
        set_ready "loading";
        start ();
        let before = shown () in
        append_html (answer_for "a" {|{"ok":"late"}|});
        after_ms 10 (fun () ->
            clear_ready ();
            finish (fun () ->
                check "loading first" "loading" before;
                check "ready" "ready late" (shown ());
                check "no fetch" "0" (string_of_int (fetches ()));
                Yuka.stop ())) );
    ( "remote: a pending answer that never comes is fetched when the document ends",
      fun finish ->
        fresh ~answer:(pending_for "a") ();
        set_ready "loading";
        start ();
        let before = fetches () in
        set_ready "interactive";
        dispatch_ready ();
        after_ms 10 (fun () ->
            clear_ready ();
            finish (fun () ->
                check "no fetch while loading" "0" (string_of_int before);
                check "one fetch" "1" (string_of_int (fetches ()));
                Yuka.stop ())) );
    ( "remote: an embedded network error is retried",
      fun finish ->
        fresh ~shown:"failed network error: timeout"
          ~attempts:(Remote.retry ~attempts:1 ~delay_ms:(fun _ -> 0))
          ~answer:(answer_for "a" {|{"error":{"kind":"network","message":"timeout"}}|})
          ();
        capture_warnings ();
        start ();
        let at_start = shown () in
        let logged = warnings () in
        after_ms 10 (fun () ->
            let sent = fetches () in
            if sent > 0 then respond 0 200 {|{"ok":"A"}|};
            after_ms 10 (fun () ->
                finish (fun () ->
                    check "hydrated with the embedded error" "failed network error: timeout" at_start;
                    check "no mismatch" "" logged;
                    check "one fetch" "1" (string_of_int sent);
                    check "ready" "ready A" (shown ());
                    Yuka.stop ()))) );
    ( "remote: a use created later reads an answer that came with its content",
      fun finish ->
        Yuka.stop ();
        setup_fetch false;
        State.set later false;
        set_body
          {|<yuka-island data-name="Late" data-id="i1" style="display:contents"><i></i></yuka-island><script type="application/json" data-yuka-props="i1">null</script>|};
        Yuka.render ~islands:(runtime_registry [ late_entry ]) ~navigation:false ();
        append_html (answer_for "late" {|{"ok":"L"}|});
        State.set later true;
        finish (fun () ->
            check "no fetch" "0" (string_of_int (fetches ()));
            check "ready" "ready L" (shown_late ());
            Yuka.stop ()) );
    ( "remote: refetch after hydration sends a request",
      fun finish ->
        fresh ~shown:"ready A" ~answer:(answer_for "a" {|{"ok":"A"}|}) ();
        start ();
        Remote.refetch (Option.get !handle);
        finish (fun () ->
            check "one fetch" "1" (string_of_int (fetches ()));
            check "keeps the data while loading" "loading A" (shown ());
            Yuka.stop ()) );
  ]
