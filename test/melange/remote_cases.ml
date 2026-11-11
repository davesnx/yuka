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
  let r = Remote.use ~retry:!retry query (fun () -> State.get input) in
  handle := Some r;
  lower "b" [] [ hole (fun () -> text (show (Remote.status r))) ]

let later = State.make false

let late_entry =
  Client.entry ~name:"L" (fun json ->
      Result.map
        (fun () () ->
          lower "i" []
            [
              hole (fun () ->
                  if State.get later then (
                    let r = Remote.use query (fun () -> "late") in
                    lower "u" [] [ hole (fun () -> text (show (Remote.status r))) ])
                  else empty);
            ])
        (Codec.decode Codec.unit json))

let shown_late : unit -> string =
  [%mel.raw "function () { const u = document.querySelector('yuka-island u'); return u ? u.textContent : 'none' }"]

let entry =
  Client.entry ~name:"Q" (fun json -> Result.map (fun () () -> view ()) (Codec.decode Codec.unit json))

let start () = Yuka.render ~islands:(Client.registry [ entry ]) ~navigation:false ()

let island_html ?(shown = "loading") ?answer () =
  {|<yuka-island data-name="Q" data-id="i1" style="display:contents"><b>|} ^ shown ^ {|</b></yuka-island>|}
  ^ Option.value answer ~default:""
  ^ {|<script type="application/json" data-yuka-props="i1">null</script>|}

let answer_for value json =
  {|<script type="application/json" data-yuka-answer="r:q &quot;|} ^ value ^ {|&quot;">|} ^ json ^ "</script>"

let pending_for value =
  {|<script type="application/json" data-yuka-answer="r:q &quot;|} ^ value ^ {|&quot;" data-pending></script>|}

let fresh ?(ignore_abort = false) ?(value = "a") ?shown ?answer ?(attempts = Remote.default_retry) () =
  Yuka.unmount ();
  setup_fetch ignore_abort;
  State.set input value;
  retry := attempts;
  set_body (island_html ?shown ?answer ())

let async =
  [
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
            Yuka.unmount ()) );
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
                    Yuka.unmount ()))) );
    ( "remote: 503 then 200 is Ready after one retry",
      fun finish ->
        fresh ~attempts:{ Remote.attempts = 2; delay_ms = (fun _ -> 0) } ();
        start ();
        respond 0 503 "";
        after_ms 20 (fun () ->
            respond 1 200 {|{"ok":"A"}|};
            after_ms 10 (fun () ->
                finish (fun () ->
                    check "two fetches" "2" (string_of_int (fetches ()));
                    check "ready" "ready A" (shown ());
                    Yuka.unmount ()))) );
    ( "remote: 400 fails at once",
      fun finish ->
        fresh ~attempts:{ Remote.attempts = 2; delay_ms = (fun _ -> 0) } ();
        start ();
        respond 0 400 {|{"error":"bad title"}|};
        after_ms 20 (fun () ->
            finish (fun () ->
                check "one fetch" "1" (string_of_int (fetches ()));
                check "rejected" "failed bad title" (shown ());
                Yuka.unmount ())) );
    ( "remote: unmount aborts",
      fun finish ->
        fresh ();
        start ();
        Yuka.unmount ();
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
            Yuka.unmount ()) );
    ( "remote: an embedded error is read too",
      fun finish ->
        fresh ~attempts:Remote.no_retry ~shown:"failed server error"
          ~answer:(answer_for "a" {|{"error":{"kind":"server"}}|}) ();
        start ();
        finish (fun () ->
            check "no fetch" "0" (string_of_int (fetches ()));
            check "failed" "failed server error" (shown ());
            Yuka.unmount ()) );
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
                Yuka.unmount ())) );
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
                Yuka.unmount ())) );
    ( "remote: an embedded network error is retried",
      fun finish ->
        fresh ~shown:"failed network error: timeout"
          ~attempts:{ Remote.attempts = 1; delay_ms = (fun _ -> 0) }
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
                    Yuka.unmount ()))) );
    ( "remote: a use created later reads an answer that came with its content",
      fun finish ->
        Yuka.unmount ();
        setup_fetch false;
        State.set later false;
        set_body
          {|<yuka-island data-name="L" data-id="i1" style="display:contents"><i></i></yuka-island><script type="application/json" data-yuka-props="i1">null</script>|};
        Yuka.render ~islands:(Client.registry [ late_entry ]) ~navigation:false ();
        append_html (answer_for "late" {|{"ok":"L"}|});
        State.set later true;
        finish (fun () ->
            check "no fetch" "0" (string_of_int (fetches ()));
            check "ready" "ready L" (shown_late ());
            Yuka.unmount ()) );
    ( "remote: refetch after hydration sends a request",
      fun finish ->
        fresh ~shown:"ready A" ~answer:(answer_for "a" {|{"ok":"A"}|}) ();
        start ();
        Remote.refetch (Option.get !handle);
        finish (fun () ->
            check "one fetch" "1" (string_of_int (fetches ()));
            check "keeps the data while loading" "loading A" (shown ());
            Yuka.unmount ()) );
  ]
