open Demo_shared

let topic = Yuka.Topic.declare ~name:"bench" ~key:Yuka.Codec.int ~state:(Yuka.Codec.list Model.Issue.codec)
let () = Yuka.Server.Live.serve topic (fun _ -> Yuka.Async.return [])

let issues n =
  let seed = Array.of_list Demo_app.Store.seed in
  List.init n (fun i ->
      let base = seed.(i mod Array.length seed) in
      { base with Model.Issue.id = Printf.sprintf "YUK-%d" (i + 1) })

let connect key bytes =
  let pending = ref [ {|{"t":"hello","v":1,"csrf":""}|}; Printf.sprintf {|{"t":"sub","id":1,"topic":"bench","key":%d}|} key ] in
  let connection =
    Yuka.Server.Live.connection
      ~send:(fun text ->
        bytes := !bytes + String.length text;
        Yuka.Async.return ())
      ~receive:(fun () ->
        match !pending with
        | x :: rest ->
            pending := rest;
            Yuka.Async.return (Some x)
        | [] ->
            let a, _, _ = Yuka.Async.make () in
            a)
      ~close:(fun _ -> Yuka.Async.return ())
  in
  let never _ =
    let a, _, _ = Yuka.Async.make () in
    a
  in
  ignore
    (Yuka.Server.Testing.live_run ~sleep:never
       (Yuka.Server.Testing.context ~session:"bench" ())
       ~verify_csrf:(fun _ -> Yuka.Async.return true)
       ~token:(fun () -> "t") connection)

let () =
  Yuka.Server.Testing.set_log (fun _ _ -> ());
  List.iter
    (fun n ->
      let key = n in
      let bytes = ref 0 in
      for _ = 1 to 100 do
        connect key bytes
      done;
      let state = issues n in
      bytes := 0;
      let runs = 20 in
      let encode_start = Unix.gettimeofday () in
      for _ = 1 to runs do
        ignore (Yuka.Json.to_string ((Yuka.Codec.list Model.Issue.codec).encode state))
      done;
      let encode_ms = (Unix.gettimeofday () -. encode_start) *. 1000. /. float_of_int runs in
      let start = Unix.gettimeofday () in
      for _ = 1 to runs do
        Yuka.Server.Live.publish topic key state
      done;
      let publish_ms = (Unix.gettimeofday () -. start) *. 1000. /. float_of_int runs in
      Printf.printf "%5d issues: %8d bytes per message, encode %6.2f ms, publish to 100 sockets %6.2f ms\n" n
        (!bytes / runs / 100) encode_ms publish_ms)
    [ 25; 500; 5000 ]
