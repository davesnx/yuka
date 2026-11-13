open Demo_shared.Model

let issue_count = 200
let comments_per_issue = 200

let labels =
  [|
    "bug"; "feature"; "docs"; "design"; "perf"; "server"; "client"; "codec"; "router"; "ppx";
    "forms"; "live"; "streaming"; "hydration"; "css"; "a11y"; "security"; "testing"; "ci"; "build";
    "dx"; "api"; "mobile"; "i18n"; "cache"; "infra"; "regression"; "refactor"; "good-first-issue"; "needs-triage";
  |]

let verbs =
  [| "Fix"; "Investigate"; "Add tests for"; "Speed up"; "Document"; "Refactor"; "Simplify"; "Measure"; "Clean up"; "Rethink" |]

let subjects =
  [|
    "hydration of nested holes"; "the router cache"; "keyed list moves"; "streaming of comments";
    "the form error summary"; "live updates after a reconnect"; "the island manifest";
    "label colors in dark mode"; "the status menu"; "keyboard focus in dialogs"; "CSS module hashes";
    "the action transport"; "prefetch on hover"; "errors sent by the server"; "the bundle size budget";
    "date formatting"; "the comment editor"; "optimistic updates"; "the not found page"; "session cookies";
  |]

let contexts =
  [|
    ""; " on Safari"; " for long lists"; " after a client navigation"; " in the production bundle";
    " on slow networks"; " when the filter is empty"; " under load"; " on small screens"; " in Firefox";
  |]

let findings =
  [|
    "It happens on about one page load in ten.";
    "The server log shows nothing at the time of the failure.";
    "A user reported it twice this week.";
    "The profile points to a long task in the client entry.";
    "It started after the last release.";
    "The old code path had the same problem, but it was hidden by a cache.";
    "We can reproduce it with the network throttled to Slow 3G.";
    "The fix should keep the public API as it is.";
  |]

let next_steps =
  [|
    "Write a failing test first.";
    "Check how the browser check covers this case.";
    "Measure before and after the change.";
    "Ask the design team for a mockup.";
    "Split the work into two pull requests.";
    "Look at how other frameworks solve it.";
    "Keep the change small and behind no flag.";
  |]

let remarks =
  [|
    "I can reproduce this on main.";
    "Same here, on a clean checkout.";
    "This looks related to the change in the router last week.";
    "I added a test that fails without the fix.";
    "The profile shows 40 ms in the scheduler for this case.";
    "Could we land the smaller part first?";
    "I am not sure this is a bug: the docs describe this behaviour.";
    "Moving this to the next cycle.";
    "Pushed a fix to a branch, please have a look.";
    "The fix works for me in Firefox and Chrome.";
    "Safari still shows the old state after a reload.";
    "Let us pair on this tomorrow.";
    "I left a few comments on the pull request.";
    "Closing the loop: the regression came from the cache key.";
    "Benchmarks look the same before and after.";
    "The bundle grows by 120 bytes with this change.";
    "Can we add this case to the browser check?";
    "Good catch, thanks.";
    "The error message could say which field failed.";
    "This needs a note in the changelog.";
    "I would keep the old name and add an alias.";
    "Done on my side, ready for review.";
    "Reopening: it fails again on the second navigation.";
    "The root cause is a missing key in the list.";
  |]

let statuses = Issue.[| Backlog; Backlog; Todo; Todo; Todo; In_progress; In_progress; Done; Done; Canceled |]
let priorities = Issue.[| No_priority; Urgent; High; High; Medium; Medium; Medium; Low; Low |]

let mix seed =
  let value = (seed lxor 0x5bd1e995) * 0x27d4eb2d land 0x3FFFFFFF in
  let value = (value lxor (value lsr 15)) * 0x165667b1 land 0x3FFFFFFF in
  value lxor (value lsr 13)

let pick seed choices = choices.(mix seed mod Array.length choices)

let date seed =
  let month = pick seed [| "Sep"; "Oct"; "Oct"; "Nov" |] in
  let last_day = if month = "Nov" then 6 else 28 in
  Printf.sprintf "%s %d" month (1 + (mix (seed + 1) mod last_day))

let snippets =
  [|
    ("ocaml", "let rec retry ~attempts run =\n  match run () with\n  | Ok value -> Ok value\n  | Error _ when attempts > 1 -> retry ~attempts:(attempts - 1) run\n  | Error message -> Error message");
    ("typescript", "const started = performance.now();\nawait page.goto(url, { waitUntil: \"networkidle\" });\nconsole.log(`loaded in ${performance.now() - started} ms`);");
    ("javascript", "document.querySelectorAll(\"yuka-island\").forEach((island) => {\n  console.log(island.dataset.name, island.dataset.start);\n});");
    ("shell", "make build && make test\nPORT=8220 make e2e");
    ("json", "{\n  \"status\": \"In_progress\",\n  \"priority\": \"High\",\n  \"labels\": [\"perf\", \"server\"]\n}");
    ("css", ".row:hover {\n  background: var(--bg-hover);\n}");
  |]

let code_block seed =
  let language, code = pick seed snippets in
  Printf.sprintf "```%s\n%s\n```" language code

let markdown_description seed =
  Printf.sprintf "%s\n\n## Steps\n\n1. %s\n2. %s\n\n%s\n\n| Browser | Result |\n| --- | --- |\n| Chrome | %s |\n| Firefox | %s |"
    (pick (seed 1) findings) (pick (seed 2) next_steps) (pick (seed 3) next_steps) (code_block (seed 4))
    (pick (seed 5) [| "fails"; "passes" |]) (pick (seed 6) [| "fails"; "passes"; "not tested" |])

let markdown_comment seed =
  match mix (seed 1) mod 3 with
  | 0 -> Printf.sprintf "%s\n\n%s" (pick (seed 2) remarks) (code_block (seed 3))
  | 1 -> Printf.sprintf "Two notes:\n\n- %s\n- %s" (pick (seed 2) remarks) (pick (seed 3) remarks)
  | _ -> Printf.sprintf "**%s** See `%s` in the [docs](https://github.com/davesnx/yuka)." (pick (seed 2) remarks) (pick (seed 3) [| "Yuka.Await"; "Yuka.each"; "Yuka.State.set" |])

let issue ~(users : User.t array) number : Issue.t =
  let seed salt = (number * 7919) + salt in
  let title =
    verbs.(((number - 1) / Array.length subjects) mod Array.length verbs)
    ^ " "
    ^ subjects.((number - 1) mod Array.length subjects)
    ^ pick (seed 1) contexts
  in
  let extra_labels = List.init (mix (seed 2) mod 3) (fun index -> pick (seed (3 + index)) labels) in
  {
    id = Printf.sprintf "%s-%d" (Workspace.issue_prefix Stress) number;
    workspace = Stress;
    title;
    description =
      (if mix (seed 13) mod 4 = 0 then markdown_description (fun salt -> seed (20 + salt))
       else pick (seed 6) findings ^ " " ^ pick (seed 7) next_steps);
    status = pick (seed 8) statuses;
    priority = pick (seed 9) priorities;
    assignee = (if mix (seed 10) mod 4 = 0 then None else Some (pick (seed 11) users));
    labels = List.sort_uniq compare (labels.((number - 1) mod Array.length labels) :: extra_labels);
    created_at = date (seed 12);
  }

let issues ~users = List.init issue_count (fun index -> issue ~users (index + 1))

let comments ~(users : User.t array) (issue : Issue.t) : Comment.t list =
  let number = Issue.number issue in
  if number < 1 || number > issue_count then []
  else
    List.init comments_per_issue (fun index ->
        let seed salt = (number * 100_003) + (index * 31) + salt in
        let sentences = 1 + (mix (seed 1) mod 3) in
        let first = mix (seed 2) in
        let body =
          if mix (seed 6) mod 8 = 0 then markdown_comment (fun salt -> seed (10 + salt))
          else
            String.concat " "
              (List.init sentences (fun sentence -> remarks.((first + (sentence * 7)) mod Array.length remarks)))
        in
        {
          Comment.id = Printf.sprintf "%s-c%d" issue.id (index + 1);
          author = pick (seed 5) users;
          body = Markdown.render body;
          created_at = Printf.sprintf "Nov %d" (1 + (index * 6 / comments_per_issue));
        })
