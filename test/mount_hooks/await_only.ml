open Dom

let () =
  let async, resolve, _ = Yuka.Async.make () in
  let c, dispose =
    mount (fun () ->
        Yuka.Await.make ~async ~loading:(Yuka.text "wait") ~children:(fun v -> Yuka.text v) ())
  in
  check "Await shows loading" "<!--[-->wait<!--]-->" (html c);
  resolve "done";
  check "Await shows the value" "<!--[-->done<!--]-->" (html c);
  dispose ();
  finish "await hook"
