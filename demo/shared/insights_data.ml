open Model

type item = {
  key : string;
  status : Issue.status;
  priority : Issue.priority;
  labels : string list;
  assignee : string;
  day : int;
  points : int;
  cycle : int;
  offset : int;
}

type measure = Count | Points

let statuses = Issue.[ Backlog; Todo; In_progress; Done; Canceled ]
let priorities = Issue.[ Urgent; High; Medium; Low; No_priority ]
let multipliers = [ 1; 10; 100 ]
let unassigned = "Unassigned"
let months = [| "Jan"; "Feb"; "Mar"; "Apr"; "May"; "Jun"; "Jul"; "Aug"; "Sep"; "Oct"; "Nov"; "Dec" |]
let month_lengths = [| 31; 28; 31; 30; 31; 30; 31; 31; 30; 31; 30; 31 |]

let month_start month =
  let rec sum index total = if index >= month then total else sum (index + 1) (total + month_lengths.(index)) in
  sum 0 0

let day_of_date text =
  match String.split_on_char ' ' text with
  | [ month; day ] -> (
      let rec find index = if index >= Array.length months then None else if months.(index) = month then Some index else find (index + 1) in
      match (find 0, int_of_string_opt day) with Some month, Some day -> month_start month + day - 1 | _ -> 0)
  | _ -> 0

let date_of_day day =
  let rec find month = if month < 11 && day >= month_start (month + 1) then find (month + 1) else month in
  let month = find 0 in
  months.(month) ^ " " ^ Int.to_string (day - month_start month + 1)

let hash value =
  let first = ((value * 7919) + 104729) mod 65521 in
  ((first * 2477) + 3) mod 65521

let story_points = [| 1; 2; 3; 5; 8 |]

let assignee_name (user : User.t option) = match user with Some user -> user.name | None -> unassigned

let expand ~multiplier (issues : Issue.t list) =
  let base = Array.of_list issues in
  let count = Array.length base in
  List.init (count * multiplier) (fun index ->
      let copy = index / count and position = index mod count in
      let issue = base.(position) in
      let pick step = base.((position + (copy * step)) mod count) in
      let seed = Issue.number issue + (copy * 1009) in
      let mixed = hash seed in
      {
        key = (if copy = 0 then issue.id else issue.id ^ "." ^ Int.to_string copy);
        status = (pick 7).status;
        priority = (pick 13).priority;
        labels = issue.labels;
        assignee = assignee_name (pick 3).assignee;
        day = (day_of_date issue.created_at + if copy = 0 then 0 else (mixed mod 7) - 3);
        points = story_points.(mixed mod Array.length story_points);
        cycle = 1 + (hash (seed + 50021) mod 30);
        offset = mixed mod 100;
      })

let value measure item = match measure with Count -> 1 | Points -> item.points

let keeps chosen value = chosen = [] || List.mem value chosen
let keeps_any chosen values = chosen = [] || List.exists (fun value -> List.mem value chosen) values

let toggle value chosen = if List.mem value chosen then List.filter (( <> ) value) chosen else chosen @ [ value ]

let index_of value values =
  let rec go index = function [] -> -1 | head :: rest -> if head = value then index else go (index + 1) rest in
  go 0 values

let totals ~measure ~categories ~category items =
  let sums = Array.make (List.length categories) 0 in
  List.iter
    (fun item ->
      let index = index_of (category item) categories in
      if index >= 0 then sums.(index) <- sums.(index) + value measure item)
    items;
  sums

let label_totals ~measure ~labels items =
  let table = Hashtbl.create 64 in
  List.iteri (fun index label -> Hashtbl.replace table label index) labels;
  let sums = Array.make (List.length labels) 0 in
  List.iter
    (fun item ->
      List.iter
        (fun label ->
          match Hashtbl.find_opt table label with
          | Some index -> sums.(index) <- sums.(index) + value measure item
          | None -> ())
        item.labels)
    items;
  sums

let grid ~measure ~rows ~row ~columns ~column items =
  let cells = Array.make_matrix (List.length rows) (List.length columns) 0 in
  List.iter
    (fun item ->
      let row_index = index_of (row item) rows and column_index = index_of (column item) columns in
      if row_index >= 0 && column_index >= 0 then
        cells.(row_index).(column_index) <- cells.(row_index).(column_index) + value measure item)
    items;
  cells

let days ~measure ~first ~last items =
  let sums = Array.make (max 1 (last - first + 1)) 0 in
  List.iter
    (fun item -> if item.day >= first && item.day <= last then sums.(item.day - first) <- sums.(item.day - first) + value measure item)
    items;
  sums

let nice_step value =
  let rec go power =
    if power >= value then power
    else if 2 * power >= value then 2 * power
    else if 5 * power >= value then 5 * power
    else go (power * 10)
  in
  go 1

let ticks ~count highest =
  let step = nice_step (max 1 ((highest + count - 1) / count)) in
  let top = step * max 1 ((highest + step - 1) / step) in
  List.init ((top / step) + 1) (fun index -> index * step)

let scale ~highest ~length value = if highest <= 0 then 0 else value * length / highest

let format_int number =
  let digits = Int.to_string (abs number) in
  let length = String.length digits in
  let buffer = Buffer.create (length + 4) in
  if number < 0 then Buffer.add_char buffer '-';
  String.iteri
    (fun index digit ->
      if index > 0 && (length - index) mod 3 = 0 then Buffer.add_char buffer ',';
      Buffer.add_char buffer digit)
    digits;
  Buffer.contents buffer

let format_tenths tenths = Int.to_string (tenths / 10) ^ "." ^ Int.to_string (tenths mod 10)
