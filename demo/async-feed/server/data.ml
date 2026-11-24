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

let slug sep text = String.lowercase_ascii (String.map (fun c -> if c = ' ' then sep else c) text)
let service n = pick services n
let file n = pick files n
let subject n = pick subjects (n * 7)
let percent n = 2 + (n mod 7)
let errors n = 40 + (n * 13 mod 400)
let failed n = n mod 9 = 0
let build_seconds n = 20 + (n mod 90)
let upvotes n = 5 + (n * 17 mod 300)
let replies n = n * 5 mod 60
let merged n = n mod 3 = 0
let pull n = 1000 + (n mod 4000)
let changed n = 1 + (n mod 24)
let additions n = n * 31 mod 900
let deletions n = n * 7 mod 300
let reviewer n = pick people ((n * 5) + 1)
let flair n = pick [ "Feature request"; "Question"; "Feedback"; "Bug" ] n
let figma_page n = pick [ "Flows"; "Components"; "Explorations"; "Handoff" ] n
let figma_frame n = Printf.sprintf "%s / Frame %d" (pick files (n + 2)) (1 + (n mod 12))

let time n = newest - ((count - n) * 5400) + (n * 7919 mod 300)

let text n source =
  let person = pick people (n * 3) and subject = subject n in
  match source with
  | New_relic ->
      let svc = service n in
      ( "New Relic",
        Printf.sprintf "Error rate above %d%% on %s" (percent n) svc,
        Printf.sprintf "Policy \"Production errors\" opened incident #%d. %s served %d errors in the last 5 minutes."
          (10000 + n) svc (errors n) )
  | Vercel ->
      let failed = failed n in
      ( person,
        Printf.sprintf "%s to production %s" (if failed then "Deployment failed" else "Deployed") (hash n),
        Printf.sprintf "Commit %s on main: %s. Built in %ds%s." (hash n) subject (build_seconds n)
          (if failed then ", the build step exited with code 1" else ", all checks passed") )
  | Figma ->
      let fl = file n in
      ( person,
        Printf.sprintf "Commented on %s" fl,
        Printf.sprintf "\"Can we align the spacing of the %s with the 8px grid? The second frame looks off.\""
          (String.lowercase_ascii (pick files (n + 2))) )
  | Reddit ->
      ( Printf.sprintf "u/%s" (slug '_' person),
        Printf.sprintf "New post in r/acme: %s?" subject,
        Printf.sprintf "%d upvotes and %d comments in the first hour. Top comment asks for an ETA." (upvotes n)
          (replies n) )
  | Github ->
      ( person,
        Printf.sprintf "%s pull request #%d: %s" (if merged n then "Merged" else "Opened") (pull n) subject,
        Printf.sprintf "%d files changed, +%d -%d. Review requested from %s." (changed n) (additions n) (deletions n)
          (reviewer n) )

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

let link (event : Model.event) =
  let n = event.id in
  match event.source with
  | New_relic -> Printf.sprintf "https://one.newrelic.com/alerts-ai/incidents/%d" (10000 + n)
  | Vercel -> Printf.sprintf "https://vercel.com/acme/%s/deployments/dpl_%s" (slug '-' event.project) (hash n)
  | Figma -> Printf.sprintf "https://www.figma.com/design/%s/%s?node-id=%d-%d" (hash (n * 7)) (slug '-' (file n)) (n mod 40) (n mod 900)
  | Reddit -> Printf.sprintf "https://www.reddit.com/r/acme/comments/%s/" (hash (n * 3))
  | Github -> Printf.sprintf "https://github.com/acme/%s/pull/%d" (slug '-' event.project) (pull n)

let notes (event : Model.event) =
  let n = event.id in
  match event.source with
  | New_relic ->
      [
        ("Impact", Printf.sprintf "Elevated 5xx responses affecting %s in us-east-1 and eu-central-1." (service n));
        ("Runbook", Printf.sprintf "Check recent deploys on %s, inspect upstream queue depth, and verify circuit breaker state." (service n));
      ]
  | Vercel ->
      [
        ("Commit summary", Printf.sprintf "%s (%s on main)." (subject n) (hash n));
        ("Regions", "iad1 (primary), fra1, hnd1, sfo1 — automatic edge propagation.");
      ]
  | Figma ->
      [
        ("Frame context", Printf.sprintf "%s · %s (%d active collaborators)." (figma_page n) (figma_frame n) (2 + (n mod 5)));
        ("Spec note", "Components use 8px base spacing tokens; verify auto-layout padding on mobile breakpoints.");
      ]
  | Reddit ->
      [
        ("Community signal", Printf.sprintf "Flair \"%s\" trending in r/acme with %d%% upvote ratio." (flair n) (84 + (n * 3 mod 15)));
        ("Suggested action", "Share current milestone status and link the public changelog entry.");
      ]
  | Github ->
      [
        ("Summary", Printf.sprintf "%s across %d files in acme/%s." (subject n) (changed n) (slug '-' event.project));
        ("Checks", if merged n then "All 4 required workflows passed before merge." else "CI checks green; awaiting final approval.");
      ]

let details (event : Model.event) =
  let n = event.id in
  match event.source with
  | New_relic ->
      [
        ("Condition", Printf.sprintf "Error rate above %d%%" (percent n));
        ("Severity", if n mod 5 < 2 then "Critical" else "Warning");
        ("Entity", service n);
        ("Policy", "Production errors");
        ("Incident", Printf.sprintf "#%d" (10000 + n));
        ("Duration", Printf.sprintf "%d min" (5 + (n * 11 mod 55)));
        ("Errors", Printf.sprintf "%d in 5 min" (errors n));
      ]
  | Vercel ->
      [
        ("Project", "acme-" ^ slug '-' event.project);
        ("Environment", "Production");
        ("Branch", "main");
        ("Commit", hash n);
        ("Status", if failed n then "Error" else "Ready");
        ("Build", Printf.sprintf "%ds" (build_seconds n));
        ("URL", Printf.sprintf "acme-%s-%s.vercel.app" (slug '-' event.project) (hash n));
      ]
  | Figma ->
      [
        ("File", file n);
        ("Page", figma_page n);
        ("Frame", figma_frame n);
        ("Thread", Printf.sprintf "%d replies" (n mod 4));
      ]
  | Reddit ->
      [
        ("Subreddit", "r/acme");
        ("Score", Int.to_string (upvotes n));
        ("Replies on Reddit", Int.to_string (replies n));
        ("Flair", flair n);
      ]
  | Github ->
      [
        ("Repository", "acme/" ^ slug '-' event.project);
        ("Pull request", Printf.sprintf "#%d" (pull n));
        ("State", if merged n then "Merged" else "Open");
        ("Files changed", Int.to_string (changed n));
        ("Diff", Printf.sprintf "+%d -%d" (additions n) (deletions n));
        ("Reviewer", reviewer n);
      ]
