let page k () =
  Yuka.element "ul" []
    (List.init 3 (fun j -> Yuka.element "li" [ Yuka.attr "class" "row" ] [ Yuka.text (Printf.sprintf "page %d, row %d & more" k j) ]))

let threads = 16
let rounds = 20_000

let () =
  let expected = Array.init threads (fun k -> Yuka.Server.to_string (page k)) in
  let wrong = Atomic.make 0 and overlaps = Atomic.make 0 in
  let worker k () =
    for _ = 1 to rounds do
      match Yuka.Server.to_string (page k) with
      | html -> if html <> expected.(k) then Atomic.incr wrong
      | exception Failure m when String.starts_with ~prefix:"Yuka.Server: two server renders overlapped" m ->
          Atomic.incr overlaps
    done
  in
  List.iter Thread.join (List.init threads (fun k -> Thread.create (worker k) ()));
  if Atomic.get wrong > 0 then begin
    Printf.printf "%d of %d renders got another thread's HTML\n" (Atomic.get wrong) (threads * rounds);
    exit 1
  end
  else
    Printf.printf "%d renders on %d threads, each its own HTML or an overlap error (%d)\n" (threads * rounds) threads
      (Atomic.get overlaps)
