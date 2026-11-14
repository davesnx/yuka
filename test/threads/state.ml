open Yuka

let shared = State.make 3
let shared_memo = State.memo (fun () -> State.get shared * 10)
let logged = Atomic.make 0
let effect_runs = Atomic.make 0
let inputs = 4

let words n = List.init n (fun j -> String.make (1 + ((n + j) mod 5)) (Char.chr (97 + (((n * 7) + j) mod 26))))
let server (e : _ element) : server element = Private.element (Private.node e)
let hole f = server (Private.element (Private.hole (fun () -> Private.node (f ()))))
let fails input = input mod 5 = 0

let page input () : server element =
  let name = State.make (Printf.sprintf "user-%d" input) in
  let count = State.make input in
  let items = State.make (words (3 + (input mod 4))) in
  let doubled = State.memo (fun () -> State.get count * 2) in
  let label =
    State.memo (fun () ->
        String.concat "," (State.get items) ^ "#" ^ State.get name ^ "+" ^ string_of_int (State.get shared_memo))
  in
  let summary = State.memo (fun () -> Printf.sprintf "%s=%d" (State.get label) (State.get doubled)) in
  Effect.before (fun () -> Atomic.incr effect_runs);
  Effect.after (fun () -> Atomic.incr effect_runs);
  element "section"
    [ attr "data-input" (string_of_int input) ]
    [
      element "h1" [] [ text (State.get name) ];
      hole (fun () -> text (State.get summary));
      hole (fun () -> int (State.get doubled));
      element "p" [] [ hole (fun () -> int (State.get doubled + State.get shared)) ];
      server (element "i" [ hole_attr "title" (fun () -> Some (State.get label)) ] [ text "t" ]);
      text (string_of_int (State.get shared_memo));
      Catch.make
        ~fallback:(fun ~error ~reset:_ -> element "em" [] [ text error ])
        ~children:(fun () ->
          let risky =
            State.memo (fun () -> if fails (State.get count) then failwith "bad input" else State.get count + State.get shared)
          in
          element "b" [] [ int (State.get risky) ])
        ();
      server
        (element "ul" []
           [ each ~key:Fun.id (fun () -> Array.of_list (State.get items)) (fun w -> element "li" [] [ text w ]) ]);
    ]

let render input = Server.to_string (page input)
let input k r = (k * inputs) + (r mod inputs)

let expected_html input =
  let w = words (3 + (input mod 4)) in
  let label = Printf.sprintf "%s#user-%d+30" (String.concat "," w) input in
  Printf.sprintf
    "<section data-input=\"%d\"><h1>user-%d</h1>%s=%d%d<p>%d</p><i title=\"%s\">t</i>30%s<ul>%s</ul></section>" input
    input label (2 * input) (2 * input)
    ((2 * input) + 3)
    label
    (if fails input then "<em>server error</em>" else Printf.sprintf "<b>%d</b>" (input + 3))
    (String.concat "" (List.map (Printf.sprintf "<li>%s</li>") w))

let failed = ref false
let one_at_a_time = Mutex.create ()

let overlap = function
  | Failure m -> String.starts_with ~prefix:"Yuka.Server: two server renders overlapped" m
  | _ -> false

let check name ok detail =
  if not ok then begin
    failed := true;
    Printf.printf "FAIL %s: %s\n%!" name detail
  end

let run mode lock domains threads rounds =
  let workers = domains * threads in
  Atomic.set effect_runs 0;
  let expected = Array.init (workers * inputs) render in
  Array.iteri (fun i html -> check (Printf.sprintf "%s: one thread, input %d" mode i) (html = expected_html i) html) expected;
  check (mode ^ ": one thread, effects off") (Atomic.get effect_runs = 0) (string_of_int (Atomic.get effect_runs));
  Atomic.set logged 0;
  let wrong = Atomic.make 0 and raised = Atomic.make 0 and overlaps = Atomic.make 0 and sample = Atomic.make None in
  let render i = if lock then Mutex.protect one_at_a_time (fun () -> render i) else render i in
  let worker k =
    for r = 1 to rounds do
      let i = input k r in
      match render i with
      | html ->
          if html <> expected.(i) then begin
            Atomic.incr wrong;
            ignore (Atomic.compare_and_set sample None (Some (Printf.sprintf "input %d: %s" i html)))
          end
      | exception e when overlap e && not lock -> Atomic.incr overlaps
      | exception e ->
          Atomic.incr raised;
          ignore (Atomic.compare_and_set sample None (Some (Printexc.to_string e)))
    done
  in
  let threads_of first = List.iter Thread.join (List.init threads (fun t -> Thread.create worker (first + t))) in
  List.iter Domain.join (List.init domains (fun d -> Domain.spawn (fun () -> threads_of (d * threads))));
  let renders = workers * rounds in
  let failing = ref 0 in
  for k = 0 to workers - 1 do
    for r = 1 to rounds do
      if fails (input k r) then incr failing
    done
  done;
  check (mode ^ ": HTML") (Atomic.get wrong = 0) (Printf.sprintf "%d of %d renders" (Atomic.get wrong) renders);
  check (mode ^ ": exceptions") (Atomic.get raised = 0) (Printf.sprintf "%d of %d renders" (Atomic.get raised) renders);
  Option.iter (Printf.printf "  first: %s\n") (Atomic.get sample);
  if lock then
    check (mode ^ ": one log per caught memo failure") (Atomic.get logged = !failing)
      (Printf.sprintf "%d logs for %d failing renders" (Atomic.get logged) !failing);
  Printf.printf "%s: %d renders with States and memos on %d domain(s) x %d thread(s), %d reported an overlap\n" mode renders
    domains threads (Atomic.get overlaps)

let () =
  Server.Testing.set_log (fun _ _ -> Atomic.incr logged);
  (match Array.to_list Sys.argv with
  | [ _; mode; lock; d; t; r ] -> run mode (bool_of_string lock) (int_of_string d) (int_of_string t) (int_of_string r)
  | _ ->
      run "threads" true 1 16 10_000;
      run "domains" true 4 4 5_000;
      run "threads, no lock" false 1 16 10_000;
      run "domains, no lock" false 4 4 1_000;
      check "after the overlaps: server_rendering" (not !Private.server_rendering) "true";
      check "after the overlaps: a render" (render 1 = expected_html 1) (render 1));
  if !failed then exit 1
