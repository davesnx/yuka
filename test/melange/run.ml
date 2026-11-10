external exit : int -> unit = "exit" [@@mel.scope "process"]
external on_exit : string -> (unit -> unit) -> unit = "on" [@@mel.scope "process"]
let set_exit_code : int -> unit = [%mel.raw "function (c) { process.exitCode = c }"]

let failures = ref 0

let report name = function
  | None -> print_endline ("ok " ^ name)
  | Some e ->
      incr failures;
      print_endline ("FAIL " ^ name ^ ": " ^ Printexc.to_string e)

let sync_cases = Cases.all @ Dom_cases.all @ Island_cases.all @ Catch_cases.all
let async_cases = Island_cases.async @ Remote_cases.async @ Form_cases.async
let total = List.length sync_cases + List.length async_cases
let finished = ref false

let finish () =
  finished := true;
  Printf.printf "%d cases, %d failures\n" total !failures;
  if !failures > 0 then set_exit_code 1

let rec run_async = function
  | [] -> finish ()
  | (name, case) :: rest ->
      let next result =
        report name result;
        run_async rest
      in
      (match case (fun check -> next (match check () with () -> None | exception e -> Some e)) with
      | () -> ()
      | exception e -> next (Some e))

let () =
  on_exit "exit" (fun () ->
      if not !finished then begin
        print_endline "async cases did not finish";
        set_exit_code 1
      end);
  List.iter
    (fun (name, case) ->
      report name (match case () with () -> None | exception e -> Some e))
    sync_cases;
  run_async async_cases
