open Yuka
module Messages = I18n_shared.Messages

let check = Cases.check
let view () = element "p" [] [ text (Messages.hello (Messages.current ()) ~name:"island") ]
let entry = runtime_entry ~name:"Greeting" (fun _ -> Ok view)
let island () = runtime_island ~name:"Greeting" ~props:`Null view

let locale () =
  let c =
    Island_cases.setup_page
      (Island_cases.page [ Context.provide Messages.context Messages.Es (fun () -> island ()); island () ])
  in
  Dom_cases.capture_warnings ();
  Island_cases.capture_errors ();
  Island_cases.start_islands [ entry ];
  check "no hydration mismatch" "" (Dom_cases.warnings ());
  check "no error" "" (Island_cases.errors ());
  check "the island under the provider reads es; the other reads the base locale" {js|¡Hola, island!,Hello, island!|js}
    (Dom_cases.texts c "p");
  Island_cases.reset_body ()

let all = [ ("i18n: islands read the locale of the page", locale) ]
