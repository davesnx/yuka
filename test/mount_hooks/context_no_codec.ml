open Dom

let plain : int Yuka.Context.t = Yuka.Context.make ~name:"plain" ()

let () =
  start_islands ();
  ignore (Yuka.Context.get plain);
  check "an island app with a context without a codec installs no page context code" "false"
    (string_of_bool (Yuka.Private.page_contexts ()));
  let (_ : int Yuka.Context.t) = Yuka.Context.make ~name:"coded" ~codec:Yuka.Codec.int () in
  check "a context with a codec installs it" "true" (string_of_bool (Yuka.Private.page_contexts ()));
  Yuka.stop ();
  finish "page context hooks"
