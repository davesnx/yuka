open Ssr_data.Data

let escape b s =
  String.iter
    (function
      | '&' -> Buffer.add_string b "&amp;"
      | '<' -> Buffer.add_string b "&lt;"
      | '>' -> Buffer.add_string b "&gt;"
      | '"' -> Buffer.add_string b "&quot;"
      | '\'' -> Buffer.add_string b "&#x27;"
      | c -> Buffer.add_char b c)
    s

let render issues =
  let b = Buffer.create 65536 in
  let add = Buffer.add_string b in
  add
    "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>Issues</title><link rel=\"stylesheet\" \
     href=\"/static/style.css\"></head><body><main><h1>All issues</h1><ul class=\"issues\">";
  List.iter
    (fun i ->
      add "<li class=\"issue\"><a class=\"row\" href=\"/issue/";
      escape b i.id;
      add "\"><span class=\"id\">";
      escape b i.id;
      add "</span><span class=\"title\">";
      escape b i.title;
      add "</span><span class=\"status status-";
      escape b (slug i.status);
      add "\">";
      escape b i.status;
      add "</span><span class=\"priority\">";
      escape b i.priority;
      add "</span><span class=\"assignee\">";
      escape b (Option.value i.assignee ~default:"Unassigned");
      add "</span><span class=\"labels\">";
      List.iter
        (fun l ->
          add "<span class=\"label\">";
          escape b l;
          add "</span>")
        i.labels;
      add "</span></a></li>")
    issues;
  add "</ul></main></body></html>";
  Buffer.contents b

let () =
  let port, issues = args () in
  Dream.run ~interface:"127.0.0.1" ~port
  @@ Dream.router [ Dream.get "/" (fun _ -> Dream.html (render issues)) ]
