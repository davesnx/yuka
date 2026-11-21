open Demo_app

let config =
  Yuka.Server.config
    ~assets:(Result.get_ok (Yuka.Server.modules ~dir:"js" ~entry:"demo/client/main.js" ~manifest:"{}" ~packages:[] ~digest:""))
    ~public:[ ("/static", "static") ]
    ~styles:[ "/static/style.css" ] ~css:Yuka_css.sheets ()

let handler = Dream.set_secret "test" @@ Dream.cookie_sessions @@ Yuka_dream.handler config Yuka_routes.app

let mask text =
  let marker = {|data-yuka-answer="l:csrf">{"ok":"|} in
  let marker_length = String.length marker in
  let buffer = Buffer.create (String.length text) in
  let rec go index =
    if index + marker_length > String.length text then Buffer.add_string buffer (String.sub text index (String.length text - index))
    else if String.sub text index marker_length = marker then begin
      Buffer.add_string buffer marker;
      Buffer.add_string buffer "TOKEN";
      go (String.index_from text (index + marker_length) '"')
    end
    else begin
      Buffer.add_char buffer text.[index];
      go (index + 1)
    end
  in
  go 0;
  Buffer.contents buffer

let is_digit c = c >= '0' && c <= '9'

let digits text index =
  let rec go i = if i < String.length text && is_digit text.[i] then go (i + 1) else i in
  go index

let node_name text index =
  if index + 2 > String.length text || String.sub text index 2 <> {|,"|} then None
  else
    let first = digits text (index + 2) in
    if first = index + 2 || first >= String.length text || text.[first] <> '.' then None
    else
      let second = digits text (first + 1) in
      let seq = digits text (second + 2) in
      let close = {|]}</script>|} in
      if
        second > first + 1
        && second + 2 <= String.length text
        && String.sub text second 2 = {|",|}
        && seq > second + 2
        && seq + String.length close <= String.length text
        && String.sub text seq (String.length close) = close
      then Some (second + 1)
      else None

let mask_node text =
  let buffer = Buffer.create (String.length text) in
  let rec go index =
    if index >= String.length text then ()
    else
      match node_name text index with
      | Some after ->
          Buffer.add_string buffer {|,"NODE"|};
          go after
      | None ->
          Buffer.add_char buffer text.[index];
          go (index + 1)
  in
  go 0;
  Buffer.contents buffer

let readable response body =
  match Dream.header response "yuka-stream" with
  | None -> body
  | Some _ ->
      String.split_on_char '\n' body
      |> List.filter_map (fun line ->
             match Yuka.Json.of_string line with
             | Ok (`String shell) -> Some shell
             | Ok (`List [ `String id; `String html ]) -> Some ("---- part " ^ id ^ "\n" ^ html)
             | Ok (`List []) -> Some "---- end"
             | Ok _ | Error _ -> if line = "" then None else Some ("---- bad line " ^ line))
      |> String.concat "\n"

let () =
  Handlers.register ();
  List.iter
    (fun (target, headers) ->
      let response = Dream.test handler (Dream.request ~target ~headers "") in
      Printf.printf "==== %s %d\n%s\n" target
        (Dream.status_to_int (Dream.status response))
        (mask_node (mask (readable response (Lwt_main.run (Dream.body response))))))
    [
      ("/", []);
      ("/my", []);
      ("/issue/YUK-1", []);
      ("/issue/YUK-2", [ ("Yuka-Navigate", "L0") ]);
      ("/about", []);
      ("/new", []);
      ("/issue/NOPE", []);
    ]
