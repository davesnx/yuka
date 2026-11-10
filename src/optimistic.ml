type id = int
type 'c t = { next : int; items : (int * 'c) list }

let empty = { next = 0; items = [] }
let add t c = ({ next = t.next + 1; items = t.items @ [ (t.next, c) ] }, t.next)
let remove t id = { t with items = List.filter (fun (i, _) -> i <> id) t.items }
let apply f t base = List.fold_left (fun acc (_, c) -> f acc c) base t.items
let is_empty t = t.items = []
