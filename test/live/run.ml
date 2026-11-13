open Yuka
module Live = Yuka.Server.Live

module Astring_like = struct
  let contains text part =
    let n = String.length part in
    let rec at i = i + n <= String.length text && (String.sub text i n = part || at (i + 1)) in
    at 0
end

let logged = ref []
let () = Yuka.Server.Testing.set_log (fun _ m -> logged := m :: !logged)

type fake = {
  mutable inbox : string option list;
  mutable waiter : (string option -> unit) option;
  mutable out : string list;
  mutable closed : int option;
  mutable closes : int;
  mutable gate : unit Async.t option;
  mutable broken : bool;
}

let fake () = { inbox = []; waiter = None; out = []; closed = None; closes = 0; gate = None; broken = false }

let receive f () =
  match f.inbox with
  | x :: rest ->
      f.inbox <- rest;
      Async.return x
  | [] ->
      let a, resolve, _ = Async.make () in
      f.waiter <- Some resolve;
      a

let connection ?(receive = receive) f =
  Live.connection
    ~send:(fun text ->
      if f.broken then Async.failed "broken pipe"
      else begin
        f.out <- f.out @ [ text ];
        match f.gate with Some g -> g | None -> Async.return ()
      end)
    ~receive:(receive f)
    ~close:(fun code ->
      f.closed <- Some code;
      f.closes <- f.closes + 1;
      Async.return ())

let deliver f x =
  match f.waiter with
  | Some w ->
      f.waiter <- None;
      w x
  | None -> f.inbox <- f.inbox @ [ x ]

let push f text = deliver f (Some text)
let hang_up f = deliver f None
let sleeps : (unit -> unit) list ref = ref []

let sleep _ =
  let a, resolve, _ = Async.make () in
  sleeps := resolve :: !sleeps;
  a

let sessions = ref 0

let fresh_session () =
  incr sessions;
  "s" ^ string_of_int !sessions

let start ?node ?(csrf = "good") ?(fresh = "next") ?(session = fresh_session ()) () =
  let f = fake () in
  let finished =
    Server.Testing.live_run ?node ~sleep (Server.Testing.context ~session ())
      ~verify_csrf:(fun t -> Async.return (t = csrf))
      ~token:(fun () -> fresh)
      (connection f)
  in
  (f, finished)

let hello = {|{"t":"hello","v":1,"csrf":"good"}|}
let sub id topic key = Printf.sprintf {|{"t":"sub","id":%d,"topic":"%s","key":%s}|} id topic key
let open_ ?node ?session () =
  let f, finished = start ?node ?session () in
  push f hello;
  f.out <- [];
  (f, finished)

let field name text =
  match Json.of_string text with
  | Ok (`Assoc f) -> List.assoc_opt name f
  | _ -> None

let states f =
  List.filter_map
    (fun t ->
      match (field "t" t, field "id" t, field "state" t) with
      | Some (`String "state"), Some (`Int id), Some s -> Some (id, Json.to_string s)
      | _ -> None)
    f.out

let seqs f =
  List.filter_map
    (fun t -> match (field "t" t, field "seq" t) with Some (`String "state"), Some (`Int s) -> Some s | _ -> None)
    f.out

let kinds f =
  List.filter_map (fun t -> match field "t" t with Some (`String k) -> Some k | _ -> None) f.out

let errors f =
  List.filter_map
    (fun t ->
      match (field "t" t, field "code" t) with
      | Some (`String "error"), Some (`String c) ->
          Some (c ^ match field "message" t with Some (`String "") | None -> "" | Some (`String m) -> " " ^ m | Some _ -> "")
      | _ -> None)
    f.out

let check_states msg expected f = Alcotest.(check (list (pair int string))) msg expected (states f)

let count = Topic.declare ~name:"count" ~key:Codec.string ~state:Codec.int
let loads = ref []
let gates : (string * (int -> unit) * (string -> unit)) list ref = ref []

let () =
  Live.serve count (fun key ->
      loads := key :: !loads;
      match key with
      | "boom" -> failwith "secret boom"
      | "nope" -> Server.Action.reject "Not yours"
      | k when String.length k > 4 && String.sub k 0 4 = "slow" ->
          let a, resolve, fail = Async.make () in
          gates := (k, resolve, fail) :: !gates;
          a
      | k -> Async.return (String.length k))

let forbidden = Topic.declare ~name:"private" ~key:Codec.string ~state:Codec.int
let () = Live.serve ~allow:(fun p k -> Server.Context.session p = Some k) forbidden (fun _ -> Async.return 1)

let gate key = List.find (fun (k, _, _) -> k = key) !gates

let hello_cases =
  [
    ( "a wrong version closes 4426",
      fun () ->
        let f, _ = start () in
        push f {|{"t":"hello","v":2,"csrf":"good"}|};
        Alcotest.(check (option int)) "code" (Some 4426) f.closed );
    ( "a bad CSRF token closes 4403",
      fun () ->
        let f, finished = start () in
        push f {|{"t":"hello","v":1,"csrf":"bad"}|};
        Alcotest.(check (option int)) "code" (Some 4403) f.closed;
        Alcotest.(check bool) "run ends" true (Async.status finished = Async.Done ()) );
    ( "a sub before hello closes 4400",
      fun () ->
        let f, _ = start () in
        push f (sub 1 "count" {|"abc"|});
        Alcotest.(check (option int)) "code" (Some 4400) f.closed );
    ( "bad JSON closes 4400",
      fun () ->
        let f, _ = open_ () in
        push f "{";
        Alcotest.(check (option int)) "code" (Some 4400) f.closed );
    ( "pipelined hello and sub work, and hello carries a fresh token",
      fun () ->
        let f = fake () in
        f.inbox <- [ Some hello; Some (sub 1 "count" {|"abcd"|}) ];
        let verify, accept, _ = Async.make () in
        let _ = Server.Testing.live_run ~sleep (Server.Testing.context ~session:("pipe") ()) ~verify_csrf:(fun _ -> verify) ~token:(fun () -> "T2") (connection f) in
        Alcotest.(check (list string)) "nothing before the check" [] f.out;
        accept true;
        Alcotest.(check (list string)) "messages" [ "hello"; "state" ] (kinds f);
        Alcotest.(check (option string)) "token" (Some {|"T2"|})
          (Option.map Json.to_string (field "csrf" (List.hd f.out)));
        check_states "state" [ (1, "4") ] f;
        hang_up f );
  ]

let sub_cases =
  [
    ( "subscribe, publish to two sockets, unsub, reload after the last unsub",
      fun () ->
        loads := [];
        let a, _ = open_ () and b, _ = open_ () in
        push a (sub 1 "count" {|"pub"|});
        push b (sub 7 "count" {|"pub"|});
        check_states "loaded" [ (1, "3") ] a;
        check_states "current state" [ (7, "3") ] b;
        Alcotest.(check (list string)) "one load" [ "pub" ] !loads;
        a.out <- [];
        b.out <- [];
        Live.publish count "pub" 42;
        check_states "a" [ (1, "42") ] a;
        check_states "b" [ (7, "42") ] b;
        Alcotest.(check (list int)) "same seq" (seqs a) (seqs b);
        push a {|{"t":"unsub","id":1}|};
        a.out <- [];
        b.out <- [];
        Live.publish count "pub" 43;
        check_states "a stopped" [] a;
        check_states "b still" [ (7, "43") ] b;
        push b {|{"t":"unsub","id":7}|};
        Live.publish count "pub" 44;
        push a (sub 2 "count" {|"pub"|});
        Alcotest.(check (list string)) "loaded again" [ "pub"; "pub" ] !loads;
        check_states "fresh load" [ (2, "3") ] a;
        hang_up a;
        hang_up b );
    ( "a publish during a pending load wins",
      fun () ->
        let a, _ = open_ () in
        push a (sub 1 "count" {|"slow1"|});
        check_states "nothing yet" [] a;
        Live.publish count "slow1" 99;
        let _, resolve, _ = gate "slow1" in
        resolve 5;
        check_states "published only" [ (1, "99") ] a;
        hang_up a );
    ( "allow, unknown topic, bad key, rejected and raising loaders",
      fun () ->
        logged := [];
        let a, _ = open_ ~session:"owner" () in
        push a (sub 1 "private" {|"other"|});
        push a (sub 2 "private" {|"owner"|});
        push a (sub 3 "nothing" {|"x"|});
        push a (sub 4 "count" "12");
        push a (sub 5 "count" {|"nope"|});
        push a (sub 6 "count" {|"boom"|});
        Alcotest.(check (list string)) "errors"
          [ "forbidden"; "unknown_topic nothing"; "bad_key expected string, got 12"; "rejected Not yours"; "server" ]
          (errors a);
        check_states "allowed" [ (2, "1") ] a;
        Alcotest.(check bool) "logged" true (List.exists (fun m -> Astring_like.contains m "secret boom") !logged);
        Alcotest.(check bool) "not sent" false (List.exists (fun m -> Astring_like.contains m "secret") a.out);
        hang_up a );
    ( "a blocked send keeps one waiting state, the last",
      fun () ->
        let a, _ = open_ () in
        push a (sub 1 "count" {|"blk"|});
        a.out <- [];
        let g, release, _ = Async.make () in
        a.gate <- Some g;
        Live.publish count "blk" 1;
        Live.publish count "blk" 2;
        Live.publish count "blk" 3;
        a.gate <- None;
        release ();
        check_states "first, then the last" [ (1, "1"); (1, "3") ] a;
        hang_up a );
    ( "limits: 64 KiB + 1 closes 1009, 65 subscriptions give limit",
      fun () ->
        let a, _ = open_ () in
        push a (String.make 65_537 ' ');
        Alcotest.(check (option int)) "1009" (Some 1009) a.closed;
        let b, _ = open_ () in
        for i = 1 to 65 do
          push b (sub i "count" (Printf.sprintf {|"k%d"|} i))
        done;
        Alcotest.(check (list string)) "limit" [ "limit at most 64 subscriptions" ] (errors b);
        hang_up b );
    ( "seq never goes down across entry removal",
      fun () ->
        let a, _ = open_ () in
        push a (sub 1 "count" {|"seq"|});
        Live.publish count "seq" 1;
        push a {|{"t":"unsub","id":1}|};
        push a (sub 2 "count" {|"seq"|});
        let s = seqs a in
        Alcotest.(check bool) "increasing" true (List.sort compare s = s && List.length s = 3);
        hang_up a );
    ( "a closed connection leaves no subscriber",
      fun () ->
        loads := [];
        let a, finished = open_ () in
        push a (sub 1 "count" {|"gone"|});
        hang_up a;
        Alcotest.(check bool) "run ends" true (Async.status finished = Async.Done ());
        a.out <- [];
        Live.publish count "gone" 9;
        Alcotest.(check (list string)) "nothing sent" [] a.out;
        let b, _ = open_ () in
        push b (sub 1 "count" {|"gone"|});
        Alcotest.(check (list string)) "loaded again" [ "gone"; "gone" ] !loads;
        hang_up b );
    ( "no message for 60 s closes 4408",
      fun () ->
        sleeps := [];
        let a, _ = open_ () in
        let early = !sleeps in
        push a {|{"t":"ping"}|};
        List.iter (fun w -> w ()) early;
        Alcotest.(check (option int)) "a later message keeps it open" None a.closed;
        Alcotest.(check (list string)) "pong" [ "pong" ] (kinds a);
        List.iter (fun w -> w ()) !sleeps;
        Alcotest.(check (option int)) "closed" (Some 4408) a.closed );
  ]

let sync_cases =
  [
    ( "synced comes after the latest state",
      fun () ->
        let a, _ = open_ () in
        push a (sub 1 "count" {|"sync"|});
        let g, release, _ = Async.make () in
        a.gate <- Some g;
        Live.publish count "sync" 7;
        Live.publish count "sync" 8;
        push a {|{"t":"sync","id":1,"ref":3}|};
        a.gate <- None;
        release ();
        Alcotest.(check (list string)) "order" [ "state"; "state"; "state"; "synced" ] (kinds a);
        check_states "states" [ (1, "4"); (1, "7"); (1, "8") ] a;
        hang_up a );
    ( "a sync while the subscription loads waits for its first state",
      fun () ->
        let a, _ = open_ () in
        push a (sub 1 "count" {|"slow2"|});
        push a {|{"t":"sync","id":1,"ref":1}|};
        Alcotest.(check (list string)) "nothing yet" [] (kinds a);
        let _, resolve, _ = gate "slow2" in
        resolve 2;
        Alcotest.(check (list string)) "state then synced" [ "state"; "synced" ] (kinds a);
        hang_up a );
    ( "a sync for an ended subscription is answered at once",
      fun () ->
        let a, _ = open_ () in
        push a {|{"t":"sync","id":9,"ref":1}|};
        Alcotest.(check (list string)) "synced" [ "synced" ] (kinds a);
        hang_up a );
  ]


let pair : (int * int) Codec.t =
  Codec.make
    ~encode:(fun (a, b) -> `Assoc [ ("a", `Int a); ("b", `Int b) ])
    ~decode:(function
      | `Assoc f -> (
          match (List.assoc_opt "a" f, List.assoc_opt "b" f) with
          | Some (`Int a), Some (`Int b) -> Ok (a, b)
          | _ -> Error "pair")
      | _ -> Error "pair")

let pairs = Topic.declare ~name:"pairs" ~key:pair ~state:Codec.int
let () = Live.serve pairs (fun (a, b) -> Async.return (a + b))
let allowed = ref true
let guarded_topic = Topic.declare ~name:"guarded" ~key:Codec.string ~state:Codec.int
let () = Live.serve ~allow:(fun _ _ -> !allowed) guarded_topic (fun _ -> Async.return 0)

let review_cases =
  [
    ( "a slow socket closes 1008 when its queue of replies is full",
      fun () ->
        let a, _ = open_ () in
        let g, _, _ = Async.make () in
        a.gate <- Some g;
        for _ = 1 to 300 do
          push a {|{"t":"ping"}|}
        done;
        Alcotest.(check (option int)) "1008" (Some 1008) a.closed );
    ( "syncs before the first state keep only the latest ref",
      fun () ->
        let a, _ = open_ () in
        push a (sub 1 "count" {|"slow3"|});
        push a {|{"t":"sync","id":1,"ref":1}|};
        push a {|{"t":"sync","id":1,"ref":5}|};
        push a {|{"t":"sync","id":1,"ref":3}|};
        let _, resolve, _ = gate "slow3" in
        resolve 1;
        Alcotest.(check (list string)) "one synced" [ "state"; "synced" ] (kinds a);
        Alcotest.(check (option string)) "latest ref" (Some "5")
          (Option.map Json.to_string (field "ref" (List.nth a.out 1)));
        hang_up a );
    ( "a socket that never sends closes after 10 s",
      fun () ->
        sleeps := [];
        let a, _ = start () in
        Alcotest.(check int) "one timer" 1 (List.length !sleeps);
        List.iter (fun w -> w ()) !sleeps;
        Alcotest.(check (option int)) "4408" (Some 4408) a.closed );
    ( "one deadline per connection",
      fun () ->
        sleeps := [];
        let a, _ = open_ () in
        for _ = 1 to 5 do
          push a {|{"t":"ping"}|}
        done;
        Alcotest.(check int) "one timer" 1 (List.length !sleeps);
        hang_up a );
    ( "connection limits per session and in total close 1013",
      fun () ->
        let node = Live.node ~per_session:2 ~total:1_000_000 () in
        let a, _ = open_ ~node ~session:"limited" () in
        let b, _ = open_ ~node ~session:"limited" () in
        let c, _ = open_ ~node ~session:"limited" () in
        let d, _ = open_ ~node ~session:"another" () in
        let x, _ = open_ ~session:"limited" () in
        Alcotest.(check (list (option int))) "third of a session" [ None; None; Some 1013; None; None ]
          [ a.closed; b.closed; c.closed; d.closed; x.closed ];
        List.iter hang_up [ a; b; d; x ];
        let node = Live.node ~total:1 () in
        let e, _ = open_ ~node () in
        let f, _ = open_ ~node () in
        Alcotest.(check (option int)) "over the total" (Some 1013) f.closed;
        hang_up e );
    ( "a failed send ends the connection and its subscriptions",
      fun () ->
        loads := [];
        let a, finished = open_ () in
        push a (sub 1 "count" {|"cut"|});
        a.broken <- true;
        Live.publish count "cut" 1;
        Alcotest.(check bool) "run ends" true (Async.status finished = Async.Done ());
        Alcotest.(check int) "closed once" 1 a.closes;
        let b, _ = open_ () in
        push b (sub 1 "count" {|"cut"|});
        Alcotest.(check (list string)) "no stale subscriber: loaded again" [ "cut"; "cut" ] !loads;
        hang_up b );
    ( "the entry of a key does not depend on the client's JSON field order",
      fun () ->
        let a, _ = open_ () in
        push a (sub 1 "pairs" {|{"b":2,"a":1}|});
        a.out <- [];
        Live.publish pairs (1, 2) 30;
        check_states "published to the canonical key" [ (1, "30") ] a;
        hang_up a );
    ( "allow runs again on each new connection",
      fun () ->
        allowed := true;
        let a, _ = open_ () in
        push a (sub 1 "guarded" {|"k"|});
        hang_up a;
        allowed := false;
        let b, _ = open_ () in
        push b (sub 1 "guarded" {|"k"|});
        allowed := true;
        Alcotest.(check (list string)) "first allowed" [] (errors a);
        Alcotest.(check (list string)) "then forbidden" [ "forbidden" ] (errors b);
        hang_up b );
    ( "revoke closes the matching connections with 4401",
      fun () ->
        let a, _ = open_ ~session:"leaving" () in
        let b, _ = open_ ~session:"staying" () in
        push a (sub 1 "count" {|"rev"|});
        push b (sub 1 "count" {|"rev"|});
        Live.revoke (fun p -> Server.Context.session p = Some "leaving");
        a.out <- [];
        b.out <- [];
        Live.publish count "rev" 9;
        Alcotest.(check (option int)) "revoked" (Some 4401) a.closed;
        Alcotest.(check (option int)) "kept" None b.closed;
        check_states "nothing to the revoked" [] a;
        check_states "the other gets it" [ (1, "9") ] b;
        hang_up b );
    ( "the socket is closed at most once, never after the client closed it",
      fun () ->
        let a, _ = open_ () in
        hang_up a;
        Alcotest.(check int) "client close: none" 0 a.closes;
        let b = fake () in
        b.inbox <- [ Some hello ];
        let _ =
          Server.Testing.live_run ~sleep (Server.Testing.context ~session:("err") ())
            ~verify_csrf:(fun _ -> Async.return true) ~token:(fun () -> "t")
            (connection ~receive:(fun b () -> if b.inbox = [] then Async.failed "reset" else receive b ()) b)
        in
        Alcotest.(check int) "receive error: one" 1 b.closes;
        sleeps := [];
        let c, _ = open_ () in
        Live.revoke (fun _ -> true);
        List.iter (fun w -> w ()) !sleeps;
        push c (String.make 70_000 ' ');
        Alcotest.(check int) "revoke, then the deadline: one" 1 c.closes );
  ]

let ssr_cases =
  [
    ( "a server render embeds the state and one token",
      fun () ->
        let s = Private.session ~streaming:false ~islands_only:true in
        let asked = ref 0 in
        Private.set_csrf s (fun () -> incr asked; "tok");
        let view () =
          let a = Yuka.Live.use count (fun () -> "ssr") and b = Yuka.Live.use count (fun () -> "other") in
          let show t = match Yuka.Live.status t with Status.Ready { data; _ } -> string_of_int data | _ -> "?" in
          element "p" [] [ text (show a ^ "," ^ show b) ]
        in
        let html = Private.print s (fun () -> Private.node (runtime_island ~name:"Live" ~props:`Null view)) in
        let has part = Astring_like.contains html part in
        Alcotest.(check bool) "data" true (has "3,5");
        Alcotest.(check bool) "state answer" true (has {|data-yuka-answer="l:count &quot;ssr&quot;">{"ok":3}|});
        Alcotest.(check bool) "token" true (has {|data-yuka-answer="l:csrf">{"ok":"tok"}|});
        Alcotest.(check int) "asked once" 1 !asked );
    ( "a page with no live use asks no token",
      fun () ->
        let s = Private.session ~streaming:false ~islands_only:true in
        let asked = ref 0 in
        Private.set_csrf s (fun () -> incr asked; "tok");
        let html = Private.print s (fun () -> Private.node (runtime_island ~name:"Plain" ~props:`Null (fun () -> text "x"))) in
        Alcotest.(check bool) "no token" false (Astring_like.contains html "l:csrf");
        Alcotest.(check int) "not asked" 0 !asked );
  ]

let shared = ref 0
let shared_loads : string list ref = ref []
let shared_gates : (int -> unit) list ref = ref []
let slow_shared = ref false
let shared_topic = Topic.declare ~name:"shared" ~key:Codec.string ~state:Codec.int

let () =
  Live.serve shared_topic (fun key ->
      shared_loads := key :: !shared_loads;
      if !slow_shared then begin
        let a, resolve, _ = Async.make () in
        shared_gates := !shared_gates @ [ resolve ];
        a
      end
      else Async.return !shared)

let open_on node =
  let f = fake () in
  let _ =
    Server.Testing.live_run ~node ~sleep (Server.Testing.context ~session:(fresh_session ()) ())
      ~verify_csrf:(fun t -> Async.return (t = "good"))
      ~token:(fun () -> "next")
      (connection f)
  in
  push f hello;
  f.out <- [];
  f

let two_nodes () =
  let m = Live.memory () in
  let a = Live.node () and b = Live.node () in
  ignore (Live.use_bus ~node:a ~name:"A" (Live.memory_bus m));
  ignore (Live.use_bus ~node:b ~name:"B" (Live.memory_bus m));
  (m, a, b)

let queued_bus () =
  let listeners = ref [] and queue = ref [] in
  let bus =
    Live.bus
      ~send:(fun text ->
        queue := !queue @ [ text ];
        Async.return ())
      ~listen:(fun l ->
        listeners := !listeners @ [ l ];
        Async.return ())
      ~on_restart:(fun _ -> ())
      ~close:(fun () -> Async.return ())
  in
  let deliver () =
    let q = !queue in
    queue := [];
    List.iter (fun t -> List.iter (fun l -> l t) !listeners) q
  in
  (bus, deliver)

let reset_shared () =
  shared := 0;
  shared_loads := [];
  shared_gates := [];
  slow_shared := false

let node_cases =
  [
    ( "two instances do not share entries",
      fun () ->
        reset_shared ();
        let a = Live.node () and b = Live.node () in
        let fa = open_on a and fb = open_on b in
        shared := 1;
        push fa (sub 1 "shared" {|"k"|});
        shared := 2;
        push fb (sub 1 "shared" {|"k"|});
        Live.publish ~node:a shared_topic "k" 9;
        check_states "a gets its publish" [ (1, "1"); (1, "9") ] fa;
        check_states "b, no bus: only its own load" [ (1, "2") ] fb );
    ( "a publish on A reaches a subscriber on B, which loads the key",
      fun () ->
        reset_shared ();
        let _, a, b = two_nodes () in
        let fb = open_on b in
        push fb (sub 3 "shared" {|"k"|});
        check_states "first state" [ (3, "0") ] fb;
        shared := 5;
        Live.publish ~node:a shared_topic "k" 5;
        check_states "B loaded again" [ (3, "0"); (3, "5") ] fb;
        Alcotest.(check (list string)) "two loads on B, none on A" [ "k"; "k" ] !shared_loads );
    ( "a node with no subscriber for the key does not load",
      fun () ->
        reset_shared ();
        let _, a, b = two_nodes () in
        let fb = open_on b in
        push fb (sub 3 "shared" {|"other"|});
        shared_loads := [];
        Live.publish ~node:a shared_topic "k" 5;
        Live.changed ~node:a shared_topic "k";
        Alcotest.(check (list string)) "no load" [] !shared_loads );
    ( "notes during a load give exactly one more load",
      fun () ->
        reset_shared ();
        let _, a, b = two_nodes () in
        let fb = open_on b in
        push fb (sub 3 "shared" {|"k"|});
        slow_shared := true;
        shared_loads := [];
        for i = 1 to 10 do
          shared := i;
          Live.publish ~node:a shared_topic "k" i
        done;
        Alcotest.(check int) "one load running" 1 (List.length !shared_loads);
        (List.hd !shared_gates) 1;
        Alcotest.(check int) "one more load" 2 (List.length !shared_loads);
        (List.nth !shared_gates 1) 10;
        Alcotest.(check int) "no third load" 2 (List.length !shared_loads);
        check_states "B ends on the last value" [ (3, "0"); (3, "1"); (3, "10") ] fb );
    ( "a note from the node itself is ignored",
      fun () ->
        reset_shared ();
        let _, a, _ = two_nodes () in
        let fa = open_on a in
        push fa (sub 3 "shared" {|"k"|});
        shared_loads := [];
        Live.publish ~node:a shared_topic "k" 4;
        check_states "the publish only" [ (3, "0"); (3, "4") ] fa;
        Alcotest.(check (list string)) "no load" [] !shared_loads );
    ( "after the bus reconnects, every subscribed key loads again",
      fun () ->
        reset_shared ();
        let m, a, b = two_nodes () in
        let fb = open_on b in
        push fb (sub 3 "shared" {|"k"|});
        Server.Testing.memory_down m true;
        shared := 7;
        Live.publish ~node:a shared_topic "k" 7;
        check_states "the note is lost" [ (3, "0") ] fb;
        Server.Testing.memory_down m false;
        check_states "the current state after the restart" [ (3, "0"); (3, "7") ] fb );
    ( "Live.optimistic settles on B only after B loaded the change of A",
      fun () ->
        reset_shared ();
        let bus, deliver = queued_bus () in
        let a = Live.node () and b = Live.node () in
        ignore (Live.use_bus ~node:a ~name:"A" bus);
        ignore (Live.use_bus ~node:b ~name:"B" bus);
        let fb = open_on b in
        push fb (sub 3 "shared" {|"k"|});
        fb.out <- [];
        slow_shared := true;
        shared := 8;
        Live.publish ~node:a shared_topic "k" 8;
        let n, p = Option.get (Server.Testing.live_mark ~node:a ()) in
        Alcotest.(check (pair string int)) "mark" ("A", 1) (n, p);
        push fb (Printf.sprintf {|{"t":"sync","id":3,"ref":1,"after":[["%s",%d]]}|} n p);
        Alcotest.(check (list string)) "no synced before the note" [] (kinds fb);
        deliver ();
        Alcotest.(check (list string)) "no synced while B loads" [] (kinds fb);
        (List.hd !shared_gates) 8;
        Alcotest.(check (list string)) "the new state, then synced" [ "state"; "synced" ] (kinds fb);
        check_states "state" [ (3, "8") ] fb );
    ( "a sync waits 5 s at most for a lost note",
      fun () ->
        reset_shared ();
        let bus, _ = queued_bus () in
        let b = Live.node () in
        ignore (Live.use_bus ~node:b ~name:"B" bus);
        let fb = open_on b in
        push fb (sub 3 "shared" {|"k"|});
        fb.out <- [];
        sleeps := [];
        push fb {|{"t":"sync","id":3,"ref":2,"after":[["A",4]]}|};
        Alcotest.(check (list string)) "waits" [] (kinds fb);
        List.iter (fun w -> w ()) !sleeps;
        Alcotest.(check (list string)) "synced after the bound" [ "synced" ] (kinds fb) );
    ( "revoke stays on its node",
      fun () ->
        let _, a, b = two_nodes () in
        let fa = open_on a and fb = open_on b in
        Live.revoke ~node:a (fun _ -> true);
        Alcotest.(check (option int)) "A closed" (Some 4401) fa.closed;
        Alcotest.(check (option int)) "B open" None fb.closed );
    ( "use_bus twice, and an empty node name, are refused",
      fun () ->
        let _, a, _ = two_nodes () in
        Alcotest.check_raises "twice" (Invalid_argument "Yuka.Server.Live.use_bus: this node already has a bus")
          (fun () -> ignore (Live.use_bus ~node:a ~name:"A" (Live.memory_bus (Live.memory ()))));
        Alcotest.check_raises "empty" (Invalid_argument "Yuka.Server.Live.use_bus: the node name is empty")
          (fun () -> ignore (Live.use_bus ~node:(Live.node ()) ~name:"" (Live.memory_bus (Live.memory ())))) );
    ( "a key too long for the bus is not sent and is logged",
      fun () ->
        reset_shared ();
        logged := [];
        let _, a, _ = two_nodes () in
        Live.publish ~node:a shared_topic (String.make 8000 'x') 1;
        Alcotest.(check (option (pair string int))) "no note counted" (Some ("A", 0)) (Server.Testing.live_mark ~node:a ());
        Alcotest.(check bool) "logged" true
          (List.exists (fun m -> Astring_like.contains m "too long for the bus") !logged) );
  ]

let action_mark_cases =
  [
    ( "an action answer carries the mark of the node",
      fun () ->
        let echo = Action.mutation ~name:"mark-echo" ~input:Codec.int ~output:Codec.int in
        Server.Action.make echo (fun _ n ->
            Live.publish shared_topic "m" n;
            Async.return n);
        let header = function
          | "origin" -> Some "https://x.test"
          | "host" -> Some "x.test"
          | "content-type" -> Some "application/json"
          | _ -> None
        in
        let before = Private.handle_action ~name:"mark-echo" ~header ~body:"3" in
        Alcotest.(check (option (pair int string))) "no bus: no mark" (Some (200, {|{"ok":3}|}))
          (match Async.status before with Async.Done r -> Some r | _ -> None);
        ignore (Live.use_bus ~name:"main" (Live.memory_bus (Live.memory ())));
        let after = Private.handle_action ~name:"mark-echo" ~header ~body:"4" in
        Alcotest.(check (option (pair int string))) "mark" (Some (200, {|{"ok":4,"live":["main",1]}|}))
          (match Async.status after with Async.Done r -> Some r | _ -> None) );
  ]

let cases tests = List.map (fun (name, f) -> Alcotest.test_case name `Quick f) tests

let () =
  Alcotest.run "live"
    [
      ("hello", cases hello_cases);
      ("subscriptions", cases sub_cases);
      ("sync", cases sync_cases);
      ("server render", cases ssr_cases);
      ("review", cases review_cases);
      ("nodes", cases node_cases);
      ("action mark", cases action_mark_cases);
    ]
