open Dom

let status a =
  match Yuka.Async.status a with
  | Yuka.Async.Pending -> "pending"
  | Done _ -> "done"
  | Failed m -> "failed " ^ m

let read () =
  match !Yuka.Private.async_source "a1" with
  | a -> status a
  | exception Failure m -> "raised " ^ m

let json : Yuka.Json.t Yuka.Codec.t = Yuka.Codec.make ~encode:(fun j -> j) ~decode:(fun j -> Ok j)

let decode () =
  match Yuka.Codec.decode (Yuka.Codec.async json) (`Assoc [ ("$async", `String "a1") ]) with
  | Ok a -> status a
  | Error m -> "error " ^ m

let () =
  check "before render ~islands: the default" "failed no async transport" (read ());
  start_islands ();
  check "after render ~islands, before a Codec.async reference: raises"
    "raised Yuka: no reader for async value a1: Codec.async did not call Client.use_async" (read ());
  check "a Codec.async reference waits for the page" "pending" (decode ());
  check "after it: the page reader" "pending" (read ());
  Yuka.stop ();
  finish "async reader hook"
