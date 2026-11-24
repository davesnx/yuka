open Async_feed_shared

let generated = Array.init Data.count (fun index -> Data.event (index + 1))
let simulated : Model.event list ref = ref []
let newest () = match !simulated with event :: _ -> event | [] -> generated.(Data.count - 1)
let newest_id () = (newest ()).id

let all () =
  Seq.append (List.to_seq !simulated) (Seq.init Data.count (fun index -> generated.(Data.count - 1 - index)))

type page = { events : Model.event list; total : int }

let page ~filter ~before ~limit =
  let older (event : Model.event) = match before with Some time -> event.time < time | None -> true in
  let matching = Seq.filter (Model.matches filter) (all ()) in
  let newest_first = List.of_seq (Seq.take limit (Seq.filter older matching)) in
  { events = List.rev newest_first; total = Seq.length matching }

let recent () = List.filteri (fun index _ -> index < Feed.kept) !simulated

let add ~now =
  let last = newest () in
  let event = { (Data.event (last.id + 1)) with time = max now (last.time + 1) } in
  simulated := List.filteri (fun index _ -> index < 1000) (event :: !simulated);
  event

let find id =
  if id >= 1 && id <= Data.count then Some generated.(id - 1)
  else List.find_opt (fun (event : Model.event) -> event.id = id) !simulated
