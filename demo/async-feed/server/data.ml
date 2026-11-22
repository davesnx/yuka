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
let percent n = 2 + (n mod 7)
let errors n = 40 + (n * 13 mod 400)
let failed n = n mod 9 = 0
let build_seconds n = 20 + (n mod 90)
let upvotes n = 5 + (n * 17 mod 300)
let replies n = n * 5 mod 60
let merged n = n mod 3 = 0
let pull n = 1000 + (n mod 4000)
let changed n = 1 + (n mod 24)
let reviewer n = pick people ((n * 5) + 1)

let time n = newest - ((count - n) * 600) + (n * 7919 mod 300)

let text n source =
  let person = pick people (n * 3) and subject = pick subjects (n * 7) in
  match source with
  | New_relic ->
      let service = pick services n in
      ( "New Relic",
        Printf.sprintf "Error rate above %d%% on %s" (percent n) service,
        Printf.sprintf "Policy \"Production errors\" opened incident #%d. %s served %d errors in the last 5 minutes."
          (10000 + n) service (errors n) )
  | Vercel ->
      let failed = failed n in
      ( person,
        Printf.sprintf "%s to production %s" (if failed then "Deployment failed" else "Deployed") (hash n),
        Printf.sprintf "Commit %s on main: %s. Built in %ds%s." (hash n) subject (build_seconds n)
          (if failed then ", the build step exited with code 1" else ", all checks passed") )
  | Figma ->
      let file = pick files n in
      ( person,
        Printf.sprintf "Commented on %s" file,
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
        Printf.sprintf "%d files changed, +%d -%d. Review requested from %s." (changed n) (n * 31 mod 900)
          (n * 7 mod 300) (reviewer n) )

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
  | Figma -> Printf.sprintf "https://www.figma.com/design/%s/%s?node-id=%d-%d" (hash (n * 7)) (slug '-' (pick files n)) (n mod 40) (n mod 900)
  | Reddit -> Printf.sprintf "https://www.reddit.com/r/acme/comments/%s/" (hash (n * 3))
  | Github -> Printf.sprintf "https://github.com/acme/%s/pull/%d" (slug '-' event.project) (pull n)

let details (event : Model.event) =
  let n = event.id in
  match event.source with
  | New_relic ->
      [
        ("Condition", Printf.sprintf "Error rate above %d%%" (percent n));
        ("Severity", if n mod 5 < 2 then "Critical" else "Warning");
        ("Entity", pick services n);
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
        ("File", pick files n);
        ("Page", pick [ "Flows"; "Components"; "Explorations"; "Handoff" ] n);
        ("Frame", Printf.sprintf "%s / Frame %d" (pick files (n + 2)) (1 + (n mod 12)));
        ("Thread", Printf.sprintf "%d replies" (n mod 4));
      ]
  | Reddit ->
      [
        ("Subreddit", "r/acme");
        ("Score", Int.to_string (upvotes n));
        ("Replies on Reddit", Int.to_string (replies n));
        ("Flair", pick [ "Feature request"; "Question"; "Feedback"; "Bug" ] n);
      ]
  | Github ->
      [
        ("Repository", "acme/" ^ slug '-' event.project);
        ("Pull request", Printf.sprintf "#%d" (pull n));
        ("State", if merged n then "Merged" else "Open");
        ("Files changed", Int.to_string (changed n));
        ("Diff", Printf.sprintf "+%d -%d" (n * 31 mod 900) (n * 7 mod 300));
        ("Reviewer", reviewer n);
      ]

let comment_texts = function
  | Model.New_relic ->
      [
        "Looking into it. Rolling back the last deploy of this service.";
        "Same spike on staging an hour ago, I think it is the new retry policy.";
        "Rollback done, the error rate is back under 1%.";
        "Opened a postmortem doc, please add your notes there.";
      ]
  | Vercel ->
      [
        "Checked the preview, the cart looks good on mobile.";
        "The build cache missed again, that is why it took this long.";
        "Can we promote this to the EU region too?";
        "Verified in production, closing the loop.";
      ]
  | Figma ->
      [
        "Agreed, the second frame uses 12px instead of 8px.";
        "Updated the tokens, can you check again?";
        "Let's keep this for the next design review.";
        "Looks aligned now, thanks!";
      ]
  | Reddit ->
      [
        "We should answer with the roadmap link.";
        "I replied from the company account.";
        "Support says three tickets ask the same thing this week.";
        "Adding this to the feedback board.";
      ]
  | Github ->
      [
        "Left two comments on the migration file.";
        "CI is green, approving.";
        "Can you split the refactor into its own PR?";
        "Merging after the release freeze.";
      ]

let comments (event : Model.event) : Model.comment list =
  let n = event.id in
  let count = if n mod 4 = 0 then 0 else 1 + (n * 7 mod 4) in
  List.init count (fun k ->
      {
        Model.author = pick people ((n * 3) + 1 + (k * 5));
        time = event.time + ((k + 1) * (120 + (n mod 7 * 60)));
        text = pick (comment_texts event.source) (n + k);
      })
