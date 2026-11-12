type options = {
  build : string;
  assets : string list;
  state : string;
  kill_after : float;
  watch_exe : string option;
  server : string list;
}

let default_state () =
  let dir = match Sys.getenv_opt "DUNE_BUILD_DIR" with Some d when d <> "" -> d | _ -> "_build" in
  Filename.concat dir ".yuka-dev"

let parse argv =
  let build = ref "dune build --watch" and assets = ref [] and state = ref (default_state ()) in
  let kill_after = ref 2. and watch_exe = ref None and server = ref [] in
  let c =
    { Cli.name = "dev";
      usage =
        "usage: yuka dev [--build COMMAND] [--assets DIR]... [--state FILE] [--kill-after SECONDS] [--watch-exe FILE] \
         -- SERVER [ARG]...\n\
         Run COMMAND, a dune build in watch mode; restart SERVER after each build that changes it and reload the browser.";
      specs =
        [ ("--build", Arg.Set_string build, "COMMAND The build command, run by /bin/sh (default: dune build --watch)");
          ("--assets", Arg.String (fun d -> assets := !assets @ [ d ]), "DIR A directory of files that the server serves");
          ("--state", Arg.Set_string state, "FILE The state file for the server (default: $DUNE_BUILD_DIR/.yuka-dev, or _build/.yuka-dev)");
          ("--kill-after", Arg.Float (fun f -> kill_after := f), "SECONDS Time from SIGTERM to SIGKILL when the server stops (default: 2)");
          ("--watch-exe", Arg.String (fun f -> watch_exe := Some f), "FILE The file whose change restarts the server (default: SERVER)");
          ("--", Arg.Rest_all (fun args -> server := args), " The server command and its arguments") ] }
  in
  Cli.parse c argv;
  if !server = [] then Cli.usage_error c "no server command; give it after --";
  if !kill_after < 0. then Cli.usage_error c "--kill-after takes a number of seconds that is not negative";
  { build = !build; assets = !assets; state = !state; kill_after = !kill_after; watch_exe = !watch_exe; server = !server }

let log fmt = Printf.ksprintf (fun s -> prerr_endline ("yuka dev: " ^ s)) fmt

let write_state file ~session ~build ~page ~error =
  let text =
    Printf.sprintf {|{"session":%s,"build":%d,"page":%d,"error":%s}|} (Source_text.json_string session) build page
      (match error with None -> "null" | Some e -> Source_text.json_string e)
  in
  let tmp = file ^ ".tmp" in
  Out_channel.with_open_bin tmp (fun oc -> output_string oc text);
  Sys.rename tmp file

let rec mkdir_p dir =
  if dir <> "" && dir <> "." && dir <> "/" && not (Sys.file_exists dir) then begin
    mkdir_p (Filename.dirname dir);
    try Unix.mkdir dir 0o755 with Unix.Unix_error (Unix.EEXIST, _, _) -> ()
  end

let executable o =
  match o.watch_exe with
  | Some f -> f
  | None ->
      let prog = List.hd o.server in
      if String.contains prog '/' then prog
      else
        let dirs = String.split_on_char ':' (Option.value (Sys.getenv_opt "PATH") ~default:"") in
        let found =
          List.find_opt
            (fun d ->
              let p = Filename.concat (if d = "" then "." else d) prog in
              Sys.file_exists p && not (Sys.is_directory p))
            dirs
        in
        Option.fold ~none:prog ~some:(fun d -> Filename.concat (if d = "" then "." else d) prog) found

let strip_ansi s =
  let b = Buffer.create (String.length s) in
  let n = String.length s in
  let rec go i =
    if i < n then
      if s.[i] = '\027' && i + 1 < n && s.[i + 1] = '[' then begin
        let j = ref (i + 2) in
        while !j < n && not (s.[!j] >= '@' && s.[!j] <= '~') do incr j done;
        go (!j + 1)
      end
      else begin
        Buffer.add_char b s.[i];
        go (i + 1)
      end
  in
  go 0;
  Buffer.contents b

let stamp path = match Unix.stat path with s -> Some (s.st_mtime, s.st_size) | exception Unix.Unix_error _ -> None

let rec files dir =
  match Sys.readdir dir with
  | names ->
      Array.to_list names
      |> List.concat_map (fun n ->
             let p = Filename.concat dir n in
             if Sys.is_directory p then files p else [ p ])
  | exception Sys_error _ -> []

let snapshot dirs = List.concat_map files dirs |> List.map (fun p -> (p, stamp p))

let changed before after =
  let differs (p, s) other = match List.assoc_opt p other with Some s' -> s' <> s | None -> true in
  List.filter_map (fun (p, s) -> if differs (p, s) before then Some p else None) after
  @ List.filter_map (fun (p, _) -> if List.mem_assoc p after then None else Some p) before

let plain_css p = Filename.check_suffix p ".css"

type server = { mutable pid : int option }

let rec waitpid flags pid =
  match Unix.waitpid flags pid with
  | r -> r
  | exception Unix.Unix_error (Unix.EINTR, _, _) -> waitpid flags pid

let running server =
  match server.pid with
  | None -> false
  | Some pid -> (
      match waitpid [ Unix.WNOHANG ] pid with
      | 0, _ -> true
      | _ ->
          server.pid <- None;
          false
      | exception Unix.Unix_error (Unix.ECHILD, _, _) ->
          server.pid <- None;
          false)

let stop o server =
  match server.pid with
  | None -> ()
  | Some pid ->
      (try Unix.kill pid Sys.sigterm with Unix.Unix_error _ -> ());
      let deadline = Unix.gettimeofday () +. o.kill_after in
      let rec wait () =
        match waitpid [ Unix.WNOHANG ] pid with
        | 0, _ when Unix.gettimeofday () < deadline ->
            (try Unix.sleepf 0.02 with Unix.Unix_error (Unix.EINTR, _, _) -> ());
            wait ()
        | 0, _ ->
            log "the server did not stop after %g s, killing it" o.kill_after;
            (try Unix.kill pid Sys.sigkill with Unix.Unix_error _ -> ());
            (try ignore (waitpid [] pid) with Unix.Unix_error (Unix.ECHILD, _, _) -> ())
        | _ -> ()
        | exception Unix.Unix_error (Unix.ECHILD, _, _) -> ()
      in
      wait ();
      server.pid <- None

let start o server =
  let env = Array.append [| "YUKA_DEV=1"; "YUKA_DEV_FILE=" ^ o.state |] (Unix.environment ()) in
  let prog = List.hd o.server in
  match Unix.create_process_env prog (Array.of_list o.server) env Unix.stdin Unix.stdout Unix.stderr with
  | pid -> server.pid <- Some pid
  | exception Unix.Unix_error (e, _, _) -> log "cannot start %s: %s" prog (Unix.error_message e)

let status line =
  let line = strip_ansi line in
  let has sub =
    let n = String.length sub in
    let rec at i = i + n <= String.length line && (String.sub line i n = sub || at (i + 1)) in
    at 0
  in
  if has "waiting for filesystem changes" then
    if String.starts_with ~prefix:"Success" (String.trim line) then `Success else `Failed
  else `Line line

let session_id () =
  Random.self_init ();
  Printf.sprintf "%08x%08x" (Random.bits ()) (Random.bits ())

let run o =
  let session = session_id () in
  let server = { pid = None } in
  let build = ref 0 and page = ref 0 in
  let exe = ref None and assets = ref [] in
  let output = Buffer.create 1024 in
  let watched = executable o in
  mkdir_p (Filename.dirname o.state);
  let write ~error = write_state o.state ~session ~build:!build ~page:!page ~error in
  let r, w = Unix.pipe ~cloexec:true () in
  let dune_pid =
    match Unix.fork () with
    | 0 -> (
        try
          ignore (Unix.setsid ());
          Unix.dup2 w Unix.stdout;
          Unix.dup2 w Unix.stderr;
          Unix.execv "/bin/sh" [| "/bin/sh"; "-c"; o.build |]
        with _ -> Unix._exit 127)
    | pid -> pid
  in
  Unix.close w;
  let finishing = ref false in
  let finish code =
    if not !finishing then begin
      finishing := true;
      let failed = ref false in
      let step name f =
        try f () with e ->
          failed := true;
          log "%s: %s" name (Printexc.to_string e)
      in
      step "stopping the server" (fun () -> stop o server);
      step "stopping dune" (fun () ->
          try Unix.kill (-dune_pid) Sys.sigterm with Unix.Unix_error (Unix.ESRCH, _, _) -> ());
      exit (if !failed then 1 else code)
    end
  in
  Sys.set_signal Sys.sigint (Sys.Signal_handle (fun _ -> finish 130));
  Sys.set_signal Sys.sigterm (Sys.Signal_handle (fun _ -> finish 143));
  let input = Unix.in_channel_of_descr r in
  let success () =
    let now_exe = stamp watched and now_assets = snapshot o.assets in
    let first = !build = 0 in
    let moved = if first then [] else changed !assets now_assets in
    let restart =
      first || now_exe = None || now_exe <> !exe || not (running server)
      || not (List.for_all plain_css moved)
    in
    exe := now_exe;
    assets := now_assets;
    if restart then begin
      incr build;
      page := !build;
      write ~error:None;
      if server.pid <> None then log "restarting the server";
      stop o server;
      start o server
    end
    else if moved <> [] then begin
      incr build;
      write ~error:None
    end
    else write ~error:None
  in
  let rec loop () =
    match input_line input with
    | line ->
        prerr_endline line;
        (match status line with
        | `Success ->
            Buffer.clear output;
            success ()
        | `Failed ->
            write ~error:(Some (String.trim (Buffer.contents output)));
            Buffer.clear output
        | `Line l when String.length l > 0 && String.trim l = "" -> ()
        | `Line l when String.starts_with ~prefix:"********** NEW BUILD" l -> Buffer.clear output
        | `Line l ->
            Buffer.add_string output l;
            Buffer.add_char output '\n');
        loop ()
    | exception End_of_file ->
        let code = match waitpid [] dune_pid with _, Unix.WEXITED c -> c | _ -> 1 in
        finish code
  in
  match loop () with
  | () -> ()
  | exception e ->
      log "%s" (Printexc.to_string e);
      finish 1

let main argv = run (parse argv)
