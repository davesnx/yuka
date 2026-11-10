open Yuka

let check = Cases.check

let install : unit -> unit =
  [%mel.raw
    {|function () {
  globalThis.__ws = [];
  globalThis.__timers = [];
  globalThis.__tid = 0;
  globalThis.__realSetTimeout = globalThis.__realSetTimeout || setTimeout;
  globalThis.__realClearTimeout = globalThis.__realClearTimeout || clearTimeout;
  globalThis.setTimeout = function (f, ms) {
    const id = ++globalThis.__tid;
    globalThis.__timers.push({ id: id, f: f, ms: ms });
    return id;
  };
  globalThis.clearTimeout = function (id) {
    globalThis.__timers = globalThis.__timers.filter(function (t) { return t.id !== id; });
  };
  globalThis.WebSocket = function (url) {
    this.url = url;
    this.sent = [];
    this.readyState = 0;
    this.closedWith = null;
    globalThis.__ws.push(this);
  };
  globalThis.WebSocket.prototype.send = function (t) { this.sent.push(t); };
  globalThis.WebSocket.prototype.close = function (code) { this.closedWith = code; };
  globalThis.__random = Math.random;
  Math.random = function () { return globalThis.__rand === undefined ? 1 : globalThis.__rand; };
}|}]

let uninstall : unit -> unit =
  [%mel.raw
    {|function () {
  globalThis.setTimeout = globalThis.__realSetTimeout;
  globalThis.clearTimeout = globalThis.__realClearTimeout;
  Math.random = globalThis.__random;
  delete globalThis.__rand;
  Object.defineProperty(window.navigator, "onLine", { configurable: true, get: function () { return true; } });
}|}]

let sockets : unit -> int = [%mel.raw "function () { return globalThis.__ws.length }"]
let sent : int -> string = [%mel.raw "function (i) { return globalThis.__ws[i].sent.join(' ') }"]
let clear_sent : int -> unit = [%mel.raw "function (i) { globalThis.__ws[i].sent = [] }"]

let closed_with : int -> string =
  [%mel.raw "function (i) { const c = globalThis.__ws[i].closedWith; return c === null ? 'open' : String(c) }"]

let ws_open : int -> unit =
  [%mel.raw "function (i) { const s = globalThis.__ws[i]; s.readyState = 1; s.onopen && s.onopen(); }"]

let ws_message : int -> string -> unit =
  [%mel.raw "function (i, t) { const s = globalThis.__ws[i]; s.onmessage && s.onmessage({ data: t }); }"]

let ws_close : int -> int -> unit =
  [%mel.raw "function (i, code) { const s = globalThis.__ws[i]; s.readyState = 3; s.onclose && s.onclose({ code: code }); }"]

let timers : unit -> string =
  [%mel.raw "function () { return globalThis.__timers.map(function (t) { return String(t.ms); }).join(' ') }"]

let fire : int -> unit =
  [%mel.raw
    {|function (ms) {
  const due = globalThis.__timers.filter(function (t) { return t.ms === ms; });
  globalThis.__timers = globalThis.__timers.filter(function (t) { return t.ms !== ms; });
  due.forEach(function (t) { t.f(); });
}|}]

let set_random : float -> unit = [%mel.raw "function (r) { globalThis.__rand = r }"]

let go_offline : unit -> unit =
  [%mel.raw
    {|function () { Object.defineProperty(window.navigator, "onLine", { configurable: true, get: function () { return false; } }); }|}]

let go_online : unit -> unit =
  [%mel.raw
    {|function () {
  Object.defineProperty(window.navigator, "onLine", { configurable: true, get: function () { return true; } });
  window.dispatchEvent(new window.Event("online"));
}|}]

let set_body : string -> unit = [%mel.raw "function (h) { document.body.innerHTML = h }"]

let topic = Topic.declare ~name:"items" ~key:Codec.string ~state:(Codec.list Codec.string)

let show (t : string list Live.t) =
  match Live.status t with
  | Status.Idle -> "idle"
  | Status.Loading None -> "loading"
  | Status.Loading (Some d) -> "loading " ^ String.concat "," d
  | Status.Ready { data; stale } -> (if stale then "stale " else "ready ") ^ String.concat "," data
  | Status.Failed { error; _ } -> "failed " ^ Status.error_to_string error

let state ?(seq = 1) id items =
  Printf.sprintf {|{"t":"state","id":%d,"seq":%d,"state":[%s]}|} id seq
    (String.concat "," (List.map (Printf.sprintf "%S") items))

let fresh () =
  Private.reset_live ();
  install ();
  set_body ""

let use key = Yuka.owner (fun () -> Live.use topic (fun () -> key))

let with_env f () =
  fresh ();
  match f () with
  | () -> uninstall ()
  | exception e ->
      uninstall ();
      raise e

let hello = {|{"t":"hello","v":1,"csrf":"from-server"}|}

let one_socket () =
  let a, stop_a = use "a" in
  check "one socket" "1" (string_of_int (sockets ()));
  ws_open 0;
  check "hello then sub" {|{"t":"hello","v":1,"csrf":""} {"t":"sub","id":1,"topic":"items","key":"a"}|} (sent 0);
  let b, stop_b = use "b" in
  check "same socket" "1" (string_of_int (sockets ()));
  check "second sub"
    {|{"t":"hello","v":1,"csrf":""} {"t":"sub","id":1,"topic":"items","key":"a"} {"t":"sub","id":2,"topic":"items","key":"b"}|}
    (sent 0);
  ws_message 0 (state 1 [ "x" ]);
  ws_message 0 (state 2 [ "y" ]);
  check "a" "ready x" (show a);
  check "b" "ready y" (show b);
  stop_a ();
  stop_b ()

let lower_seq_dropped () =
  let a, stop = use "a" in
  ws_open 0;
  ws_message 0 (state ~seq:5 1 [ "new" ]);
  ws_message 0 (state ~seq:4 1 [ "old" ]);
  check "kept" "ready new" (show a);
  stop ()

let reconnect () =
  set_random 1.;
  let a, stop_a = use "a" in
  let b, stop_b = use "b" in
  ws_open 0;
  ws_message 0 hello;
  ws_message 0 (state 1 [ "x" ]);
  ws_close 0 1006;
  check "stale with data" "stale x" (show a);
  check "loading without data" "loading" (show b);
  check "first delay" "250" (timers ());
  fire 250;
  ws_close 1 1006;
  check "second delay" "500" (timers ());
  set_random 0.;
  fire 500;
  ws_close 2 1006;
  check "third delay, half" "500" (timers ());
  fire 500;
  ws_open 3;
  check "every use again, with the server token"
    {|{"t":"hello","v":1,"csrf":"from-server"} {"t":"sub","id":3,"topic":"items","key":"a"} {"t":"sub","id":4,"topic":"items","key":"b"}|}
    (sent 3);
  ws_message 3 hello;
  ws_message 3 (state 3 [ "x2" ]);
  check "fresh" "ready x2" (show a);
  set_random 1.;
  ws_close 3 1006;
  check "reset after hello" "250" (timers ());
  stop_a ();
  stop_b ()

let forbidden () =
  let a, stop = use "a" in
  ws_open 0;
  ws_close 0 4403;
  check "failed" "failed forbidden" (show a);
  check "no reconnect" "" (timers ());
  stop ()

let protocol_close () =
  let a, stop = use "a" in
  ws_open 0;
  ws_close 0 4426;
  check "failed" "failed protocol error: live socket closed with 4426" (show a);
  check "no reconnect" "" (timers ());
  stop ()

let idle_close () =
  let _, stop = use "a" in
  ws_open 0;
  stop ();
  check "after 2 s (and the ping timer)" "25000 2000" (timers ());
  check "still open" "open" (closed_with 0);
  fire 2000;
  check "closed" "1000" (closed_with 0);
  check "no reconnect, no wait for the server" "" (timers ())

let navigation_keeps_socket () =
  let _, stop = use "a" in
  ws_open 0;
  stop ();
  let _, stop = use "b" in
  check "close timer gone" "25000" (timers ());
  check "same socket" "1" (string_of_int (sockets ()));
  check "still open" "open" (closed_with 0);
  stop ()

let embedded () =
  set_body
    {|<script type="application/json" data-yuka-answer="l:items &quot;a&quot;">{"ok":["e"]}</script><script type="application/json" data-yuka-answer="l:csrf">{"ok":"page-token"}</script>|};
  let a, stop = use "a" in
  check "ready before open" "ready e" (show a);
  ws_open 0;
  check "token" {|{"t":"hello","v":1,"csrf":"page-token"}|} (List.hd (String.split_on_char ' ' (sent 0)));
  stop ()

let error_message () =
  let a, stop = use "a" in
  ws_open 0;
  ws_message 0 {|{"t":"error","id":1,"code":"rejected","message":"No such list"}|};
  check "failed" "failed No such list" (show a);
  ws_close 0 1006;
  fire 250;
  ws_open 1;
  check "no sub again" {|{"t":"hello","v":1,"csrf":""}|} (sent 1);
  stop ()

let offline () =
  let a, stop = use "a" in
  ws_open 0;
  ws_message 0 (state 1 [ "x" ]);
  go_offline ();
  ws_close 0 1006;
  check "only the slow timer" "5000" (timers ());
  check "stale" "stale x" (show a);
  go_online ();
  check "reconnects" "2" (string_of_int (sockets ()));
  check "the slow timer is gone" "" (timers ());
  stop ()

let heartbeat () =
  let _, stop = use "a" in
  ws_open 0;
  check "ping timer" "25000" (timers ());
  clear_sent 0;
  fire 25000;
  check "ping" {|{"t":"ping"}|} (sent 0);
  ws_message 0 {|{"t":"pong"}|};
  check "pong cancels the wait" "25000" (timers ());
  fire 25000;
  fire 10000;
  check "closed after 10 s of silence" "4000" (closed_with 0);
  check "reconnect at once, with no wait for the server" "250" (timers ());
  stop ()

let edit (s : string list) = s @ [ "mine" ]

let mutate_settles_on_synced () =
  let a, stop = use "a" in
  ws_open 0;
  ws_message 0 (state ~seq:1 1 [ "x" ]);
  clear_sent 0;
  let result, resolve, _ = Async.make () in
  let _ = Live.mutate a edit (fun () -> result) in
  check "shown at once" "ready x,mine" (show a);
  ws_message 0 (state ~seq:2 1 [ "x"; "mine" ]);
  check "published state first" "ready x,mine,mine" (show a);
  resolve ();
  check "sync sent" {|{"t":"sync","id":1,"ref":0}|} (sent 0);
  check "still pending" "ready x,mine,mine" (show a);
  ws_message 0 {|{"t":"synced","id":1,"ref":0}|};
  check "settled" "ready x,mine" (show a);
  stop ()

let mutate_rolls_back () =
  let a, stop = use "a" in
  ws_open 0;
  ws_message 0 (state 1 [ "x" ]);
  let result, _, fail = Async.make () in
  let _ = Live.mutate a edit (fun () -> result) in
  fail "no";
  check "rolled back" "ready x" (show a);
  stop ()

let mutate_while_down () =
  let a, stop = use "a" in
  ws_open 0;
  ws_message 0 (state 1 [ "x" ]);
  let result, resolve, _ = Async.make () in
  let _ = Live.mutate a edit (fun () -> result) in
  ws_close 0 1006;
  resolve ();
  check "kept while down" "stale x,mine" (show a);
  fire 250;
  ws_open 1;
  check "sync after the sub"
    {|{"t":"hello","v":1,"csrf":""} {"t":"sub","id":2,"topic":"items","key":"a"} {"t":"sync","id":2,"ref":0}|}
    (sent 1);
  ws_message 1 (state 2 [ "x"; "mine" ]);
  ws_message 1 {|{"t":"synced","id":2,"ref":0}|};
  check "settled" "ready x,mine" (show a);
  stop ()

let key_change () =
  let k = State.make "a" in
  let a, stop = Yuka.owner (fun () -> Live.use topic (fun () -> State.get k)) in
  ws_open 0;
  ws_message 0 (state 1 [ "x" ]);
  clear_sent 0;
  State.set k "b";
  check "unsub then sub" {|{"t":"unsub","id":1} {"t":"sub","id":2,"topic":"items","key":"b"}|} (sent 0);
  check "loading with old data" "loading x" (show a);
  ws_message 0 (state 1 [ "late" ]);
  check "old id ignored" "loading x" (show a);
  ws_message 0 (state 2 [ "y" ]);
  check "new" "ready y" (show a);
  stop ()

let all =
  List.map
    (fun (name, f) -> ("live: " ^ name, with_env f))
    [
      ("one socket for every use, hello then sub", one_socket);
      ("a lower seq is dropped", lower_seq_dropped);
      ("close gives stale, backoff grows and resets after hello, reopen subscribes again", reconnect);
      ("close 4403 fails every use, no reconnect", forbidden);
      ("close 4426 fails with a protocol error, no reconnect", protocol_close);
      ("the last use closes the socket after 2 s", idle_close);
      ("a new use within 2 s keeps the socket", navigation_keeps_socket);
      ("an embedded answer gives Ready before the socket opens, and its token", embedded);
      ("an error message fails the use and it does not subscribe again", error_message);
      ("offline waits for the online event", offline);
      ("heartbeat: ping after 25 s, close after 10 s of silence", heartbeat);
      ("mutate settles on synced, after a state that came first", mutate_settles_on_synced);
      ("mutate rolls back on failure", mutate_rolls_back);
      ("mutate while the socket is down syncs after the next sub", mutate_while_down);
      ("a key change unsubscribes and subscribes", key_change);
    ]
