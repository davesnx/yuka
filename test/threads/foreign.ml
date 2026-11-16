open Yuka

let page () = element "p" [] [ text "B"; text "b" ]

let () =
  let html = ref "" and kept = ref false in
  let t =
    Thread.create
      (fun () ->
        let self = Obj.repr (Thread.self ()) in
        let foreign = Obj.repr (Array.make 8 (Obj.repr 42)) in
        Obj.set_field self 1 foreign;
        html := Server.to_string page;
        kept := Obj.field self 1 == foreign)
      ()
  in
  Thread.join t;
  if !html <> "<p>Bb</p>" then (Printf.printf "FAIL the render returned %S\n" !html; exit 1);
  if not !kept then (print_endline "FAIL the render replaced the thread's field 1"; exit 1);
  print_endline "foreign: a render on a thread whose Thread.t field 1 holds another library's slots returns its HTML"
