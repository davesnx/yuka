open Yuka

let shared = State.make 3
let base = State.make 3
let shared_memo = State.memo (fun () -> State.get base * 10)
let theme : string Context.t = Context.make ~name:"theme" ()
let effect_runs = Atomic.make 0
let server (e : _ element) : server element = Private.element (Private.node e)
let hole f = server (Private.element (Private.hole (fun () -> Private.node (f ()))))
let fails input = input mod 5 = 0
let words n = List.init n (fun j -> String.make (1 + ((n + j) mod 5)) (Char.chr (97 + (((n * 7) + j) mod 26))))

let page input () : server element =
  let count = State.make input in
  let items = State.make (words (3 + (input mod 4))) in
  let doubled = State.memo (fun () -> (State.get count * 2) + State.get shared) in
  let label = State.memo (fun () -> String.concat "," (State.get items) ^ "+" ^ string_of_int (State.get shared_memo)) in
  Effect.before (fun () -> Atomic.incr effect_runs);
  Effect.after (fun () -> Atomic.incr effect_runs);
  State.set count (input + 1);
  element "section"
    [ attr "data-input" (string_of_int input) ]
    [
      hole (fun () -> text (State.get label));
      hole (fun () -> int (State.get doubled));
      Context.provide theme (Printf.sprintf "t%d" input) (fun () ->
          let shown = State.memo (fun () -> Option.value ~default:"none" (Context.get theme) ^ "!") in
          element "b" [] [ hole (fun () -> text (State.get shown)) ]);
      Catch.make
        ~fallback:(fun ~error ~reset:_ -> element "em" [] [ text error ])
        ~children:(fun () ->
          let risky = State.memo (fun () -> if fails input then failwith "bad input" else State.get count) in
          element "i" [] [ int (State.get risky) ])
        ();
      server (element "ul" [] [ each ~key:Fun.id (fun () -> Array.of_list (State.get items)) (fun w -> element "li" [] [ text w ]) ]);
    ]

let expected_html input =
  let w = words (3 + (input mod 4)) in
  Printf.sprintf
    "<section data-input=\"%d\">%s+30%d<b>t%d!</b>%s<ul>%s</ul></section>"
    input (String.concat "," w)
    ((2 * (input + 1)) + 3)
    input
    (if fails input then "<em>server error</em>" else Printf.sprintf "<i>%d</i>" (input + 1))
    (String.concat "" (List.map (Printf.sprintf "<li>%s</li>") w))

let failed = ref false

let check name ok detail =
  if not ok then begin
    failed := true;
    Printf.printf "FAIL %s: %s\n%!" name detail
  end

let scheduler_works () =
  let s = State.make 1 in
  let seen = ref [] in
  let (), dispose =
    owner (fun () ->
        let m = State.memo (fun () -> State.get s * 2) in
        Effect.before (fun () -> seen := State.get m :: !seen))
  in
  State.set s 2;
  let batched = ref 0 in
  batch (fun () ->
      State.set s 3;
      State.set s 4;
      batched := List.length !seen);
  dispose ();
  State.set s 5;
  let probe = State.make 0 in
  ignore (State.get probe);
  if !seen <> [ 8; 4; 2 ] then Error (String.concat "," (List.map string_of_int !seen))
  else if !batched <> 2 then Error "an effect ran inside a batch"
  else if Private.server_rendering () then Error "server_rendering is true"
  else if Private.owner_size () <> 0 then Error "an owner is left"
  else if Private.has_readers probe then Error "a top-level read is tracked"
  else Ok ()

let domains = 8
let rounds = 2_000
let inputs = 6

let () =
  Server.Testing.set_log (fun _ _ -> ());
  let expected = Array.init (domains * inputs) (fun i -> Server.to_string (page i)) in
  Array.iteri (fun i html -> check (Printf.sprintf "one domain, input %d" i) (html = expected_html i) html) expected;
  let wrong = Atomic.make 0 and raised = Atomic.make 0 and sample = Atomic.make None in
  let note x = ignore (Atomic.compare_and_set sample None (Some x)) in
  let worker k () =
    for r = 1 to rounds do
      let i = (k * inputs) + (r mod inputs) in
      match Server.to_string (page i) with
      | html ->
          if html <> expected.(i) then begin
            Atomic.incr wrong;
            note (Printf.sprintf "input %d: %s" i html)
          end
      | exception e ->
          Atomic.incr raised;
          note (Printexc.to_string e)
    done;
    scheduler_works ()
  in
  let reactive () =
    let total = ref 0 in
    for _ = 1 to rounds do
      match scheduler_works () with Ok () -> incr total | Error m -> note ("reactive domain: " ^ m)
    done;
    !total
  in
  let renderers = List.init domains (fun k -> Domain.spawn (worker k)) in
  let other = Domain.spawn reactive in
  let after = List.map Domain.join renderers in
  let reactive_ok = Domain.join other in
  let renders = domains * rounds in
  check "HTML" (Atomic.get wrong = 0) (Printf.sprintf "%d of %d renders" (Atomic.get wrong) renders);
  check "exceptions" (Atomic.get raised = 0) (Printf.sprintf "%d of %d renders" (Atomic.get raised) renders);
  check "effects during renders" (Atomic.get effect_runs = 0) (string_of_int (Atomic.get effect_runs));
  check "reactive work on another domain" (reactive_ok = rounds) (Printf.sprintf "%d of %d" reactive_ok rounds);
  List.iteri
    (fun k r -> check (Printf.sprintf "scheduler of domain %d after its renders" k) (r = Ok ()) (match r with Ok () -> "" | Error m -> m))
    after;
  check "scheduler of the main domain" (scheduler_works () = Ok ()) "error";
  check "module-level State has no readers" (not (Private.has_readers shared)) "readers";
  check "module-level memo has no readers" (not (Private.has_readers shared_memo)) "readers";
  check "a write to a module-level State raises"
    (match State.set shared 4 with () -> false | exception Invalid_argument _ -> true)
    "no exception";
  Option.iter (Printf.printf "  first: %s\n") (Atomic.get sample);
  if !failed then exit 1
  else
    Printf.printf "%d renders on %d domains with no lock, each its own HTML; schedulers work after\n" renders domains
