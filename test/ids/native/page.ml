open Yuka

let starts_at s i p = i + String.length p <= String.length s && String.sub s i (String.length p) = p

let rec index_from s i p =
  if i + String.length p > String.length s then invalid_arg ("no " ^ p)
  else if starts_at s i p then i
  else index_from s (i + 1) p

let fill html (id, chunk) =
  let opening = "<!--[" ^ id ^ "-->" in
  let after = index_from html 0 opening + String.length opening in
  let rec close i depth =
    if starts_at html i "<!--]-->" then if depth = 0 then i else close (i + 8) (depth - 1)
    else if starts_at html i "<!--[" then close (i + 5) (depth + 1)
    else close (i + 1) depth
  in
  let stop = close after 0 in
  String.sub html 0 after ^ chunk ^ String.sub html stop (String.length html - stop)

let streamed () =
  let async, resolve, _ = Async.make () in
  let session = Private.session ~streaming:true ~islands_only:true in
  let shell = Private.print session (fun () -> Private.node (Ids_cases.page async)) in
  let pending = Private.take_pending session in
  resolve "done";
  let fills =
    List.filter_map
      (function Private.Pending_await { id; fill; _ } -> Some (id, fill ()) | _ -> None)
      pending
  in
  (shell, fills)

let answer () =
  let body =
    Private.settled ~id_prefix:"L1/x-" ~sleep:(fun _ -> Async.return ()) (fun () ->
        Ids_cases.answer (Async.return "done"))
  in
  match Async.status body with Async.Done html -> html | _ -> invalid_arg "the answer did not settle"

let () =
  Server.set_default_log (fun _ _ -> ());
  match Sys.argv with
  | [| _; "shell" |] -> print_string (fst (streamed ()))
  | [| _; "filled" |] ->
      let shell, fills = streamed () in
      print_string (List.fold_left fill shell fills)
  | [| _; "answer" |] -> print_string (answer ())
  | _ -> invalid_arg "page.exe shell|filled|answer"
