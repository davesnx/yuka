let issues = Ssr_data.Data.issues 100
let styles = [ "/static/style.css" ]

let time name n f =
  for _ = 1 to n / 10 do
    ignore (f ())
  done;
  Gc.full_major ();
  let words = Gc.minor_words () in
  let t = Unix.gettimeofday () in
  for _ = 1 to n do
    ignore (f ())
  done;
  let dt = Unix.gettimeofday () -. t in
  Printf.printf "%-10s %8.1f us/render %10.0f words/render\n%!" name
    (dt *. 1e6 /. float_of_int n)
    ((Gc.minor_words () -. words) /. float_of_int n)

let () =
  let n = try int_of_string Sys.argv.(1) with _ -> 3000 in
  time "document" n (fun () -> Yuka.Server.document ~title:"Issues" ~styles (Ssr_view.view issues));
  let handler = Yuka_dream.handler (Yuka.Server.config ~styles ()) (Ssr_view.stream_app issues) in
  time "stream" n (fun () ->
      Lwt_main.run (Dream.body (Dream.test handler (Dream.request ~target:"/stream" ""))))
