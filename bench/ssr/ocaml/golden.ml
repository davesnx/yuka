let issues = Ssr_data.Data.issues 100
let styles = [ "/static/style.css" ]

let () =
  print_string (Ssr_view.document ~title:"Issues" ~styles (Ssr_view.view issues));
  print_string "\n----\n";
  let handler = Yuka_dream.handler (Yuka.Server.config ~styles ()) (Ssr_view.stream_app issues) in
  let response = Dream.test handler (Dream.request ~target:"/stream" "") in
  print_string (Lwt_main.run (Dream.body response))
