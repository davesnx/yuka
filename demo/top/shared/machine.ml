(* Fake machines for top: the programs of each host, and a step that moves the
   numbers as time goes. Nothing reads /proc; every number comes from [step].

   The numbers are integers (tenths of a percent, KiB, hundredths of a second)
   and the random numbers come from a generator on 31 bits, so the server and the
   browser, where an int has 32 bits, compute the same first screen. Each [draw] is
   in its own [let]: OCaml evaluates the parts of a tuple, a record or an application
   right to left, Melange left to right. *)

type program = {
  user : string;
  command : string;
  cpu : int;  (** The usual %CPU, in tenths of a percent of one core. *)
  burst : int;  (** How far %CPU can go above [cpu], in tenths. *)
  res : int;  (** Resident memory, in KiB. *)
  virt : int;  (** Virtual memory, in KiB. *)
  shr : int;  (** Shared memory, in KiB. *)
  nice : int;
  life : int;  (** For a short-lived program, its life in ticks; else 0. *)
}

type host = {
  name : string;
  user_name : string;  (** The user who runs top, who can kill only their own processes. *)
  kernel : string;
  cores : int;
  mem : int;  (** In tenths of a MiB. *)
  swap : int;  (** In tenths of a MiB. *)
  boot : int;  (** Seconds of uptime at the first screen. *)
  clock : int;  (** The clock of the first screen, in seconds after midnight. *)
  users : int;
  seed : int;
  programs : program list;
  short_lived : program list;  (** Started now and then, as the compilers of a build. *)
}

type proc = {
  pid : int;
  user : string;
  pr : int;
  ni : int;
  virt : int;
  res : int;
  shr : int;
  state : char;  (** [R]unning, [S]leeping, [I]dle (a kernel thread) or [D] (waiting for the disk). *)
  cpu : int;  (** Tenths of a percent of one core. *)
  mem : int;  (** Tenths of a percent of the memory. *)
  time : int;  (** CPU time, in hundredths of a second. *)
  command : string;
  left : int;  (** Ticks before a short-lived process ends; 0 for the others. *)
  base : int;  (** The usual %CPU of the program. *)
  burst : int;
}

type cpu = { us : int; sy : int; ni : int; id : int; wa : int; hi : int; si : int }

type t = {
  host : string;
  tick : int;
  clock : int;
  uptime : int;
  seed : int;
  next_pid : int;
  load : int * int * int;  (** Hundredths. *)
  total : cpu;  (** Tenths of a percent of all cores. *)
  cores : cpu array;
  used : int;  (** Tenths of a MiB. *)
  cache : int;
  swap_used : int;
  procs : proc array;
}

(* The delay between two screens, in seconds, as [top -d 1]. *)
let delay = 1

(* The linear congruential generator of C's [rand], kept to 31 bits: the products keep
   the same low bits on 63 and on 32 bits. *)
let next seed = ((seed * 1103515245) + 12345) land 0x7fffffff

let program ?(nice = 0) ?(burst = 0) ?(life = 0) ~user ~cpu ~res ~virt ~shr command =
  { user; command; cpu; burst; res; virt; shr; nice; life }

let kernel ?(cpu = 0) ?(burst = 0) command =
  program ~user:"root" ~cpu ~burst ~res:0 ~virt:0 ~shr:0 command

let laptop =
  let me = "yuka" in
  {
    name = "laptop";
    user_name = me;
    kernel = "Linux 6.17.8-arch1-1";
    cores = 8;
    mem = 319_584;
    swap = 81_920;
    boot = (3 * 86400) + (5 * 3600) + (12 * 60);
    clock = (18 * 3600) + (42 * 60) + 7;
    users = 2;
    seed = 42;
    programs =
      [
        program ~user:"root" ~cpu:0 ~res:14_208 ~virt:23_440 ~shr:10_112 "systemd";
        kernel "kthreadd";
        kernel ~cpu:2 ~burst:6 "rcu_preempt";
        kernel ~cpu:0 ~burst:4 "ksoftirqd/0";
        kernel ~cpu:1 ~burst:8 "kworker/u16:3-events_unbound";
        kernel ~cpu:0 ~burst:5 "kworker/3:1-mm_percpu_wq";
        program ~user:"root" ~cpu:0 ~burst:3 ~res:38_912 ~virt:91_844 ~shr:37_120 "systemd-journald";
        program ~user:"systemd+" ~cpu:0 ~res:13_440 ~virt:21_908 ~shr:11_008 "systemd-resolved";
        program ~user:"dbus" ~cpu:0 ~burst:2 ~res:6_016 ~virt:11_052 ~shr:3_840 "dbus-broker";
        program ~user:"root" ~cpu:0 ~burst:2 ~res:22_656 ~virt:340_532 ~shr:18_176 "NetworkManager";
        program ~user:"root" ~cpu:0 ~res:9_344 ~virt:16_124 ~shr:8_064 "sshd";
        program ~user:me ~cpu:12 ~burst:30 ~res:21_504 ~virt:1_284_628 ~shr:16_128 "pipewire";
        program ~user:me ~cpu:24 ~burst:60 ~res:412_380 ~virt:5_912_448 ~shr:138_240 "gnome-shell";
        program ~user:me ~cpu:8 ~burst:40 ~res:98_816 ~virt:1_043_224 ~shr:61_312 "Xwayland";
        program ~user:me ~cpu:46 ~burst:180 ~res:1_183_744 ~virt:36_284_416 ~shr:312_576 "zed";
        program ~user:me ~cpu:4 ~burst:10 ~res:52_480 ~virt:1_201_352 ~shr:44_032 "zed --crash-handler";
        program ~user:me ~cpu:18 ~burst:240 ~res:684_032 ~virt:1_912_840 ~shr:24_576 "ocamllsp";
        program ~user:me ~cpu:30 ~burst:420 ~res:312_960 ~virt:704_512 ~shr:20_480 "dune build -w @check";
        program ~user:me ~cpu:6 ~burst:40 ~res:188_416 ~virt:1_084_672 ~shr:52_224 "node esbuild --watch";
        program ~user:me ~cpu:0 ~burst:3 ~res:61_440 ~virt:312_608 ~shr:13_312 "utop";
        program ~user:me ~cpu:3 ~burst:50 ~res:73_728 ~virt:1_412_096 ~shr:12_288 "demo_server.exe --port 8080";
        program ~user:me ~cpu:62 ~burst:200 ~res:1_734_656 ~virt:13_168_640 ~shr:401_408 "firefox";
        program ~user:me ~cpu:21 ~burst:150 ~res:612_352 ~virt:3_407_872 ~shr:139_264 "Isolated Web Co";
        program ~user:me ~cpu:2 ~burst:20 ~res:248_832 ~virt:2_621_440 ~shr:102_400 "Isolated Web Co";
        program ~user:"postgres" ~cpu:0 ~burst:8 ~res:30_720 ~virt:219_136 ~shr:27_648 "postgres";
        program ~user:"postgres" ~cpu:0 ~burst:4 ~res:9_216 ~virt:219_264 ~shr:7_168 "postgres: walwriter";
        program ~user:me ~cpu:0 ~res:5_632 ~virt:8_840 ~shr:3_712 "bash";
        program ~user:me ~cpu:3 ~burst:4 ~res:4_480 ~virt:12_100 ~shr:3_456 "top -d 1";
      ];
    short_lived =
      [
        program ~user:me ~cpu:900 ~burst:99 ~res:96_256 ~virt:181_248 ~shr:9_216 ~life:2 "ocamlopt.opt";
        program ~user:me ~cpu:400 ~burst:300 ~res:30_720 ~virt:92_160 ~shr:7_168 ~life:1 "git status";
      ];
  }

let build =
  let me = "ci" in
  let job n = program ~user:me ~cpu:0 ~burst:10 ~res:8_192 ~virt:24_576 ~shr:5_120 ("runner: job " ^ n) in
  {
    name = "build-01";
    user_name = me;
    kernel = "Linux 6.12.48-1-lts";
    cores = 32;
    mem = 1_289_216;
    swap = 0;
    boot = (41 * 86400) + (17 * 3600) + (3 * 60);
    clock = (3 * 3600) + (14 * 60) + 51;
    users = 1;
    seed = 2024;
    programs =
      [
        program ~user:"root" ~cpu:0 ~res:12_544 ~virt:22_016 ~shr:9_216 "systemd";
        kernel "kthreadd";
        kernel ~cpu:4 ~burst:20 "rcu_preempt";
        kernel ~cpu:2 ~burst:30 "ksoftirqd/12";
        kernel ~cpu:6 ~burst:40 "kworker/u64:1-flush-259:0";
        kernel ~cpu:0 ~burst:10 "kcompactd0";
        program ~user:"root" ~cpu:0 ~burst:6 ~res:61_440 ~virt:131_072 ~shr:59_392 "systemd-journald";
        program ~user:"root" ~cpu:0 ~res:8_704 ~virt:15_872 ~shr:7_680 "sshd";
        program ~user:"root" ~cpu:8 ~burst:60 ~res:98_304 ~virt:2_244_608 ~shr:51_200 "containerd";
        program ~user:"root" ~cpu:4 ~burst:30 ~res:131_072 ~virt:3_145_728 ~shr:65_536 "dockerd";
        program ~user:me ~cpu:6 ~burst:20 ~res:65_536 ~virt:1_572_864 ~shr:30_720 "Runner.Listener";
        program ~user:me ~cpu:4 ~burst:20 ~res:73_728 ~virt:1_605_632 ~shr:32_768 "Runner.Worker";
        job "3184 (opam install)";
        job "3185 (make test)";
        program ~user:me ~cpu:180 ~burst:600 ~res:524_288 ~virt:1_310_720 ~shr:32_768 "dune build @install @runtest -j 32";
        program ~user:me ~cpu:960 ~burst:40 ~res:1_048_576 ~virt:1_966_080 ~shr:12_288 "ocamlopt.opt -O3 src/printer.ml";
        program ~user:me ~cpu:940 ~burst:60 ~res:786_432 ~virt:1_474_560 ~shr:12_288 "ocamlopt.opt -O3 src/state.ml";
        program ~user:me ~cpu:910 ~burst:90 ~res:655_360 ~virt:1_310_720 ~shr:12_288 "melange.exe -o js/router.js";
        program ~user:me ~cpu:12 ~burst:200 ~res:122_880 ~virt:1_212_416 ~shr:40_960 "node scripts/bundle.ts";
        program ~user:me ~cpu:0 ~burst:300 ~res:2_097_152 ~virt:5_242_880 ~shr:16_384 "opam-solver";
        program ~user:"root" ~cpu:2 ~burst:8 ~res:24_576 ~virt:729_088 ~shr:12_288 "node_exporter";
        program ~user:me ~cpu:0 ~res:5_120 ~virt:8_840 ~shr:3_584 "bash";
        program ~user:me ~cpu:2 ~burst:4 ~res:4_352 ~virt:12_100 ~shr:3_328 "top -d 1";
      ];
    short_lived =
      [
        program ~user:me ~cpu:960 ~burst:40 ~res:212_992 ~virt:425_984 ~shr:12_288 ~life:3 "ocamlopt.opt";
        program ~user:me ~cpu:900 ~burst:99 ~res:131_072 ~virt:262_144 ~shr:12_288 ~life:2 "ocamlc.opt";
        program ~user:me ~cpu:990 ~burst:10 ~res:96_256 ~virt:180_224 ~shr:8_192 ~life:2 "cc1";
        program ~user:me ~cpu:600 ~burst:300 ~res:40_960 ~virt:81_920 ~shr:6_144 ~life:1 "as";
        program ~user:me ~cpu:800 ~burst:200 ~res:262_144 ~virt:409_600 ~shr:10_240 ~life:2 "ld";
      ];
  }

let database =
  let backend ?life name = program ?life ~user:"postgres" ~cpu:60 ~burst:350 ~res:262_144 ~virt:17_563_648 ~shr:249_856 name in
  {
    name = "db-1";
    user_name = "yuka";
    kernel = "Linux 6.8.0-87-generic";
    cores = 16;
    mem = 1_289_216;
    swap = 40_960;
    boot = (187 * 86400) + (2 * 3600) + (48 * 60);
    clock = (11 * 3600) + (5 * 60) + 33;
    users = 3;
    seed = 7;
    programs =
      [
        program ~user:"root" ~cpu:0 ~res:13_056 ~virt:167_936 ~shr:8_448 "systemd";
        kernel "kthreadd";
        kernel ~cpu:3 ~burst:10 "rcu_sched";
        kernel ~cpu:2 ~burst:60 "kworker/u32:0-writeback";
        kernel ~cpu:1 ~burst:80 "jbd2/nvme0n1p2-8";
        program ~user:"root" ~cpu:0 ~burst:4 ~res:52_224 ~virt:98_304 ~shr:50_176 "systemd-journald";
        program ~user:"root" ~cpu:0 ~res:8_960 ~virt:15_616 ~shr:7_424 "sshd";
        program ~user:"postgres" ~cpu:4 ~burst:20 ~res:3_407_872 ~virt:17_301_504 ~shr:3_391_488 "postgres -D /var/lib/postgresql/17";
        program ~user:"postgres" ~cpu:2 ~burst:120 ~res:4_194_304 ~virt:17_317_888 ~shr:4_177_920 "postgres: checkpointer";
        program ~user:"postgres" ~cpu:3 ~burst:40 ~res:1_048_576 ~virt:17_317_888 ~shr:1_040_384 "postgres: background writer";
        program ~user:"postgres" ~cpu:14 ~burst:90 ~res:20_480 ~virt:17_317_888 ~shr:18_432 "postgres: walwriter";
        program ~user:"postgres" ~cpu:1 ~burst:30 ~res:12_288 ~virt:17_317_888 ~shr:9_216 "postgres: autovacuum launcher";
        program ~user:"postgres" ~cpu:6 ~burst:40 ~res:10_240 ~virt:17_317_888 ~shr:8_192 "postgres: walsender replica 10.0.0.12";
        backend "postgres: yuka 10.0.0.4 SELECT";
        backend "postgres: yuka 10.0.0.4 idle";
        backend "postgres: yuka 10.0.0.5 UPDATE";
        backend "postgres: yuka 10.0.0.5 idle in transaction";
        backend "postgres: yuka 10.0.0.6 COPY";
        program ~user:"pgbouncer" ~cpu:18 ~burst:60 ~res:14_336 ~virt:30_720 ~shr:6_144 "pgbouncer /etc/pgbouncer.ini";
        program ~user:"prometh+" ~cpu:4 ~burst:20 ~res:22_528 ~virt:1_253_376 ~shr:12_288 "postgres_exporter";
        program ~user:"root" ~cpu:2 ~burst:8 ~res:24_576 ~virt:729_088 ~shr:12_288 "node_exporter";
        program ~user:"yuka" ~cpu:0 ~res:5_120 ~virt:8_840 ~shr:3_584 "bash";
        program ~user:"yuka" ~cpu:0 ~burst:2 ~res:12_288 ~virt:28_672 ~shr:9_216 "psql yuka";
        program ~user:"yuka" ~cpu:2 ~burst:4 ~res:4_352 ~virt:12_100 ~shr:3_328 "top -d 1";
      ];
    short_lived =
      [
        backend ~life:4 "postgres: yuka 10.0.0.7 SELECT";
        program ~user:"postgres" ~cpu:300 ~burst:500 ~res:524_288 ~virt:17_563_648 ~shr:262_144 ~life:3
          "postgres: autovacuum worker issues";
      ];
  }

let hosts = [ laptop; build; database ]

let find name = List.find_opt (fun host -> host.name = name) hosts

let host_of (t : t) = match find t.host with Some host -> host | None -> laptop

(* A random number in [0, bound), from a seed that the caller threads. *)
let draw seed bound =
  seed := next !seed;
  if bound <= 0 then 0 else (!seed lsr 7) mod bound

let clamp low high x = if x < low then low else if x > high then high else x

(* The %CPU of a process for one screen: mostly near [base], with a burst now and then. *)
let cpu_of seed ~base ~burst =
  let jitter = if base = 0 then 0 else draw seed ((base / 3) + 1) - (base / 6) in
  let spike = if burst > 0 && draw seed 5 = 0 then draw seed (burst + 1) else 0 in
  clamp 0 1000 (base + jitter + spike)

let state_of seed ~kernel ~cpu =
  if cpu >= 300 then 'R'
  else if cpu > 0 && draw seed 9 = 0 then 'R'
  else if (not kernel) && draw seed 200 = 0 then 'D'
  else if kernel then 'I'
  else 'S'

(* %MEM in tenths. The memory is divided first, so the product stays under 2^31. *)
let mem_of (host : host) res = res * 100 / (host.mem / 10 * 1024 / 10)

let spawn seed (host : host) ~pid (program : program) =
  let cpu = cpu_of seed ~base:program.cpu ~burst:program.burst in
  {
    pid;
    user = program.user;
    pr = 20 + program.nice;
    ni = program.nice;
    virt = program.virt;
    res = program.res;
    shr = program.shr;
    state = state_of seed ~kernel:(program.virt = 0) ~cpu;
    cpu;
    mem = mem_of host program.res;
    time = 0;
    command = program.command;
    left = program.life;
    base = program.cpu;
    burst = program.burst;
  }

let mib_of_kib kib = kib * 10 / 1024

(* The summary lines: the CPU split, the memory and the load. *)
let summarize seed (host : host) procs ~cache ~load:(l1, l5, l15) =
  let busy = Array.fold_left (fun sum p -> sum + p.cpu) 0 procs in
  let split share =
    let used = clamp 0 1000 (share + draw seed 6) in
    let sy = used / 4 in
    let wa = draw seed 8 in
    let ni = if draw seed 4 = 0 then draw seed 4 else 0 in
    let si = draw seed 4 in
    let hi = 0 in
    let us = used - sy in
    { us; sy; ni; wa; hi; si; id = max 0 (1000 - us - sy - ni - wa - hi - si) }
  in
  let total = split (busy / host.cores) in
  let cores =
    Array.init host.cores (fun _ ->
        (* Each core takes a share of the work, unevenly. *)
        let weight = 60 + draw seed 80 in
        split (busy * weight / 100 / host.cores))
  in
  let resident = Array.fold_left (fun sum p -> sum + p.res) 0 procs in
  let used = clamp 0 (host.mem - cache) (mib_of_kib resident + (host.mem / 12)) in
  (* The load moves towards the number of busy cores, as the kernel's averages do over
     1, 5 and 15 minutes. *)
  let running = busy / 10 in
  let towards load keep = ((load * keep) + (running * (1000 - keep))) / 1000 in
  (total, cores, used, (towards l1 983, towards l5 997, towards l15 999))

let start (host : host) =
  let seed = ref host.seed in
  let procs =
    List.mapi
      (fun i (program : program) ->
        let pid = if i = 0 then 1 else if program.virt = 0 then i + 1 else 300 + (i * 97) + draw seed 90 in
        let p = spawn seed host ~pid program in
        (* The CPU time so far, in hundredths: %CPU over a part of the uptime, or under
           a minute for a busy program, which started a moment ago. *)
        let time =
          if p.base >= 300 then draw seed 6000 else p.base * (host.boot / 100) * 2 * (1 + draw seed 5)
        in
        { p with time })
      host.programs
  in
  let procs = Array.of_list procs in
  let cache = host.mem / 3 + draw seed (host.mem / 10) in
  let busy = Array.fold_left (fun sum p -> sum + p.cpu) 0 procs / 10 in
  let l1 = busy + draw seed 40 in
  let l5 = (busy * 9 / 10) + draw seed 30 in
  let l15 = (busy * 8 / 10) + draw seed 20 in
  let total, cores, used, load = summarize seed host procs ~cache ~load:(l1, l5, l15) in
  let next_pid = 300 + (List.length host.programs * 97) + 1000 + draw seed 500 in
  let swap_used = if host.swap = 0 then 0 else draw seed (host.swap / 40) in
  {
    host = host.name;
    tick = 0;
    clock = host.clock;
    uptime = host.boot;
    seed = !seed;
    next_pid;
    load;
    total;
    cores;
    used;
    cache;
    swap_used;
    procs;
  }

(* The next screen, [delay] seconds later. *)
let step (t : t) =
  let host = host_of t in
  let seed = ref t.seed in
  let next_pid = ref t.next_pid in
  let survivors =
    Array.to_list t.procs
    |> List.filter_map (fun p ->
           if p.left = 1 then None
           else
             let cpu = cpu_of seed ~base:p.base ~burst:p.burst in
             let res =
               if p.virt = 0 then 0
               else clamp (p.shr / 2) (p.virt / 2) (p.res + (draw seed 9 - 4) * (p.res / 2000))
             in
             Some
               {
                 p with
                 cpu;
                 res;
                 mem = mem_of host res;
                 state = state_of seed ~kernel:(p.virt = 0) ~cpu;
                 time = p.time + (cpu * delay / 10);
                 left = (if p.left > 1 then p.left - 1 else 0);
               })
  in
  let born =
    List.filter_map
      (fun program ->
        if draw seed 3 = 0 then begin
          next_pid := !next_pid + 1 + draw seed 40;
          Some (spawn seed host ~pid:!next_pid program)
        end
        else None)
      host.short_lived
  in
  let procs = Array.of_list (survivors @ born) in
  let cache = clamp (host.mem / 5) (host.mem / 2) (t.cache + draw seed 2001 - 1000) in
  let total, cores, used, load = summarize seed host procs ~cache ~load:t.load in
  {
    t with
    tick = t.tick + 1;
    clock = (t.clock + delay) mod 86400;
    uptime = t.uptime + delay;
    seed = !seed;
    next_pid = !next_pid;
    load;
    total;
    cores;
    used;
    cache;
    procs;
  }

let kill (t : t) pid =
  { t with procs = Array.of_list (List.filter (fun p -> p.pid <> pid) (Array.to_list t.procs)) }

(* The text of top. *)

let pad width text =
  let n = String.length text in
  if n >= width then text else String.make (width - n) ' ' ^ text

let tenths x =
  let sign = if x < 0 then "-" else "" in
  let x = abs x in
  sign ^ Int.to_string (x / 10) ^ "." ^ Int.to_string (x mod 10)

let hundredths x =
  let two n = if n < 10 then "0" ^ Int.to_string n else Int.to_string n in
  Int.to_string (x / 100) ^ "." ^ two (x mod 100)

let two n = if n < 10 then "0" ^ Int.to_string n else Int.to_string n

let clock seconds = two (seconds / 3600) ^ ":" ^ two (seconds / 60 mod 60) ^ ":" ^ two (seconds mod 60)

let uptime seconds =
  let days = seconds / 86400 and hours = seconds / 3600 mod 24 and minutes = seconds / 60 mod 60 in
  let time = pad 2 (Int.to_string hours) ^ ":" ^ two minutes in
  match days with 0 -> time | 1 -> "1 day, " ^ time | n -> Int.to_string n ^ " days, " ^ time

(* TIME+ as top writes it: minutes:seconds.hundredths, without the hundredths from
   1000 minutes on, so it keeps to its column. *)
let time hundredths =
  let seconds = hundredths / 100 in
  let minutes = Int.to_string (seconds / 60) ^ ":" ^ two (seconds mod 60) in
  if seconds / 60 >= 1000 then minutes else minutes ^ "." ^ two (hundredths mod 100)

(* VIRT, RES and SHR: KiB, or gibibytes once the number has more than seven digits. *)
let kib n = if n < 10_000_000 then Int.to_string n else tenths (n / 104_858) ^ "g"

(* USER as top writes it: eight characters, the eighth a [+] when the name is longer. *)
let user name = if String.length name <= 8 then name else String.sub name 0 7 ^ "+"

let running (t : t) = Array.fold_left (fun n p -> if p.state = 'R' then n + 1 else n) 0 t.procs

let count state (t : t) = Array.fold_left (fun n p -> if p.state = state then n + 1 else n) 0 t.procs

type sort = Cpu | Mem | Pid | Time | Command

let compare_by sort (a : proc) (b : proc) =
  let primary =
    match sort with
    | Cpu -> compare b.cpu a.cpu
    | Mem -> compare b.res a.res
    | Pid -> compare b.pid a.pid
    | Time -> compare b.time a.time
    | Command -> compare a.command b.command
  in
  if primary <> 0 then primary else compare a.pid b.pid

let sorted ~sort ~reverse (t : t) =
  let list = List.stable_sort (compare_by sort) (Array.to_list t.procs) in
  Array.of_list (if reverse then List.rev list else list)
