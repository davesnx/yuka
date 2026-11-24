open Async_feed_shared

let batch = 4
let pause = 0.7

let publish () = Yuka.Server.Live.publish Feed.recent () (Store.recent ())

let rec stream remaining =
  if remaining = 0 then Lwt.return batch
  else
    Lwt.bind (Lwt_unix.sleep pause) (fun () ->
        ignore (Store.add ~now:(int_of_float (Unix.gettimeofday ())));
        publish ();
        stream (remaining - 1))

let register () =
  Yuka.Server.Live.implement Feed.recent (fun () -> Yuka.Async.return (Store.recent ()));
  Yuka.Server.Action.implement Feed.simulate (fun _ () -> Yuka_dream.to_async (stream batch))
