open Yuka

let check = Cases.check
let ints = string_of_int
let decodes = ref 0

let counted =
  Codec.make ~encode:(Codec.encode Codec.string) ~decode:(fun j ->
      incr decodes;
      Codec.decode Codec.string j)

let theme : string State.read Context.t = Context.make ~name:"t.theme" ~codec:(Codec.state counted) ()
let label : int Context.t = Context.make ~name:"t.label" ~codec:Codec.int ()
let plain : int Context.t = Context.make ~name:"plain" ()
let seen = ref []

let view () =
  let st = Context.get theme in
  Option.iter (fun s -> seen := s :: !seen) st;
  let n = match (Context.get label, Context.get plain) with Some n, None -> ints n | _, Some _ -> "plain" | None, None -> "none" in
  element "p" [] [ text n; hole (fun () -> text (match st with Some s -> " " ^ State.get s | None -> " none")) ]

let entry = runtime_entry ~name:"Th" (fun _ -> Ok view)
let island () = runtime_island ~name:"Th" ~props:`Null view

let page v =
  Island_cases.page
    [ Context.provide plain 1 (fun () ->
          Context.provide label 4 (fun () ->
              Context.provide theme (State.read_only (State.make v)) (fun () -> fragment [ island (); island () ])));
      island () ]

let start c =
  decodes := 0;
  seen := [];
  check "no decode before the first read" "0" (ints !decodes);
  Dom_cases.capture_warnings ();
  Island_cases.capture_errors ();
  Island_cases.start_islands [ entry ];
  check "no hydration mismatch" "" (Dom_cases.warnings ());
  check "no error" "" (Island_cases.errors ());
  c

let shared () =
  let c = start (Island_cases.setup_page (page "dark")) in
  check "the islands show the server values; the island outside the provider reads None" "4 dark,4 dark,none none"
    (Dom_cases.texts c "p");
  check "one decode for two islands" "1" (ints !decodes);
  (match !seen with
  | [ a; b ] -> check "two islands under one provider get one State" "true" (string_of_bool (a == b))
  | l -> check "States read" "2" (ints (List.length l)));
  Island_cases.reset_body ()

let restart () =
  ignore (start (Island_cases.setup_page (page "dark")));
  let c = start (Island_cases.setup_page (page "light")) in
  check "after stop, a new page with the same ids decodes its own value" "4 light,4 light,none none" (Dom_cases.texts c "p");
  Island_cases.reset_body ()

let bad_json () =
  let c =
    Dom_cases.container
      ({|<yuka-island data-name="Th" data-id="i1" data-ctx="t.label=c1" style="display:contents"><p>none none</p></yuka-island>|}
      ^ {|<script type="application/json" data-yuka-context="c1" data-name="t.label">"x"</script><script type="application/json" data-yuka-props="i1">null</script>|})
  in
  Island_cases.capture_errors ();
  Island_cases.start_islands [ entry ];
  check "a value that does not decode: None and one error" "none none" (Dom_cases.texts c "p");
  check "the error names the context and the id" "true"
    (string_of_bool (Cases.contains (Island_cases.errors ()) "context t.label (c1)"));
  Island_cases.reset_body ()

let all =
  [ ("shared context: two islands share one State, hydration, lazy decode", shared);
    ("shared context: stop clears the page values", restart);
    ("shared context: a value that does not decode", bad_json) ]
