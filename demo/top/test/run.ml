open Top_demo_app
open Top_demo_shared

let config =
  Yuka.Server.config
    ~assets:
      (Result.get_ok
         (Yuka.Server.modules ~dir:"js" ~entry:"demo/top/client/main.js" ~manifest:"{}" ~packages:[] ~digest:""))
    ()

let handler = Yuka_dream.handler config Yuka_routes.app

let get target =
  let response = Dream.test handler (Dream.request ~target "") in
  (Dream.status_to_int (Dream.status response), Lwt_main.run (Dream.body response))

let count html needle =
  let n = String.length needle in
  let rec go i found =
    if i + n > String.length html then found else go (i + 1) (if String.sub html i n = needle then found + 1 else found)
  in
  go 0 0

let check_count html name expected needle = Alcotest.(check int) name expected (count html needle)

let first_host () =
  let status, html = get "/" in
  Alcotest.(check int) "status" 200 status;
  check_count html "the title" 1 "<title>top — laptop</title>";
  check_count html "the island" 1 {|data-name="Top_demo_shared.Monitor"|};
  check_count html "a line per process" (Array.length (Machine.start Machine.laptop).procs) {|role="row" data-pid=|};
  check_count html "the selected host" 1 {|<a class="row selected" href="/?host=laptop" aria-current="page">|};
  check_count html "the clock of the first screen" 1 {|<span class="clock">18:42:07</span>|};
  check_count html "the sorted column" 1 {|aria-sort="descending"|};
  check_count html "four boxes" 4 {|<section class="box |};
  check_count html "the full-screen window" 1 {|<div class="fullscreen">|};
  check_count html "no detail before a click" 0 {|role="dialog"|}

let other_host () =
  let _, html = get "/?host=build-01" in
  check_count html "the title" 1 "<title>top — build-01</title>";
  check_count html "the kernel" 1 "Linux 6.12.48-1-lts";
  let _, html = get "/?host=nope" in
  check_count html "an unknown host shows the laptop" 1 "<title>top — laptop</title>"

let sum f (t : Machine.t) = Array.fold_left (fun n p -> n + f p) 0 t.procs

let rec steps n t = if n = 0 then t else steps (n - 1) (Machine.step t)

let simulation () =
  List.iter
    (fun (host : Machine.host) ->
      let first = Machine.start host in
      Alcotest.(check bool) (host.name ^ ": start is the same each time") true (first = Machine.start host);
      let later = steps 60 first in
      Alcotest.(check int) (host.name ^ ": a minute later") (first.clock + 60) later.clock;
      Alcotest.(check bool) (host.name ^ ": the CPU time grows") true (sum (fun p -> p.time) later >= 0);
      let pct (cpu : Machine.cpu) = cpu.us + cpu.sy + cpu.ni + cpu.id + cpu.wa + cpu.hi + cpu.si in
      Alcotest.(check int) (host.name ^ ": the CPU split sums to 100%") 1000 (pct later.total);
      Alcotest.(check int) (host.name ^ ": a line per core") host.cores (Array.length later.cores);
      Alcotest.(check bool) (host.name ^ ": memory fits") true (later.used + later.cache <= host.mem);
      let pids = Array.to_list (Array.map (fun (p : Machine.proc) -> p.pid) later.procs) in
      Alcotest.(check int) (host.name ^ ": pids are unique") (List.length pids)
        (List.length (List.sort_uniq compare pids)))
    Machine.hosts;
  List.iter
    (fun (host : Machine.host) ->
      let hour = steps 3600 (Machine.start host) in
      let most = List.length host.programs + (3 * List.length host.short_lived) in
      Alcotest.(check bool) (host.name ^ ": short-lived processes end") true (Array.length hour.procs <= most))
    Machine.hosts;
  let first = Machine.start Machine.laptop in
  let zed = (Machine.sorted ~sort:Machine.Mem ~reverse:false first).(0) in
  Alcotest.(check string) "the largest process" "firefox" zed.command;
  let killed = Machine.kill first zed.pid in
  Alcotest.(check int) "kill takes one away" (Array.length first.procs - 1) (Array.length killed.procs)

let history () =
  List.iter
    (fun (host : Machine.host) ->
      let t = Machine.start host in
      Alcotest.(check int) (host.name ^ ": the clock of the host") host.clock t.clock;
      Alcotest.(check int) (host.name ^ ": the uptime of the host") host.boot t.uptime;
      Alcotest.(check int) (host.name ^ ": a full CPU graph") Machine.samples (Array.length t.history);
      Alcotest.(check bool) (host.name ^ ": the graph has values") true (Array.for_all (fun v -> v > 0) t.history);
      Alcotest.(check bool) (host.name ^ ": downloads") true (Array.for_all (fun v -> v > 0) t.rx);
      Array.iter
        (fun (p : Machine.proc) ->
          Alcotest.(check bool) "the %CPU of a process is kept" true
            (List.length p.cpu_history >= 1 && List.length p.cpu_history <= Machine.proc_samples);
          Alcotest.(check int) "the newest first" p.cpu (List.hd p.cpu_history))
        t.procs)
    Machine.hosts;
  let t = Machine.start Machine.build in
  let compilers = List.filter (fun (p : Machine.proc) -> p.left > 0) (Array.to_list t.procs) in
  let dune =
    List.find (fun (p : Machine.proc) -> Machine.starts_with "dune" p.command) (Array.to_list t.procs)
  in
  Alcotest.(check bool) "a compiler is a child of dune" true
    (List.for_all (fun (p : Machine.proc) -> p.ppid = dune.pid) compilers)

let graph () =
  let check = Alcotest.(check (list string)) in
  check "empty, then full" [ {js|⠀⣸|js}; {js|⠀⣿|js}; {js|⢀⣿|js} ] (Graph.lines ~height:3 ~top:120 [| 0; 1; 90; 120 |]);
  check "a value is at least one dot" [ {js|⢀|js} ] (Graph.lines ~height:1 ~top:1000 [| 0; 1 |]);
  check "an odd count fills the left column with 0" [ {js|⢸|js} ] (Graph.lines ~height:1 ~top:4 [| 4 |]);
  check "hanging" [ {js|⣿⠁|js}; {js|⣿⠀|js} ] (Graph.lines ~hang:true ~height:2 ~top:8 [| 8; 8; 1; 0 |])

let text () =
  let check = Alcotest.(check string) in
  check "clock" "08:05:03" (Machine.clock ((8 * 3600) + (5 * 60) + 3));
  check "uptime" "3 days,  5:12" (Machine.uptime ((3 * 86400) + (5 * 3600) + (12 * 60)));
  check "uptime under a day" " 0:42" (Machine.uptime (42 * 60));
  check "TIME+" "12:34.56" (Machine.time ((((12 * 60) + 34) * 100) + 56));
  check "TIME+ over 1000 minutes" "1234:05" (Machine.time ((((1234 * 60) + 5) * 100) + 99));
  check "a long user" "pgbounc+" (Machine.user "pgbouncer");
  check "KiB" "1183744" (Machine.kib 1_183_744);
  check "GiB" "34.6g" (Machine.kib 36_284_416);
  check "tenths" "0.4" (Machine.tenths 4);
  check "hundredths" "1.05" (Machine.hundredths 105);
  check "size in K" "512K" (Machine.size 512);
  check "size in M" "30.0M" (Machine.size 30_720);
  check "size in big M" "312M" (Machine.size 319_488);
  check "size in G" "1.6G" (Machine.size 1_734_656);
  check "rate" "1.5 MiB/s" (Machine.rate 1536);
  check "total" "53.9 TiB" (Machine.total_mib 56_520_000);
  check "program" "dune" (Machine.program_name "dune build -w @check");
  check "program of a path" "postgres" (Machine.program_name "/usr/lib/postgresql/17/bin/postgres -D x");
  check "program with a colon" "postgres" (Machine.program_name "postgres: walwriter");
  check "a kernel thread" "kworker/3:1-mm_percpu_wq" (Machine.program_name "kworker/3:1-mm_percpu_wq");
  let p = (Machine.start Machine.laptop).procs.(0) in
  Alcotest.(check bool) "filter by user" true (Machine.matches ~filter:"ROOT" p);
  Alcotest.(check bool) "filter by pid" true (Machine.matches ~filter:"1" p);
  Alcotest.(check bool) "filter out" false (Machine.matches ~filter:"firefox" p)

let () =
  Alcotest.run "top"
    [
      ("page", [ Alcotest.test_case "first host" `Quick first_host; Alcotest.test_case "other host" `Quick other_host ]);
      ( "machine",
        [
          Alcotest.test_case "simulation" `Quick simulation;
          Alcotest.test_case "history" `Quick history;
          Alcotest.test_case "graph" `Quick graph;
          Alcotest.test_case "text" `Quick text;
        ] );
    ]
