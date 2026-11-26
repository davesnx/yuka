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
  check_count html "a line per process" (List.length Machine.laptop.programs) {|role="row" data-pid=|};
  check_count html "the selected host" 1 {|<a class="row selected" href="/?host=laptop" aria-current="page">|};
  check_count html "the clock of the first screen" 1 {|<b class="value">18:42:07</b>|};
  check_count html "the sorted column" 1 {|aria-sort="descending"|}

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
  check "hundredths" "1.05" (Machine.hundredths 105)

let () =
  Alcotest.run "top"
    [
      ("page", [ Alcotest.test_case "first host" `Quick first_host; Alcotest.test_case "other host" `Quick other_host ]);
      ("machine", [ Alcotest.test_case "simulation" `Quick simulation; Alcotest.test_case "text" `Quick text ]);
    ]
