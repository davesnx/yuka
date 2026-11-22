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

let length text =
  let rec go index total =
    if index >= String.length text then total
    else go (index + Uchar.utf_decode_length (String.get_utf_8_uchar text index)) (total + 1)
  in
  go 0 0

let comment _ ({ item; text } : Feed.comment_input) =
  let text = String.trim text in
  match Store.find item with
  | None -> Yuka.Server.Action.reject "This notification does not exist."
  | Some _ when text = "" -> Yuka.Server.Action.reject "Write a comment first."
  | Some _ when length text > Feed.max_comment ->
      Yuka.Server.Action.reject (Printf.sprintf "A comment has at most %d characters." Feed.max_comment)
  | Some event ->
      Yuka.Async.return (Store.comment event ~author:"Ana Ruiz" ~now:(int_of_float (Unix.gettimeofday ())) text)

let register () =
  Yuka.Server.Action.implement Feed.comment comment;
  Yuka.Server.Live.implement Feed.recent (fun () -> Yuka.Async.return (Store.recent ()));
  Yuka.Server.Action.implement Feed.simulate (fun _ () -> Yuka_dream.to_async (stream batch))
