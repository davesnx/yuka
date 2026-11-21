type 'a t = { past : 'a list; future : 'a list }

let empty = { past = []; future = [] }
let rec take n = function [] -> [] | x :: rest -> if n <= 0 then [] else x :: take (n - 1) rest
let record ?(limit = 200) t ~before = { past = take limit (before :: t.past); future = [] }

let undo t ~current =
  match t.past with [] -> None | previous :: past -> Some ({ past; future = current :: t.future }, previous)

let redo t ~current =
  match t.future with [] -> None | next :: future -> Some ({ past = current :: t.past; future }, next)

let can_undo t = match t.past with [] -> false | _ -> true
let can_redo t = match t.future with [] -> false | _ -> true
