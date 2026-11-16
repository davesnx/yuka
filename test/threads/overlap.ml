open Yuka

let gate = Mutex.create ()
let cond = Condition.create ()
let step = ref 0
let wait n = Mutex.protect gate (fun () -> while !step < n do Condition.wait cond gate done)
let go n = Mutex.protect gate (fun () -> step := n; Condition.broadcast cond)
let hole f : server element = Private.element (Private.hole (fun () -> Private.node (f ())))
let failed = ref false

let check name ok detail =
  if not ok then begin
    failed := true;
    Printf.printf "FAIL %s: %s\n%!" name detail
  end

let outcome f = match f () with html -> Ok html | exception e -> Error e

let overlapped = function
  | Error (Failure m) -> String.starts_with ~prefix:"Yuka.Server: two server renders overlapped" m
  | _ -> false

let show = function Ok html -> "returned " ^ html | Error e -> "raised " ^ Printexc.to_string e

let in_parallel f g =
  step := 0;
  let x = ref (Ok "") and y = ref (Ok "") in
  let tf = Thread.create (fun () -> x := f ()) () in
  let tg = Thread.create (fun () -> y := g ()) () in
  Thread.join tf;
  Thread.join tg;
  (!x, !y)

let in_domains f g =
  step := 0;
  let df = Domain.spawn f and dg = Domain.spawn g in
  let x = Domain.join df in
  (x, Domain.join dg)

let page () = element "p" [] [ text "B"; hole (fun () -> text "b") ]
let page_html = Server.to_string page

let clean name =
  check (name ^ ": server_rendering after") (not (Private.server_rendering ())) "true";
  let probe = Yuka.State.make 0 in
  ignore (Yuka.State.get probe);
  check (name ^ ": a top-level State.get is not tracked") (not (Private.has_readers probe)) "tracked";
  ignore (Yuka.State.memo (fun () -> 0));
  check (name ^ ": a top-level memo has no owner") (Private.owner_size () = 0) (string_of_int (Private.owner_size ()));
  let runs = ref 0 in
  let (), dispose = owner (fun () -> Effect.before (fun () -> incr runs)) in
  dispose ();
  check (name ^ ": Effect.before in owner runs") (!runs = 1) (string_of_int !runs);
  let html = outcome (fun () -> Server.to_string page) in
  check (name ^ ": a render after") (html = Ok page_html) (show html)

let interleaved () =
  let a, b =
    in_parallel
      (fun () ->
        let r = outcome (fun () -> Server.to_string (fun () -> element "p" [] [ hole (fun () -> go 1; wait 2; text "a") ])) in
        go 3;
        clean "interleaved, worker A";
        r)
      (fun () ->
        wait 1;
        outcome (fun () -> Server.to_string (fun () -> element "p" [] [ hole (fun () -> go 2; wait 3; text "b") ])))
  in
  check "interleaved: A" (a = Ok "<p>a</p>") (show a);
  check "interleaved: B" (b = Ok "<p>b</p>") (show b);
  clean "interleaved"

let listener () =
  let a, m =
    in_parallel
      (fun () ->
        let r = outcome (fun () -> Server.to_string (fun () -> element "p" [] [ hole (fun () -> go 1; wait 2; text "a") ])) in
        go 3;
        clean "memo on another thread, render worker";
        r)
      (fun () ->
        wait 1;
        let v = Yuka.State.get (Yuka.State.memo (fun () -> go 2; wait 3; 7)) in
        Ok (string_of_int v))
  in
  check "memo on another thread: the render" (a = Ok "<p>a</p>") (show a);
  check "memo on another thread: the memo" (m = Ok "7") (show m);
  clean "memo on another thread"

let owner_cursor () =
  let a, o =
    in_parallel
      (fun () ->
        wait 1;
        let r = outcome (fun () -> Server.to_string (fun () -> element "p" [] [ hole (fun () -> go 2; wait 3; text "a") ])) in
        clean "owner on another thread, render worker";
        r)
      (fun () ->
        let (), dispose = owner (fun () -> go 1; wait 2) in
        dispose ();
        go 3;
        Ok "")
  in
  check "owner on another thread: the render" (a = Ok "<p>a</p>") (show a);
  check "owner on another thread: the owner" (o = Ok "") (show o);
  clean "owner on another thread"

let domains_interleaved () =
  let a, b =
    in_domains
      (fun () ->
        let r = outcome (fun () -> Server.to_string (fun () -> element "p" [] [ hole (fun () -> go 1; wait 2; text "a") ])) in
        go 3;
        r)
      (fun () ->
        wait 1;
        outcome (fun () -> Server.to_string (fun () -> element "p" [] [ hole (fun () -> go 2; wait 3; text "b") ])))
  in
  check "interleaved on two domains: A" (a = Ok "<p>a</p>") (show a);
  check "interleaved on two domains: B" (b = Ok "<p>b</p>") (show b);
  clean "interleaved on two domains"

let domains_memo_and_owner () =
  let a, m =
    in_domains
      (fun () ->
        let r = outcome (fun () -> Server.to_string (fun () -> element "p" [] [ hole (fun () -> go 1; wait 2; text "a") ])) in
        go 3;
        r)
      (fun () ->
        wait 1;
        let (), dispose = owner (fun () -> ignore (Yuka.State.get (Yuka.State.memo (fun () -> go 2; wait 3; 7)))) in
        dispose ();
        Ok "")
  in
  check "memo and owner on another domain: the render" (a = Ok "<p>a</p>") (show a);
  check "memo and owner on another domain: the owner" (m = Ok "") (show m);
  clean "memo and owner on another domain"

let threads_in_a_domain () =
  let a, b =
    Domain.join
      (Domain.spawn (fun () ->
           in_parallel
             (fun () ->
               let r = outcome (fun () -> Server.to_string (fun () -> element "p" [] [ hole (fun () -> go 1; wait 2; text "a") ])) in
               go 3;
               r)
             (fun () ->
               wait 1;
               outcome (fun () -> Server.to_string (fun () -> element "p" [] [ hole (fun () -> go 2; wait 3; text "b") ])))))
  in
  check "interleaved threads in one other domain: A" (a = Ok "<p>a</p>") (show a);
  check "interleaved threads in one other domain: B" (b = Ok "<p>b</p>") (show b);
  clean "interleaved threads in one other domain"

let nested () =
  let inner = ref "" in
  let html =
    outcome (fun () ->
        Server.to_string (fun () ->
            element "div" []
              [
                hole (fun () ->
                    inner := Server.to_string page;
                    text !inner);
              ]))
  in
  check "nested: the inner render" (!inner = page_html) !inner;
  check "nested: the outer render" (Result.is_ok html) (show html);
  clean "nested"

let sequential () =
  let a, b =
    in_parallel
      (fun () ->
        let r = outcome (fun () -> Server.to_string page) in
        go 1;
        r)
      (fun () ->
        wait 1;
        outcome (fun () -> Server.to_string page))
  in
  check "one after the other on two threads: first" (a = Ok page_html) (show a);
  check "one after the other on two threads: second" (b = Ok page_html) (show b);
  clean "one after the other"

module Deep = Stdlib.Effect.Deep

type _ Stdlib.Effect.t += Suspend : unit Stdlib.Effect.t

let fiber f =
  let result = ref (Ok "") and paused = ref None in
  Deep.match_with f ()
    {
      retc = (fun r -> result := r);
      exnc = raise;
      effc =
        (fun (type b) (e : b Stdlib.Effect.t) ->
          match e with
          | Suspend -> Some (fun (k : (b, unit) Deep.continuation) -> paused := Some (k : (unit, unit) Deep.continuation))
          | _ -> None);
    };
  (result, paused)

let resume paused = Option.iter (fun k -> Deep.continue k ()) !paused

let suspending name () =
  let suspend () =
    Stdlib.Effect.perform Suspend;
    text name
  in
  outcome (fun () -> Server.to_string (fun () -> element "p" [] [ hole suspend ]))

let fibers_nested () =
  let a, paused = fiber (suspending "a") in
  let b = outcome (fun () -> Server.to_string page) in
  resume paused;
  check "a render while a fiber waits: the render" (b = Ok page_html) (show b);
  check "a render while a fiber waits: the fiber" (!a = Ok "<p>a</p>") (show !a);
  clean "a render while a fiber waits"

let fibers_interleaved () =
  let a, paused_a = fiber (suspending "a") in
  let b, paused_b = fiber (suspending "b") in
  resume paused_a;
  resume paused_b;
  check "interleaved fibers on one thread: A raises" (overlapped !a) (show !a);
  check "interleaved fibers on one thread: B raises" (overlapped !b) (show !b);
  clean "interleaved fibers on one thread"

let () =
  nested ();
  sequential ();
  interleaved ();
  listener ();
  owner_cursor ();
  domains_interleaved ();
  domains_memo_and_owner ();
  threads_in_a_domain ();
  fibers_nested ();
  fibers_interleaved ();
  if !failed then exit 1
  else
    print_endline
      "overlap: renders that interleave on threads and domains return their HTML; renders that interleave as fibers on \
       one thread raise"
