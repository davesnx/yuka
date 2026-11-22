open Async_feed_shared
open Model

let count = 5000
let newest = 1795165200
let pick values n = List.nth values (n mod List.length values)
let services = [ "checkout-api"; "search-indexer"; "billing-worker"; "web-frontend"; "auth-gateway"; "image-proxy" ]

let subjects =
  [
    "Retry failed webhooks with backoff"; "Move the cart to server components"; "Cache search facets";
    "New onboarding checklist"; "Dark mode for the dashboard"; "Faster invoice export";
    "Drop the legacy session store"; "Keyboard shortcuts in the editor"; "Pricing page refresh";
    "Fix flaky checkout test";
  ]

let files = [ "Checkout flow v3"; "Design system tokens"; "Mobile nav"; "Billing settings"; "Empty states" ]
let hash n = Printf.sprintf "%07x" (n * 2654435761 land 0xfffffff)

let time n = newest - ((count - n) * 600) + (n * 7919 mod 300)

let text n source =
  let person = pick people (n * 3) and subject = pick subjects (n * 7) in
  match source with
  | New_relic ->
      let service = pick services n in
      ( "New Relic",
        Printf.sprintf "Error rate above %d%% on %s" (2 + (n mod 7)) service,
        Printf.sprintf "Policy \"Production errors\" opened incident #%d. %s served %d errors in the last 5 minutes."
          (10000 + n) service (40 + (n * 13 mod 400)) )
  | Vercel ->
      let failed = n mod 9 = 0 in
      ( person,
        Printf.sprintf "%s to production %s" (if failed then "Deployment failed" else "Deployed") (hash n),
        Printf.sprintf "Commit %s on main: %s. Built in %ds%s." (hash n) subject (20 + (n mod 90))
          (if failed then ", the build step exited with code 1" else ", all checks passed") )
  | Figma ->
      let file = pick files n in
      ( person,
        Printf.sprintf "Commented on %s" file,
        Printf.sprintf "\"Can we align the spacing of the %s with the 8px grid? The second frame looks off.\""
          (String.lowercase_ascii (pick files (n + 2))) )
  | Reddit ->
      ( Printf.sprintf "u/%s" (String.lowercase_ascii (String.map (fun c -> if c = ' ' then '_' else c) person)),
        Printf.sprintf "New post in r/acme: %s?" subject,
        Printf.sprintf "%d upvotes and %d comments in the first hour. Top comment asks for an ETA." (5 + (n * 17 mod 300))
          (n * 5 mod 60) )
  | Github ->
      let merged = n mod 3 = 0 in
      ( person,
        Printf.sprintf "%s pull request #%d: %s" (if merged then "Merged" else "Opened") (1000 + (n mod 4000)) subject,
        Printf.sprintf "%d files changed, +%d -%d. Review requested from %s." (1 + (n mod 24)) (n * 31 mod 900)
          (n * 7 mod 300) (pick people (n * 5 + 1)) )

let event n =
  let source = pick [ New_relic; Vercel; Figma; Reddit; Github ] (n * 3 mod 5 + (n / 5) mod 2) in
  let author, title, description = text n source in
  {
    id = n;
    time = time n;
    source;
    author;
    title;
    description;
    project = pick projects (n * 5);
    team = pick teams (n * 3 + 1);
    assignee = pick people (n * 7 + 2);
  }
