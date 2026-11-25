type id = int
type 'c t = { next : int; items : (int * 'c) list }

let empty = { next = 0; items = [] }
let add t c = ({ next = t.next + 1; items = t.items @ [ (t.next, c) ] }, t.next)
let remove t id = { t with items = List.filter (fun (i, _) -> i <> id) t.items }
let replace t id c = { t with items = List.map (fun (i, d) -> if i = id then (i, c) else (i, d)) t.items }
let apply f t base = List.fold_left (fun acc (_, c) -> f acc c) base t.items
let is_empty t = t.items = []

let status t (base : _ Status.t) : _ Status.t =
  if is_empty t then base
  else
    let f = apply (fun d f -> f d) t in
    match base with
    | Idle -> Idle
    | Loading d -> Loading (match d with Some d -> Some (f d) | None -> None)
    | Ready { data; stale } -> Ready { data = f data; stale }
    | Failed { error; last } -> Failed { error; last = (match last with Some l -> Some (f l) | None -> None) }

let make () =
  let base = State.make (Status.Loading None) and changes = State.make empty in
  (base, changes, State.memo (fun () -> status (State.get changes) (State.get base)))
