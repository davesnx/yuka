type issue = {
  id : string;
  title : string;
  status : string;
  priority : string;
  assignee : string option;
  labels : string list;
}

let statuses = [| "Backlog"; "Todo"; "In progress"; "Done"; "Canceled" |]
let priorities = [| "No priority"; "Urgent"; "High"; "Medium"; "Low" |]
let users = [| "Maya Chen"; "Dev Patel"; "Sofia Rossi"; "Tomas Novak" |]

let issue i =
  {
    id = "YUK-" ^ string_of_int i;
    title = "Issue " ^ string_of_int i ^ ": fix \"quotes\" & <tags> in the list";
    status = statuses.(i mod 5);
    priority = priorities.(i mod 5);
    assignee = (if i mod 3 = 0 then None else Some users.(i mod 4));
    labels = (match i mod 3 with 0 -> [] | 1 -> [ "bug" ] | _ -> [ "bug"; "server" ]);
  }

let slug s = String.map (fun c -> if c = ' ' then '-' else Char.lowercase_ascii c) s
let issues n = List.init n (fun i -> issue (i + 1))

let args () =
  let port = ref 8200 and rows = ref 100 in
  Arg.parse
    [ ("--port", Arg.Set_int port, "Port"); ("--rows", Arg.Set_int rows, "Rows in the list") ]
    (fun _ -> ())
    "ssr bench server";
  (!port, issues !rows)
