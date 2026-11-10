let page k () =
  Yuka.lower "ul" []
    (List.init 3 (fun j -> Yuka.lower "li" [ Yuka.attr "class" "row" ] [ Yuka.text (Printf.sprintf "page %d, row %d & more" k j) ]))

let threads = 16
let rounds = 20_000

let () =
  let expected = Array.init threads (fun k -> Yuka.Server.to_string (page k)) in
  let wrong = Atomic.make 0 in
  let worker k () =
    for _ = 1 to rounds do
      if Yuka.Server.to_string (page k) <> expected.(k) then Atomic.incr wrong
    done
  in
  List.iter Thread.join (List.init threads (fun k -> Thread.create (worker k) ()));
  if Atomic.get wrong > 0 then begin
    Printf.printf "%d of %d renders got another thread's HTML\n" (Atomic.get wrong) (threads * rounds);
    exit 1
  end
  else Printf.printf "%d renders on %d threads, each its own HTML\n" (threads * rounds) threads
