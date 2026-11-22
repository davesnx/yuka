open Yuka

type node

let () =
  [%mel.raw
    {|(function () {
  const { JSDOM } = require("jsdom");
  const dom = new JSDOM("<!doctype html><html><body></body></html>", { url: "http://localhost/" });
  globalThis.window = dom.window;
  globalThis.document = dom.window.document;
})()|}]

let dev : bool = [%mel.raw {|globalThis.__YUKA_DEV__ !== false|}]
let set_exit_code : int -> unit = [%mel.raw "function (c) { process.exitCode = c }"]

let take : unit -> string array =
  [%mel.raw
    {|function () { const e = globalThis.__errors; globalThis.__errors = []; return e.map(function (x) { return x.message + (x.stack ? " +stack" : " -stack"); }) }|}]

let container : unit -> node =
  [%mel.raw "function () { const c = document.createElement('div'); document.body.appendChild(c); return c }"]

let click : node -> unit = [%mel.raw "function (c) { c.querySelector('button').click() }"]

external as_container : node -> Client.container = "%identity"

let failures = ref 0

let message =
  "[yuka] State.get with nothing tracking it, during the render of a component.\n\
  \  It reads one time and never updates. Read it in markup, a memo or an effect,\n\
  \  or use State.peek for one read. +stack"

let check name ~fires =
  let errors = take () in
  let expected = if fires && dev then [| message |] else [||] in
  if errors <> expected then begin
    incr failures;
    print_endline
      ("FAIL " ^ name ^ "\n  expected: [" ^ String.concat " | " (Array.to_list expected) ^ "]\n  got:      ["
     ^ String.concat " | " (Array.to_list errors) ^ "]")
  end
  else print_endline ("ok " ^ name)

let render view =
  let c = container () in
  (c, Private.render (as_container c) view)

let () = check "module top level" ~fires:false

let () =
  let _, dispose = render Dev_check_cases.body_read in
  check "a read in a same-file helper called in a component body" ~fires:true;
  dispose ()

let () =
  let _, dispose = render Dev_check_cases.helper_read in
  check "a read in a helper of another module, called in a body" ~fires:true;
  dispose ()

let () =
  let _, dispose = render Dev_check_cases.body_read_in_hole in
  check "a component in a hole, not shown" ~fires:false;
  State.set Dev_check_cases.show true;
  check "a read in the body of a component that a hole shows" ~fires:true;
  State.set Dev_check_cases.show false;
  dispose ()

let () =
  let c, dispose = render Dev_check_cases.handler_read in
  check "render of a handler" ~fires:false;
  click c;
  check "a read in an event handler" ~fires:false;
  dispose ()

let () =
  let _, dispose = render Dev_check_cases.effect_read in
  State.set Dev_check_cases.count 2;
  check "a read in an effect and in on_change" ~fires:false;
  dispose ()

let () =
  let _, dispose = render Dev_check_cases.memo_read in
  State.set Dev_check_cases.count 3;
  check "a read in a memo" ~fires:false;
  dispose ()

let () =
  let _, dispose = render Dev_check_cases.hole_read in
  State.set Dev_check_cases.count 4;
  check "a read in markup" ~fires:false;
  dispose ()

let () =
  let _, dispose = render Dev_check_cases.peek_read in
  check "State.peek in a body" ~fires:false;
  dispose ()

let () =
  let _, dispose = render Dev_check_cases.untrack_read in
  check "State.untrack in a body" ~fires:false;
  dispose ()

let () =
  let _, dispose = render Dev_check_cases.each_cleanup_read in
  check "render of an each with an effect cleanup per row" ~fires:false;
  State.set Dev_check_cases.items [| 1 |];
  check "a read in the effect cleanup of a removed each row" ~fires:false;
  dispose ()

let () =
  ignore (State.get Dev_check_cases.count);
  check "a read outside a render" ~fires:false

let expect name messages =
  let errors = take () in
  let expected = if dev then Array.of_list messages else [||] in
  if errors <> expected then begin
    incr failures;
    print_endline
      ("FAIL " ^ name ^ "\n  expected: [" ^ String.concat " | " (Array.to_list expected) ^ "]\n  got:      ["
     ^ String.concat " | " (Array.to_list errors) ^ "]")
  end
  else print_endline ("ok " ^ name)

let () =
  let _, dispose = render Dev_check_cases.named_read in
  expect "a read of a named State in a component body"
    [
      "[yuka] State `named`: State.get with nothing tracking it, during the render of a component.\n\
      \  It reads one time and never updates. Read it in markup, a memo or an effect,\n\
      \  or use State.peek for one read. +stack";
    ];
  dispose ()

let () =
  let fail = State.make false in
  let (), dispose =
    with_owner (fun () ->
        owner_debug_name "Page";
        let (), _ =
          with_owner (fun () ->
              owner_debug_name "Room";
              Effect.after (effect_debug_name "boom" (fun () -> if State.get fail then raise Exit)))
        in
        ())
  in
  (try State.set fail true with Exit -> ());
  expect "a named effect that raises, in named owners" [ "[yuka] effect `boom` in `Page` > `Room` raised an exception +stack" ];
  dispose ()

let () =
  let fail = State.make false in
  let (), dispose =
    with_owner (fun () ->
        owner_debug_name "Page";
        Effect.after (effect_debug_name "boom" (fun () -> if State.get fail then raise Exit)))
  in
  (try State.set fail true with Exit -> ());
  expect "a named effect that raises, in a named owner" [ "[yuka] effect `boom` in `Page` raised an exception +stack" ];
  dispose ()

let () =
  let fail = State.make false in
  let (), dispose =
    with_owner (fun () ->
        let total = State.memo (fun () -> if State.get fail then raise Not_found else 1) |> State.debug_name "total" in
        Effect.after (fun () -> ignore (State.get total)))
  in
  (try State.set fail true with Not_found -> ());
  expect "a named memo that raises, one time for each compute"
    [ "[yuka] State `total` raised an exception +stack"; "[yuka] State `total` raised an exception +stack" ];
  dispose ()

let () =
  let go = State.make false and n = State.make 0 in
  let (), dispose =
    with_owner (fun () ->
        Effect.after (effect_debug_name "spin" (fun () -> if State.get go then State.set n (State.get n + 1))))
  in
  (try State.set go true with Failure _ -> ());
  expect "a named effect that keeps changing a State it reads"
    [ "[yuka] effect `spin` keeps changing a State it reads +stack" ];
  dispose ()

let () =
  let go = State.make false and n = State.make 0 in
  let (), dispose =
    with_owner (fun () ->
        let grow =
          State.memo (fun () ->
              let v = State.get n in
              if State.get go then State.set n (v + 1);
              v)
          |> State.debug_name "grow"
        in
        Effect.after (fun () -> ignore (State.get grow)))
  in
  (try State.set go true with Failure _ -> ());
  expect "a named memo that keeps changing a State it reads, one time for each compute"
    [
      "[yuka] State `grow` keeps changing a State it reads +stack";
      "[yuka] State `grow` keeps changing a State it reads +stack";
    ];
  dispose ()

let () =
  let fail = State.make false in
  let (), dispose = with_owner (fun () -> Effect.after (fun () -> if State.get fail then raise Exit)) in
  (try State.set fail true with Exit -> ());
  expect "an effect with no name that raises" [];
  dispose ()


let logs : unit -> string array =
  [%mel.raw
    {|function () { const l = globalThis.__logs; globalThis.__logs = []; return l.map(function (x) { return x.replace(/#\d+/g, "#N"); }) }|}]

let set_html : string -> unit = [%mel.raw "function (h) { document.body.innerHTML = h }"]

let expect_trace name lines =
  let got = logs () in
  let expected = if dev then Array.of_list lines else [||] in
  if got <> expected then begin
    incr failures;
    print_endline
      ("FAIL " ^ name ^ "\n  expected: [" ^ String.concat " | " (Array.to_list expected) ^ "]\n  got:      ["
     ^ String.concat " | " (Array.to_list got) ^ "]")
  end
  else print_endline ("ok " ^ name)

let () =
  let count = State.make 0 |> State.debug_name "count" in
  Dev.trace true;
  let (), dispose =
    with_owner (fun () ->
        owner_debug_name "Page";
        Effect.after (effect_debug_name "save" (fun () -> ignore (State.get count))))
  in
  State.set count 1;
  State.set count 2;
  Dev.trace false;
  expect_trace "the trace of a named effect and the State write that made it run"
    [
      "[yuka] effect `save` in `Page` runs for the first time";
      "[yuka] effect `save` in `Page` runs: State `count` changed";
      "[yuka] effect `save` in `Page` runs: State `count` changed";
    ];
  dispose ()

let () =
  let a = State.make 0 and b = State.make 0 in
  Dev.trace true;
  let (), dispose = with_owner (fun () -> Effect.after (fun () -> ignore (State.get a + State.get b))) in
  State.set b 1;
  batch (fun () ->
      State.set a 1;
      State.set b 2);
  Dev.trace false;
  expect_trace "the trace of an effect and a State with no name, and of a batch"
    [
      "[yuka] effect #N runs for the first time";
      "[yuka] effect #N runs: State #N changed";
      "[yuka] effect #N runs: State #N changed";
    ];
  dispose ()

let () =
  let n = State.make 1 |> State.debug_name "n" in
  Dev.trace true;
  let (), dispose =
    with_owner (fun () ->
        let double = State.memo (fun () -> State.get n * 2) |> State.debug_name "double" in
        Effect.after (effect_debug_name "show" (fun () -> ignore (State.get double))))
  in
  State.set n 2;
  Dev.trace false;
  expect_trace "the trace of an effect that reads a memo gives the State written"
    [ "[yuka] effect `show` runs for the first time"; "[yuka] effect `show` runs: State `n` changed" ];
  dispose ()

let () =
  let n = State.make 0 in
  let (), dispose = with_owner (fun () -> Effect.after (fun () -> ignore (State.get n))) in
  State.set n 1;
  expect_trace "no trace when it is off" [];
  dispose ()

let () =
  let view () = element "p" [] [ text "hi" ] in
  set_html
    (Private.render_html (fun () ->
         Private.node (runtime_island ~name:"Hello" ~props:(Codec.encode Codec.int 0) view)));
  Dev.trace true;
  Yuka.render ~islands:(runtime_registry [ runtime_entry ~name:"Hello" (fun _ -> Ok view) ]) ~navigation:false ();
  Yuka.stop ();
  Dev.trace false;
  set_html "";
  expect_trace "the trace of an island start and stop"
    [ "[yuka] island Hello #i1 starts"; "[yuka] island Hello #i1 stops" ]

let panel : unit -> string array =
  [%mel.raw
    {|function () {
  var d = globalThis.__yuka_dev, r = [];
  if (!d) return r;
  d.islands().forEach(function (i) {
    r.push(i.name + " #" + i.id);
    i.states.forEach(function (x) { r.push("  " + (x.owner ? x.owner + " | " : "") + x.name + " = " + x.value) });
  });
  return r.map(function (x) { return x.replace(/#\d+/g, "#N") });
}|}]

let expect_panel name lines =
  let got = panel () in
  let expected = if dev then Array.of_list lines else [||] in
  if got <> expected then begin
    incr failures;
    print_endline
      ("FAIL " ^ name ^ "\n  expected: [" ^ String.concat " | " (Array.to_list expected) ^ "]\n  got:      ["
     ^ String.concat " | " (Array.to_list got) ^ "]")
  end
  else print_endline ("ok " ^ name)

type user = { name : string; tags : string list }

let counter : int State.t option ref = ref None

let () =
  let counter_view () =
    owner_debug_name "Counter";
    let count = State.make 1 |> State.debug_name "count" in
    counter := Some count;
    let double = State.memo (fun () -> State.get count * 2) |> State.debug_name "double" in
    ignore double;
    ignore (State.make { name = "ada"; tags = [ "a"; "b" ] });
    let (), _ =
      with_owner (fun () ->
          owner_debug_name "Row";
          ignore (State.make (Some true) |> State.debug_name "open"))
    in
    Effect.after (fun () -> ignore (State.make (State.get count) |> State.debug_name "seen"));
    element "p" [] [ text "count" ]
  in
  let hello_view () =
    ignore (State.make "hi" |> State.debug_name "greeting");
    element "p" [] [ text "hi" ]
  in
  let outside = State.make 0 |> State.debug_name "outside" in
  ignore outside;
  set_html
    (Private.render_html (fun () ->
         Private.node
           (fragment
              [
                runtime_island ~name:"Counter" ~props:(Codec.encode Codec.int 0) counter_view;
                runtime_island ~name:"Hello" ~props:(Codec.encode Codec.int 0) hello_view;
              ])));
  expect_panel "the panel data before the islands start" [];
  Yuka.render
    ~islands:
      (runtime_registry
         [
           runtime_entry ~name:"Counter" (fun _ -> Ok counter_view);
           runtime_entry ~name:"Hello" (fun _ -> Ok hello_view);
         ])
    ~navigation:false ();
  expect_panel "the panel data lists each island with its owners and States"
    [
      "Counter #i1";
      "  `Counter` | State `count` = 1";
      "  `Counter` | State `double` = 2";
      "  `Counter` | State #N = {name: \"ada\", tags: [\"a\", \"b\"]}";
      "  `Counter` > `Row` | State `open` = true";
      "  `Counter` | State `seen` = 1";
      "Hello #i2";
      "  State `greeting` = \"hi\"";
    ];
  (match !counter with Some c -> State.set c 5 | None -> ());
  expect_panel "the panel data shows the new values after a write"
    [
      "Counter #i1";
      "  `Counter` | State `count` = 5";
      "  `Counter` | State `double` = 10";
      "  `Counter` | State #N = {name: \"ada\", tags: [\"a\", \"b\"]}";
      "  `Counter` > `Row` | State `open` = true";
      "  `Counter` | State `seen` = 5";
      "Hello #i2";
      "  State `greeting` = \"hi\"";
    ];
  Yuka.stop ();
  set_html "";
  expect_panel "the panel data is empty after the islands stop" []

let () =
  if !failures > 0 then set_exit_code 1
  else print_endline (if dev then "dev check (dev build): ok" else "dev check (__YUKA_DEV__ = false): ok")
