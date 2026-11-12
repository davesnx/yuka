open Dom

let status a =
  match Yuka.Async.status a with
  | Yuka.Async.Pending -> "pending"
  | Done _ -> "done"
  | Failed m -> "failed " ^ m

let call () =
  match !Yuka.Private.call_action "double" (`Int 1) with
  | a -> status a
  | exception Failure m -> "raised " ^ m

let double = Yuka.Action.declare ~name:"double" ~input:Yuka.Codec.int ~output:Yuka.Codec.int

let () =
  stub_fetch ();
  check "before render ~islands: the default" "failed no action transport" (call ());
  start_islands ();
  check "after render ~islands, before Action.call: raises"
    "raised Yuka: no action transport for double: Action.send did not call Client.use_actions" (call ());
  check "Action.call sends" "pending" (status (Yuka.Action.call double 1));
  check "after Action.call: the browser transport" "pending" (call ());
  Yuka.unmount ();
  finish "action transport hook"
