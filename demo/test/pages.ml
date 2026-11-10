open Demo_app

let config =
  Yuka.Server.config
    ~assets:(Yuka.Server.modules ~dir:"js" ~entry:"demo/client/main.js" ~manifest:"{}" ~packages:[] ~digest:"")
    ~public:[ ("/static", "static") ]
    ~styles:[ "/static/style.css" ] ~css:Yuka_css.sheets ()

let handler = Dream.set_secret "test" @@ Dream.cookie_sessions @@ Yuka_dream.handler config Routes_server.app

let mask text =
  let marker = {|data-yuka-answer="l:csrf">{"ok":"|} in
  let n = String.length marker in
  let b = Buffer.create (String.length text) in
  let rec go i =
    if i + n > String.length text then Buffer.add_string b (String.sub text i (String.length text - i))
    else if String.sub text i n = marker then begin
      Buffer.add_string b marker;
      Buffer.add_string b "TOKEN";
      go (String.index_from text (i + n) '"')
    end
    else begin
      Buffer.add_char b text.[i];
      go (i + 1)
    end
  in
  go 0;
  Buffer.contents b

let () =
  Handlers.register ();
  List.iter
    (fun (target, headers) ->
      let response = Dream.test handler (Dream.request ~target ~headers "") in
      Printf.printf "==== %s %d\n%s\n" target
        (Dream.status_to_int (Dream.status response))
        (mask (Lwt_main.run (Dream.body response))))
    [
      ("/", []);
      ("/my", []);
      ("/issue/YUK-1", []);
      ("/issue/YUK-2", [ ("Yuka-Navigate", "L0") ]);
      ("/about", []);
      ("/new", []);
      ("/issue/NOPE", []);
    ]
