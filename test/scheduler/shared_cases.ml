open Yuka

let check = Cases.check

let theme : string Context.t = Context.make ~name:"theme" ~codec:Codec.string ()
let user : int Context.t = Context.make ~name:"user" ~codec:Codec.int ()
let plain : int Context.t = Context.make ~name:"plain" ()
let show c = match Context.get c with Some v -> v | None -> "none"
let island ?(name = "I") body = runtime_island ~name ~props:`Null body
let quiet () = island (fun () -> empty)
let session ?(streaming = false) () = Private.session ~streaming ~islands_only:true
let print ?(s = session ()) build = Private.print s (fun () -> Private.node (build ()))

let count html part =
  let n = String.length part in
  let rec go i acc =
    if i + n > String.length html then acc else go (i + 1) (if String.sub html i n = part then acc + 1 else acc)
  in
  go 0 0

let index html part =
  let n = String.length part in
  let rec go i = if i + n > String.length html then -1 else if String.sub html i n = part then i else go (i + 1) in
  go 0

let script id name json = {|<script type="application/json" data-yuka-context="|} ^ id ^ {|" data-name="|} ^ name ^ {|">|} ^ json ^ "</script>"
let ints = string_of_int

let two_islands () =
  let html = print (fun () -> Context.provide theme "dark" (fun () -> fragment [ quiet (); quiet () ])) in
  check "two islands under one provider: one script, the same id"
    ({|<yuka-island data-name="I" data-id="i1" style="display:contents" data-ctx="theme=c1"></yuka-island>|}
    ^ script "c1" "theme" {|"dark"|}
    ^ {|<script type="application/json" data-yuka-props="i1">null</script>|}
    ^ {|<yuka-island data-name="I" data-id="i2" style="display:contents" data-ctx="theme=c1"></yuka-island>|}
    ^ {|<script type="application/json" data-yuka-props="i2">null</script>|})
    html

let nested () =
  let html =
    print (fun () ->
        Context.provide theme "a" (fun () ->
            fragment
              [ island ~name:"A" (fun () -> empty);
                Context.provide theme "b" (fun () -> island ~name:"B" (fun () -> empty));
                island ~name:"C" (fun () -> empty) ]))
  in
  check "the inner island reads the inner provider, the others the outer one"
    "theme=c1 theme=c2 theme=c1"
    (String.concat " "
       (List.map
          (fun name ->
            let i = index html ({|data-name="|} ^ name ^ {|"|}) in
            let rest = String.sub html i (String.length html - i) in
            let a = index rest {|data-ctx="|} + 10 in
            String.sub rest a (String.index_from rest a '"' - a))
          [ "A"; "B"; "C" ]));
  check "two scripts" "2" (ints (count html "data-yuka-context="));
  check "the values" "true"
    (string_of_bool (Cases.contains html (script "c1" "theme" {|"a"|}) && Cases.contains html (script "c2" "theme" {|"b"|})))

let rebind () =
  let html =
    print (fun () ->
        Context.provide theme "a" (fun () -> Context.provide user 7 (fun () -> Context.provide theme "b" quiet)))
  in
  check "the nearest provider per name, nearest first" "true" (string_of_bool (Cases.contains html {|data-ctx="theme=c1 user=c2"|}));
  check "the hidden provider is not written" "false" (string_of_bool (Cases.contains html {|"a"|}));
  check "two scripts" "true"
    (string_of_bool (Cases.contains html (script "c1" "theme" {|"b"|} ^ script "c2" "user" "7")))

let no_codec () =
  let html = print (fun () -> Context.provide plain 1 (fun () -> island (fun () -> text (match Context.get plain with Some n -> ints n | None -> "none")))) in
  check "a context without a codec: no attribute, no script, None in the island"
    {|<yuka-island data-name="I" data-id="i1" style="display:contents">none</yuka-island><script type="application/json" data-yuka-props="i1">null</script>|}
    html;
  check "no island, no script" "<p>x</p>" (print (fun () -> Context.provide theme "dark" (fun () -> element "p" [] [ text "x" ])))

let server_get () =
  let html =
    print (fun () ->
        Context.provide theme "dark" (fun () ->
            island (fun () -> fragment [ text (show theme); hole (fun _ -> text (" " ^ show theme)) ])))
  in
  check "an island render reads the page value of a context with a codec" "true"
    (string_of_bool (Cases.contains html "dark<!--[--> dark<!--]-->"));
  check "no provider: None" "none" (show theme);
  check "get_exn names the context" "Yuka.Context.get_exn: no value for theme"
    (match Context.get_exn theme with _ -> "no exception" | exception Invalid_argument m -> m)

let fills s =
  List.filter_map
    (function Private.Pending_await { fill; _ } -> Some fill | _ -> None)
    (Private.take_pending s)

let streamed () =
  let a, resolve, _ = Async.make () in
  let s = session ~streaming:true () in
  let shell =
    print ~s (fun () ->
        Context.provide theme "dark" (fun () ->
            fragment
              [ quiet ();
                Await.make ~async:a ~loading:(text "L") ~children:(fun () -> quiet ()) ();
                Context.provide user 3 (fun () ->
                    Await.make ~async:a ~loading:(text "L") ~children:(fun () -> quiet ()) ()) ]))
  in
  check "the shell has the script of its island only" "1" (ints (count shell "data-yuka-context="));
  match fills s with
  | [ first; second ] ->
      resolve ();
      let second = second () and first = first () in
      check "a fill under a provider of the shell: no second copy" "0" (ints (count first "data-yuka-context="));
      check "its island lists the shell's id" "true" (string_of_bool (Cases.contains first {|data-ctx="theme=c1"|}));
      check "a provider whose first island is in a fill: the script is in the fill, before the props" "true"
        (string_of_bool
           (Cases.contains second {|data-ctx="user=c2 theme=c1"|}
           && index second (script "c2" "user" "3") >= 0
           && index second (script "c2" "user" "3") < index second "data-yuka-props"))
  | l -> raise (Cases.Failed ("pending awaits: " ^ ints (List.length l)))

let catch () =
  let html =
    print (fun () ->
        Context.provide theme "dark" (fun () ->
            fragment
              [ Catch.make
                  ~fallback:(fun ~error:_ ~reset:_ -> text "lost")
                  ~children:(fun () -> fragment [ quiet (); Private.element (Private.hole (fun _ -> failwith "x")) ])
                  ();
                quiet () ]))
  in
  check "an island in a failed Catch leaves no script; the next island writes it with the same id" "1 true"
    (ints (count html "data-yuka-context=") ^ " " ^ string_of_bool (Cases.contains html (script "c1" "theme" {|"dark"|})))

let escaped () =
  let html = print (fun () -> Context.provide theme "</script><!--\xe2\x80\xa8" (fun () -> quiet ())) in
  check "the value cannot close the script" "true"
    (string_of_bool (Cases.contains html {|data-name="theme">"\u003c/script>\u003c!--|} && count html "</script>" = 2))

let slot () =
  let html =
    print (fun () ->
        Context.provide theme "page" (fun () ->
            island ~name:"Outer" (fun () ->
                Context.provide theme "inner" (fun () ->
                    runtime_slot (Some (island ~name:"Inner" (fun () -> empty)))))))
  in
  check "an island in slot content has the page scope" "true"
    (string_of_bool (Cases.contains html (script "c1" "theme" {|"page"|}) && count html {|data-ctx="theme=c1"|} = 2))

let names () =
  let refused name =
    match (Context.make ?name ~codec:Codec.int () : int Context.t) with
    | _ -> "made"
    | exception Invalid_argument m -> m
  in
  check "a codec with no name is refused"
    "Yuka.Context.make: a context with a codec needs a ~name of a-z, 0-9, '.', '_' and '-', got no name" (refused None);
  check "a name with another character is refused"
    {|Yuka.Context.make: a context with a codec needs a ~name of a-z, 0-9, '.', '_' and '-', got a=b|}
    (refused (Some "a=b"));
  check "a valid name" "made" (refused (Some "app.theme_2-x"))

let state_codec () =
  let st : string State.read Context.t = Context.make ~name:"st" ~codec:(Codec.state Codec.string) () in
  let html = print (fun () -> Context.provide st (State.read_only (State.make "v")) (fun () -> quiet ())) in
  check "Codec.state writes the value of the State" "true" (string_of_bool (Cases.contains html (script "c1" "st" {|"v"|})));
  match Codec.decode (Codec.state Codec.string) (`String "w") with
  | Ok s -> check "Codec.state decodes to a State" "w" (State.peek s)
  | Error m -> raise (Cases.Failed m)

let all =
  [
    ("shared context: two islands, one script", two_islands);
    ("shared context: nested providers", nested);
    ("shared context: a rebind hides the outer provider", rebind);
    ("shared context: a context without a codec", no_codec);
    ("shared context: server get in an island", server_get);
    ("shared context: streamed fills", streamed);
    ("shared context: Catch", catch);
    ("shared context: escaping", escaped);
    ("shared context: slot content", slot);
    ("shared context: names", names);
    ("shared context: Codec.state", state_codec);
  ]
