type options = {
  dune : string;
  targets : string list;
  assets : string list;
  state : string;
  kill_after : float;
  server : string list;
}

let usage =
  "usage: yuka dev [--build TARGET]... [--assets DIR]... [--state FILE] [--dune CMD] [--kill-after SECONDS] -- \
   SERVER [ARG]..."

exception Usage of string

let parse args =
  let rec go o = function
    | "--" :: (_ :: _ as server) -> { o with server }
    | "--" :: [] -> raise (Usage "no server command after --")
    | "--build" :: t :: rest -> go { o with targets = o.targets @ [ t ] } rest
    | "--assets" :: d :: rest -> go { o with assets = o.assets @ [ d ] } rest
    | "--state" :: f :: rest -> go { o with state = f } rest
    | "--dune" :: d :: rest -> go { o with dune = d } rest
    | "--kill-after" :: s :: rest -> (
        match float_of_string_opt s with
        | Some f when f >= 0. -> go { o with kill_after = f } rest
        | _ -> raise (Usage ("--kill-after takes a number of seconds, not " ^ s)))
    | [ ("--build" | "--assets" | "--state" | "--dune" | "--kill-after") as flag ] ->
        raise (Usage (flag ^ " needs a value"))
    | arg :: _ -> raise (Usage ("unknown argument " ^ arg))
    | [] -> raise (Usage "no server command; give it after --")
  in
  match args with
  | "dev" :: rest ->
      let o =
        go
          { dune = "dune"; targets = []; assets = []; state = "_build/.yuka-dev"; kill_after = 2.; server = [] }
          rest
      in
      { o with targets = (if o.targets = [] then [ "@@default" ] else o.targets) }
  | [] -> raise (Usage "no command")
  | cmd :: _ -> raise (Usage ("unknown command " ^ cmd))

let log fmt = Printf.ksprintf (fun s -> prerr_endline ("yuka dev: " ^ s)) fmt

let json_string s =
  let b = Buffer.create (String.length s + 2) in
  Buffer.add_char b '"';
  String.iter
    (function
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | c when Char.code c < 0x20 -> Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char b c)
    s;
  Buffer.add_char b '"';
  Buffer.contents b

let write_state file ~build ~page ~error =
  let text =
    Printf.sprintf {|{"build":%d,"page":%d,"error":%s}|} build page
      (match error with None -> "null" | Some e -> json_string e)
  in
  let tmp = file ^ ".tmp" in
  Out_channel.with_open_bin tmp (fun oc -> output_string oc text);
  Sys.rename tmp file

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
  List.filter_map
    (fun (p, s) -> match List.assoc_opt p before with Some s' when s' = s -> None | _ -> Some p)
    after

type server = { mutable pid : int option }

let running server =
  match server.pid with
  | None -> false
  | Some pid -> (
      match Unix.waitpid [ Unix.WNOHANG ] pid with
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
      server.pid <- None;
      (try Unix.kill pid Sys.sigterm with Unix.Unix_error _ -> ());
      let deadline = Unix.gettimeofday () +. o.kill_after in
      let rec wait () =
        match Unix.waitpid [ Unix.WNOHANG ] pid with
        | 0, _ when Unix.gettimeofday () < deadline ->
            Unix.sleepf 0.02;
            wait ()
        | 0, _ ->
            log "the server did not stop after %g s, killing it" o.kill_after;
            (try Unix.kill pid Sys.sigkill with Unix.Unix_error _ -> ());
            ignore (Unix.waitpid [] pid)
        | _ -> ()
        | exception Unix.Unix_error _ -> ()
      in
      wait ()

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

let run o =
  let server = { pid = None } in
  let build = ref 0 and page = ref 0 in
  let exe = ref None and assets = ref [] in
  let output = Buffer.create 1024 in
  (try Unix.mkdir (Filename.dirname o.state) 0o755 with Unix.Unix_error _ -> ());
  let r, w = Unix.pipe ~cloexec:true () in
  let dune_pid =
    Unix.create_process o.dune
      (Array.of_list ((o.dune :: "build" :: "--watch" :: o.targets)))
      Unix.stdin w w
  in
  Unix.close w;
  let finish code =
    stop o server;
    (try Unix.kill dune_pid Sys.sigterm with Unix.Unix_error _ -> ());
    exit code
  in
  Sys.set_signal Sys.sigint (Sys.Signal_handle (fun _ -> finish 130));
  Sys.set_signal Sys.sigterm (Sys.Signal_handle (fun _ -> finish 143));
  let input = Unix.in_channel_of_descr r in
  let success () =
    let now_exe = stamp (List.hd o.server) and now_assets = snapshot o.assets in
    let first = !build = 0 in
    let restart = first || now_exe = None || now_exe <> !exe || not (running server) in
    let moved = if first then [] else changed !assets now_assets in
    exe := now_exe;
    assets := now_assets;
    if restart then begin
      incr build;
      page := !build;
      write_state o.state ~build:!build ~page:!page ~error:None;
      if server.pid <> None then log "restarting the server";
      stop o server;
      start o server
    end
    else if moved <> [] then begin
      incr build;
      if not (List.for_all (fun p -> Filename.check_suffix p ".css") moved) then page := !build;
      write_state o.state ~build:!build ~page:!page ~error:None
    end
    else write_state o.state ~build:!build ~page:!page ~error:None
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
            write_state o.state ~build:!build ~page:!page ~error:(Some (String.trim (Buffer.contents output)));
            Buffer.clear output
        | `Line l when String.length l > 0 && String.trim l = "" -> ()
        | `Line l when String.starts_with ~prefix:"********** NEW BUILD" l -> Buffer.clear output
        | `Line l ->
            Buffer.add_string output l;
            Buffer.add_char output '\n');
        loop ()
    | exception End_of_file ->
        let code = match Unix.waitpid [] dune_pid with _, Unix.WEXITED c -> c | _ -> 1 in
        finish code
  in
  loop ()

let () =
  match parse (List.tl (Array.to_list Sys.argv)) with
  | o -> run o
  | exception Usage m ->
      prerr_endline ("yuka: " ^ m);
      prerr_endline usage;
      exit 2
